// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {Currency, IUniswapV4PoolManager, IUnlockCallback} from "./interfaces/IUniswapV4PoolManager.sol";

/// @title Arbitrageur — a minimal, owner-controlled taker for any SwapVM router
/// @notice A general-purpose taker that any SwapVM router order can be executed against,
///         callable by its owner with plain, ABI-typed arguments -- the on-chain half of a
///         Pathfinder-style trading stand-in. Decision logic (when a trade is profitable, how
///         large to size it) lives off-chain in `packages/arbitrageur` instead, so it can be
///         iterated on without a redeploy.
/// @dev Every swap uses `isFirstTransferFromTaker` + `useTransferFromAndAquaPush` with both
///      `hasPreTransferInCallback`/`hasPreTransferOutCallback` left `false` (see `_takerTraits`),
///      so the owner never needs to implement `ITakerCallbacks` and can be a plain EOA.
///      `TakerTraitsLib.build`'s packed, bit-shifted encoding (`lib/swap-vm/src/libs/TakerTraits.sol`)
///      is built once here, in Solidity, reusing the same library the rest of this codebase
///      already relies on, rather than hand-replicated off-chain with no test coverage.
/// @dev `executeArbitrage` holds no standing balance between calls: it pulls exactly `amountIn`
///      from the owner immediately before swapping, and `tokenOut` settles directly to the owner
///      (`to: msg.sender`). `executeFlashArbitrage` borrows `amountIn` from Uniswap V4's
///      PoolManager instead of pulling it from the owner -- see that function's own doc comment
///      -- and, by design, leaves any profit sitting on this contract afterward; `sweep` is how
///      that profit (and anything stranded here by mistake) gets collected.
contract Arbitrageur is Ownable, IUnlockCallback {
    using SafeERC20 for IERC20;

    ISwapVM public immutable ROUTER;
    IUniswapV4PoolManager public immutable POOL_MANAGER;

    /// @dev Threaded through `unlockCallback` as the PoolManager's opaque `data`, since the
    ///      callback's own signature is fixed by `IUnlockCallback`. `fyndTarget`/`fyndSpender`
    ///      are kept separate since an aggregator's calldata may target one contract while a
    ///      different one (e.g. a Permit2-style allowance holder) needs the approval.
    struct FlashArbParams {
        ISwapVM.Order order;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minCurveAmountOut;
        address fyndTarget;
        address fyndSpender;
        bytes fyndCalldata;
        uint40 deadline;
    }

    event ArbitrageExecuted(
        bytes32 indexed orderHash,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event FlashArbitrageExecuted(
        bytes32 indexed orderHash,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 curveAmountOut,
        uint256 repaid,
        uint256 profit
    );
    event Swept(address indexed token, uint256 amount, address indexed to);

    error ArbitrageurUnauthorizedFlashLoanCallback(address caller);
    error ArbitrageurFyndCallFailed(bytes reason);
    error ArbitrageurInsufficientRepayment(uint256 owed, uint256 actual);

    constructor(address router, address poolManager, address owner_) Ownable(owner_) {
        ROUTER = ISwapVM(router);
        POOL_MANAGER = IUniswapV4PoolManager(poolManager);
    }

    /// @notice Simulates an exact-in trade against `order` without moving any tokens -- SwapVM's
    ///         own `quote()` is explicitly documented as callable in a static context, so the
    ///         off-chain server can call this via `eth_call` to price a candidate trade size
    ///         before ever submitting a real transaction.
    function quoteExactIn(ISwapVM.Order calldata order, address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        (, amountOut,) = ROUTER.quote(order, tokenIn, tokenOut, amountIn, _takerTraits(address(0), "", 0));
    }

    /// @notice Executes one real exact-in trade against `order`: pulls `amountIn` of `tokenIn`
    ///         from the caller (who must have approved this contract first), and forwards
    ///         whatever `tokenOut` the router settles directly back to the caller.
    /// @param minAmountOut Slippage floor -- SwapVM's own `TakerTraitsLib.validate()` already
    ///        reverts (`TakerTraitsInsufficientMinOutputAmount`) if the settled amount falls
    ///        short, so this function does not re-check it itself.
    /// @param deadline Unix timestamp after which SwapVM reverts the trade
    ///        (`TakerTraitsDeadlineExpired`); 0 disables the check.
    function executeArbitrage(
        ISwapVM.Order calldata order,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint40 deadline
    ) external onlyOwner returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(ROUTER), amountIn);

        bytes32 orderHash;
        (, amountOut, orderHash) = ROUTER.swap(
            order, tokenIn, tokenOut, amountIn, _takerTraits(msg.sender, abi.encodePacked(minAmountOut), deadline)
        );

        emit ArbitrageExecuted(orderHash, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Same trade `executeArbitrage` runs, except `amountIn` of `tokenIn` is borrowed
    ///         from Uniswap V4's PoolManager (no flash-loan fee at all -- see
    ///         `IUniswapV4PoolManager.sol`) instead of pulled from the owner -- the owner never
    ///         needs to hold or approve `tokenIn` at all. `params.fyndCalldata`, built off-chain
    ///         by `packages/arbitrageur` against a running Fynd instance, converts the curve's
    ///         `tokenOut` proceeds back into `tokenIn` on the open market so the loan can be
    ///         repaid within the same transaction -- see `unlockCallback`.
    function executeFlashArbitrage(FlashArbParams calldata params) external onlyOwner {
        POOL_MANAGER.unlock(abi.encode(params));
    }

    /// @notice The PoolManager's unlock callback -- reachable only as a direct, synchronous
    ///         consequence of `executeFlashArbitrage`'s own call into `POOL_MANAGER.unlock`, so
    ///         `msg.sender == POOL_MANAGER` is the entire access-control story here.
    /// @dev The safety property that actually protects borrowed principal isn't the slippage
    ///      checks below -- it's that the repayment check must find at least `owed` `tokenIn` on
    ///      this contract, or the whole transaction (including the curve trade) reverts. A
    ///      worse-than-expected Fynd route costs gas on a failed attempt, never principal.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(POOL_MANAGER), ArbitrageurUnauthorizedFlashLoanCallback(msg.sender));

        FlashArbParams memory p = abi.decode(data, (FlashArbParams));

        // 0. Borrow: `take` moves `amountIn` of tokenIn from the manager to this contract,
        // recording a debt this call must repay (via sync + transfer + settle below) before
        // `unlock` returns, or the whole call reverts with `CurrencyNotSettled`.
        POOL_MANAGER.take(Currency.wrap(p.tokenIn), address(this), p.amountIn);

        // 1. tokenIn -> tokenOut against the PM curve, proceeds settling here.
        IERC20(p.tokenIn).forceApprove(address(ROUTER), p.amountIn);
        (, uint256 curveAmountOut, bytes32 orderHash) = ROUTER.swap(
            p.order,
            p.tokenIn,
            p.tokenOut,
            p.amountIn,
            _takerTraits(address(this), abi.encodePacked(p.minCurveAmountOut), p.deadline)
        );

        // 2. tokenOut -> tokenIn via whatever route Fynd found, executed as an arbitrary
        // external call -- this contract has no opinion on which DEXs that route touches.
        IERC20(p.tokenOut).forceApprove(p.fyndSpender, curveAmountOut);
        (bool ok, bytes memory ret) = p.fyndTarget.call(p.fyndCalldata);
        require(ok, ArbitrageurFyndCallFailed(ret));
        // The off-chain-built calldata isn't guaranteed to spend the full approval (e.g. the
        // curve leg settled for slightly more than the off-chain quote expected) -- reset
        // regardless of how much was actually spent so no allowance to `fyndSpender` survives.
        IERC20(p.tokenOut).forceApprove(p.fyndSpender, 0);

        // 3. Repay the loan -- no fee, so exactly `amountIn` is owed. `sync` before transferring
        // (it snapshots the manager's balance pre-repayment, so `settle` can tell how much of
        // the transfer below actually counts), then transfer, then `settle` to zero the debt.
        uint256 owed = p.amountIn;
        uint256 actual = IERC20(p.tokenIn).balanceOf(address(this));
        require(actual >= owed, ArbitrageurInsufficientRepayment(owed, actual));
        POOL_MANAGER.sync(Currency.wrap(p.tokenIn));
        IERC20(p.tokenIn).safeTransfer(address(POOL_MANAGER), owed);
        POOL_MANAGER.settle();

        emit FlashArbitrageExecuted(orderHash, p.tokenIn, p.tokenOut, p.amountIn, curveAmountOut, owed, actual - owed);
        return "";
    }

    /// @notice Recovers any token balance left on this contract by mistake -- not part of the
    ///         normal flow (see this contract's own top-level doc comment). Also how
    ///         `executeFlashArbitrage`'s profit (whatever `tokenIn` remains after repayment) is
    ///         collected -- there's no separate profit-forwarding step in the flash-loan path.
    function sweep(address token, uint256 amount, address to) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit Swept(token, amount, to);
    }

    /// @dev Every field this contract never varies (`shouldUnwrapWeth`, hooks, callbacks,
    ///      signature) is left at its zero/false/empty default -- both callback flags being
    ///      `false` means no `ITakerCallbacks` implementation is ever invoked, and
    ///      `order.traits.useAquaInsteadOfSignature()` (required by every PM strategy, see
    ///      `PortfolioManagerRouter`) means no signature is needed either.
    function _takerTraits(address to, bytes memory threshold, uint40 deadline) private view returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(this),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: true,
                useTransferFromAndAquaPush: true,
                threshold: threshold,
                to: to,
                deadline: deadline,
                hasPreTransferInCallback: false,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
    }
}
