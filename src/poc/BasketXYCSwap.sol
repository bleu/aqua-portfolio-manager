// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev PoC only — not the license this repo ships under (see ../../LICENSE). This file only
/// exists to answer a design question: what does swapVM need to price tokenIn -> tokenOut
/// while also accounting for a third token's balance. Not part of any milestone deliverable.

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Calldata } from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";
import { IAqua } from "aqua/interfaces/IAqua.sol";
import { Context, ContextLib } from "swap-vm/libs/VM.sol";

library BasketXYCSwapArgsBuilder {
    using Calldata for bytes;

    error BasketXYCSwapMissingBasketTokenArg();

    function build(address basketToken) internal pure returns (bytes memory) {
        return abi.encodePacked(basketToken);
    }

    function parse(bytes calldata args) internal pure returns (address basketToken) {
        basketToken = address(bytes20(args.slice(0, 20, BasketXYCSwapMissingBasketTokenArg.selector)));
    }
}

/// @title BasketXYCSwap — PoC: xy=k where the "y" side is a basket of 2 tokens, not 1
/// @notice The swap itself still only moves tokenIn and tokenOut, exactly like plain XYCSwap.
///         The one change: before applying the xy=k formula, this reads a third token's Aqua
///         balance (`basketToken`, e.g. token C, grouped with tokenOut) and adds it to
///         tokenOut's balance before pricing. basketToken is read-only here — nothing about it
///         is pulled, pushed, or otherwise moved by this instruction; only tokenIn/tokenOut move.
contract BasketXYCSwap {
    using ContextLib for Context;

    error BasketXYCSwapRecomputeDetected();
    error BasketXYCSwapRequiresNonZeroBalances(uint256 balanceIn, uint256 effectiveBalanceOut);

    IAqua internal immutable _AQUA;

    constructor(address aqua) {
        _AQUA = IAqua(aqua);
    }

    /// @param args.basketToken | 20 bytes — third token, grouped with tokenOut, read but never moved
    /// @dev Not declared `view`: Solidity won't implicitly widen a view-typed function-pointer
    ///      array literal to the unqualified array type _opcodes() needs (see PoCOpcodes.sol).
    function _basketXycSwapXD(Context memory ctx, bytes calldata args) internal {
        address basketToken = BasketXYCSwapArgsBuilder.parse(args);

        // The escape hatch: nothing in VM.sol's Context/SwapRegisters carries a third balance.
        // An instruction that wants one just holds its own IAqua reference and reads it directly —
        // the same pattern Fee.sol already uses to reach Aqua for its own purposes.
        (uint256 basketBalance,) = _AQUA.rawBalances(ctx.query.maker, address(this), ctx.query.orderHash, basketToken);
        uint256 effectiveBalanceOut = ctx.swap.balanceOut + basketBalance;

        require(
            ctx.swap.balanceIn > 0 && effectiveBalanceOut > 0,
            BasketXYCSwapRequiresNonZeroBalances(ctx.swap.balanceIn, effectiveBalanceOut)
        );

        if (ctx.query.isExactIn) {
            require(ctx.swap.amountOut == 0, BasketXYCSwapRecomputeDetected());
            // Floor division for tokenOut is desired behavior — same rounding direction as XYCSwap.
            ctx.swap.amountOut = (ctx.swap.amountIn * effectiveBalanceOut) / (ctx.swap.balanceIn + ctx.swap.amountIn);
        } else {
            require(ctx.swap.amountIn == 0, BasketXYCSwapRecomputeDetected());
            // Ceiling division for tokenIn is desired behavior — same rounding direction as XYCSwap.
            ctx.swap.amountIn = Math.ceilDiv(
                ctx.swap.amountOut * ctx.swap.balanceIn,
                (effectiveBalanceOut - ctx.swap.amountOut)
            );
        }
    }
}
