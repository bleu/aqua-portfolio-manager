// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {Currency, IUniswapV4PoolManager} from "./interfaces/IUniswapV4PoolManager.sol";
import {IArbitrageur} from "./interfaces/IArbitrageur.sol";

/// @title Arbitrageur — a minimal, owner-controlled taker for any SwapVM router
/// @notice Executes SwapVM orders on the owner's behalf; sizing and profitability decisions live
///         off-chain in `apps/arbitrageur`.
/// @dev Every swap uses `_takerTraits` with both transfer callbacks left `false`, so the owner
///      can be a plain EOA. `executeFlashArbitrage` borrows `amountIn` from Uniswap V4's
///      PoolManager and, by design, leaves any profit on this contract -- `sweep` collects it
///      (see `sweep`'s own doc comment).
contract Arbitrageur is Ownable, IArbitrageur {
    using SafeERC20 for IERC20;

    ISwapVM public immutable ROUTER;
    IUniswapV4PoolManager public immutable POOL_MANAGER;

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

    /// @notice Executes one real exact-in trade against `order`: `amountIn` of `tokenIn` is
    ///         borrowed from Uniswap V4's PoolManager (no flash-loan fee at all -- see
    ///         `IUniswapV4PoolManager.sol`) and repaid within the same transaction -- the owner
    ///         never needs to hold or approve `tokenIn` at all. `params.fyndCalldata`, built off-chain
    ///         by `apps/arbitrageur` against a running Fynd instance, converts the curve's
    ///         `tokenOut` proceeds back into `tokenIn` on the open market so the loan can be
    ///         repaid within the same transaction -- see `unlockCallback`.
    function executeFlashArbitrage(FlashArbParams calldata params) external onlyOwner {
        POOL_MANAGER.unlock(abi.encode(params));
    }

    /// @notice The PoolManager's unlock callback -- reachable only as a direct, synchronous
    ///         consequence of `executeFlashArbitrage`'s own call into `POOL_MANAGER.unlock`, so
    ///         `msg.sender == POOL_MANAGER` is the entire access-control story here.
    /// @dev The safety property that actually protects borrowed principal isn't the slippage
    ///      checks below -- it's that the repayment check must find `owed` `tokenIn` *gained*
    ///      during this call, or the whole transaction (including the curve trade) reverts. A
    ///      worse-than-expected Fynd route costs gas on a failed attempt, never principal. Gained
    ///      is measured against the balance snapshotted before the borrow, not the absolute
    ///      balance after -- a prior flash arbitrage's unswept profit sitting on this contract
    ///      must never be able to mask a losing trade.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(POOL_MANAGER), ArbitrageurUnauthorizedFlashLoanCallback(msg.sender));

        FlashArbParams memory p = abi.decode(data, (FlashArbParams));
        uint256 balanceBeforeBorrow = IERC20(p.tokenIn).balanceOf(address(this));

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

        // 3. Repay the loan -- no fee, so exactly `amountIn` is owed. `gained` is this trade's own
        // contribution, not the contract's absolute tokenIn balance (see this function's own doc
        // comment). `sync` before transferring (it snapshots the manager's balance
        // pre-repayment, so `settle` can tell how much of the transfer below actually counts),
        // then transfer, then `settle` to zero the debt.
        uint256 owed = p.amountIn;
        uint256 gained = IERC20(p.tokenIn).balanceOf(address(this)) - balanceBeforeBorrow;
        require(gained >= owed, ArbitrageurInsufficientRepayment(owed, gained));
        POOL_MANAGER.sync(Currency.wrap(p.tokenIn));
        IERC20(p.tokenIn).safeTransfer(address(POOL_MANAGER), owed);
        POOL_MANAGER.settle();

        emit FlashArbitrageExecuted(orderHash, p.tokenIn, p.tokenOut, p.amountIn, curveAmountOut, owed, gained - owed);
        return "";
    }

    /// @notice Collects `executeFlashArbitrage`'s profit -- by design left on this contract
    ///         instead of forwarded automatically, same as any token stranded here by mistake.
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
