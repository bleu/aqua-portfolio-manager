// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Context, ContextLib} from "swap-vm/libs/VM.sol";
import {ExposureReader} from "./ExposureReader.sol";
import {PortfolioManagerArgsBuilder, PM_BPS} from "./PortfolioManagerArgsBuilder.sol";
import {PortfolioManagerPricing} from "./PortfolioManagerPricing.sol";

/// @title PortfolioManagerSwap — the real weighted-curve SwapVM instruction, per PRICING.md
/// @notice Wires PortfolioManagerArgsBuilder's declared universe and PortfolioManagerPricing's
///         curve math into an actual instruction: reads real wallet balances via
///         ExposureReader (ADR-0002 — never AQUA's own ledger via ctx.swap.balanceIn/Out,
///         which is a same-strategy-only accounting entry, not a wallet-wide reading),
///         resolves tokenIn's/tokenOut's declared weight, and prices the trade.
/// @dev Single-token-per-group scope only (matches PortfolioManagerArgsBuilder's current
///      scope, BLEUDEV-281) — multi-token oracle-valued groups (ADR-0003) are a routing detail
///      PRICING.md explicitly defers to a later milestone, not decided here.
/// @dev This instruction's `feeWad` is the LP's own curve fee only. The protocol fee (1inch
///      DAO's tiered cut per 1IP-103) is a separate, additive mechanism composed *before* this
///      instruction in the program (a chained `Fee._aquaProtocolFeeAmountInXD` call,
///      BLEUDEV-327) — this contract has no awareness of it and needs none: whatever
///      `amountIn` survives that pull is what this instruction prices off, exactly as it would
///      price off the taker's raw amount if no protocol fee were composed at all.
contract PortfolioManagerSwap {
    using ContextLib for Context;

    error PortfolioManagerSwapTokenNotDeclared(address token);
    error PortfolioManagerSwapRecomputeDetected();

    uint256 private constant WAD = 1e18;
    /// @dev Converts PortfolioManagerArgsBuilder's `feeBps` (PM_BPS = 1e9 scale) into
    ///      PortfolioManagerPricing's `feeWad` (WAD = 1e18 scale) — both scales represent
    ///      100% at their own constant, so this ratio is exact with no rounding.
    uint256 private constant FEE_WAD_PER_BPS = WAD / PM_BPS;

    /// @param args Encoded via PortfolioManagerArgsBuilder.build (tokens, weights, feeBps)
    /// @dev Not declared `view`: Solidity won't implicitly widen a view-typed function-pointer
    ///      array literal to the unqualified array type `_opcodes()` needs (same reasoning as
    ///      `BasketXYCSwap.sol`'s identical note) — this instruction sits in the same fixed-size
    ///      array as `Fee`'s state-changing pull instructions, so all entries must share one
    ///      mutability.
    function _portfolioManagerSwapXD(Context memory ctx, bytes calldata args) internal {
        (address[] memory tokens, uint256[] memory weights, uint32 feeBps) = PortfolioManagerArgsBuilder.parse(args);

        PortfolioManagerPricing.Quote memory quote = PortfolioManagerPricing.Quote({
            balanceIn: ExposureReader.balanceOf(ctx.query.tokenIn, ctx.query.maker, tokens),
            balanceOut: ExposureReader.balanceOf(ctx.query.tokenOut, ctx.query.maker, tokens),
            weightIn: _weightOf(tokens, weights, ctx.query.tokenIn),
            weightOut: _weightOf(tokens, weights, ctx.query.tokenOut),
            feeWad: uint256(feeBps) * FEE_WAD_PER_BPS
        });

        if (ctx.query.isExactIn) {
            require(ctx.swap.amountOut == 0, PortfolioManagerSwapRecomputeDetected());
            ctx.swap.amountOut = PortfolioManagerPricing.exactIn(quote, ctx.swap.amountIn);
        } else {
            require(ctx.swap.amountIn == 0, PortfolioManagerSwapRecomputeDetected());
            ctx.swap.amountIn = PortfolioManagerPricing.exactOut(quote, ctx.swap.amountOut);
        }
    }

    /// @dev `tokens`/`weights` already passed `PortfolioManagerArgsBuilder.parse`'s
    ///      sum-to-WAD re-validation; a token not found here means `ctx.query.tokenIn`/
    ///      `tokenOut` was never part of the declared universe at all.
    function _weightOf(address[] memory tokens, uint256[] memory weights, address token)
        private
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) return weights[i];
        }
        revert PortfolioManagerSwapTokenNotDeclared(token);
    }
}
