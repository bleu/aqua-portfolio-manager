// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";

/// @title Arbitrageur — a minimal, owner-controlled taker for any SwapVM router (BLEUDEV-349)
/// @notice Real pathfinder-style routing (1inch's own) is closed-source with no self-hosted or
///         forked-mainnet-testable equivalent (confirmed directly with 1inch, see
///         `docs/ARCHITECTURE.md`'s Milestone 1 section) -- there is no way to test that a
///         deployed PM strategy is actually tradeable the way a real taker/solver would trade it,
///         short of building a stand-in. This contract is that stand-in's on-chain half: a
///         general-purpose taker that any SwapVM router order can be executed against, callable
///         by its owner with plain, ABI-typed arguments. The decision logic (when a trade is
///         profitable, how large to size it) is deliberately kept off-chain, in
///         `packages/arbitrageur`'s TypeScript server -- exactly the part a real Pathfinder-style
///         router would own, and the part worth iterating on without a redeploy.
/// @dev All swaps use SwapVM's `useTransferFromAndAquaPush` taker path (plain `transferFrom` +
///      `Aqua.push`, no `ITakerCallbacks` implementation needed) specifically so the *owner* can
///      be a plain EOA -- signing and submitting transactions directly -- rather than needing to
///      be a contract capable of receiving a mid-swap callback. `TakerTraitsLib.build`'s packed,
///      bit-shifted encoding is subtle enough (see `lib/swap-vm/src/libs/TakerTraits.sol`) that
///      hand-replicating it off-chain would be a real correctness risk with no test coverage
///      protecting it; every call here instead builds it once, in Solidity, reusing the exact
///      same library the rest of this codebase already relies on and tests.
/// @dev Deliberately does not hold a standing token balance between calls: `executeArbitrage`
///      pulls exactly `amountIn` from the owner immediately before swapping, and `tokenOut` is
///      sent directly to the owner by the router's own settlement (`to: msg.sender` at call
///      time), not routed back through this contract. `sweep` exists only to recover anything
///      that ends up here by mistake (e.g. dust from a future taker-traits change), not as part
///      of the normal flow.
contract Arbitrageur is Ownable {
    using SafeERC20 for IERC20;

    ISwapVM public immutable ROUTER;

    event ArbitrageExecuted(
        bytes32 indexed orderHash,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address router, address owner_) Ownable(owner_) {
        ROUTER = ISwapVM(router);
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

    /// @notice Recovers any token balance left on this contract by mistake -- not part of the
    ///         normal flow (see this contract's own top-level doc comment).
    function sweep(address token, uint256 amount, address to) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @dev Every field this contract never varies (`shouldUnwrapWeth`, hooks, callbacks,
    ///      signature) is left at its zero/false/empty default -- `useTransferFromAndAquaPush`
    ///      means no `ITakerCallbacks` implementation is ever invoked, and
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
