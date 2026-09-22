// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @dev Reference prototype only. Reads a third token's Aqua balance when pricing a two-token swap.
///      This file retains its original license. See ../../../LICENSE for the project license.

import {FixedPointMath} from "./utils/FixedPointMath.sol";
import {Calldata} from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";
import {IAqua} from "aqua/interfaces/IAqua.sol";
import {Context, ContextLib} from "swap-vm/libs/VM.sol";

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

/// @title BasketXYCSwap
/// @notice Prices xy=k with a third token's raw Aqua balance added to the output reserve.
/// @dev Only tokenIn and tokenOut move. This prototype assumes equal token values and performs no oracle conversion.
contract BasketXYCSwap {
    using ContextLib for Context;

    error BasketXYCSwapRecomputeDetected();
    error BasketXYCSwapRequiresNonZeroBalances(uint256 balanceIn, uint256 effectiveBalanceOut);

    IAqua internal immutable _AQUA;

    constructor(address aqua) {
        _AQUA = IAqua(aqua);
    }

    /// @param args.basketToken The 20-byte address of the read-only token added to the output reserve.
    /// @dev The opcode table requires a non-view function pointer.
    function _basketXycSwapXD(Context memory ctx, bytes calldata args) internal {
        address basketToken = BasketXYCSwapArgsBuilder.parse(args);

        // Instructions can read balances outside the two-token Context through their own Aqua reference.
        (uint256 basketBalance,) = _AQUA.rawBalances(ctx.query.maker, address(this), ctx.query.orderHash, basketToken);
        uint256 effectiveBalanceOut = ctx.swap.balanceOut + basketBalance;

        require(
            ctx.swap.balanceIn > 0 && effectiveBalanceOut > 0,
            BasketXYCSwapRequiresNonZeroBalances(ctx.swap.balanceIn, effectiveBalanceOut)
        );

        if (ctx.query.isExactIn) {
            require(ctx.swap.amountOut == 0, BasketXYCSwapRecomputeDetected());
            // Floor division for tokenOut is desired behavior — same rounding direction as XYCSwap.
            ctx.swap.amountOut = FixedPointMath.mulDivDown(
                ctx.swap.amountIn, effectiveBalanceOut, ctx.swap.balanceIn + ctx.swap.amountIn
            );
        } else {
            require(ctx.swap.amountIn == 0, BasketXYCSwapRecomputeDetected());
            // Ceiling division for tokenIn is desired behavior — same rounding direction as XYCSwap.
            ctx.swap.amountIn = FixedPointMath.mulDivUp(
                ctx.swap.amountOut, ctx.swap.balanceIn, effectiveBalanceOut - ctx.swap.amountOut
            );
        }
    }
}
