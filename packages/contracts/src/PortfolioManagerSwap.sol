// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context, ContextLib} from "swap-vm/libs/VM.sol";
import {Fee, BPS as FEE_BPS} from "swap-vm/instructions/Fee.sol";
import {PortfolioManagerArgsBuilder, PM_BPS} from "./PortfolioManagerArgsBuilder.sol";
import {PortfolioManagerPricing} from "./PortfolioManagerPricing.sol";
import {PortfolioManagerProgramBuilder} from "./PortfolioManagerProgramBuilder.sol";

/// @title PortfolioManagerSwap — the real weighted-curve SwapVM instruction, per PRICING.md
/// @notice Wires PortfolioManagerArgsBuilder's declared universe and PortfolioManagerPricing's
///         curve math into an actual instruction: reads real wallet balances via plain
///         `balanceOf` (ADR-0002 — never AQUA's own ledger via ctx.swap.balanceIn/Out, which is
///         a same-strategy-only accounting entry, not a wallet-wide reading), resolves
///         tokenIn's/tokenOut's declared weight, and prices the trade.
/// @dev Single-token-per-group scope only (matches PortfolioManagerArgsBuilder's current
///      scope) — multi-token oracle-valued groups (ADR-0003) are a routing detail PRICING.md
///      explicitly defers to a later milestone, not decided here.
/// @dev The 1inch DAO protocol fee (1IP-103's tiered cut) is pulled directly from
///      inside this instruction's own execution, not composed as a separate chainable
///      instruction — `Aqua.ship()` is permissionless, so a program that only invokes this
///      opcode (skipping any separate fee instruction) would otherwise pay nothing. Baking the
///      pull in here means anyone shipping a strategy that actually uses this curve pays the
///      fee, regardless of what tooling built their program bytes. Inherits `Fee` purely to
///      reuse its `_AQUA` reference, `BPS` scale, and `ProtocolFeeSkipped` event — not to call
///      any of its instruction functions, which wrap "the rest of the program" in a way that
///      only composes correctly across separate chained instructions, not within one function
///      body that still has its own pricing left to do afterward.
contract PortfolioManagerSwap is Fee {
    using ContextLib for Context;

    error PortfolioManagerSwapTokenNotDeclared(address token);
    error PortfolioManagerSwapRecomputeDetected();

    uint256 private constant WAD = 1e18;
    /// @dev Converts PortfolioManagerArgsBuilder's `feeBps` (PM_BPS = 1e9 scale) into
    ///      PortfolioManagerPricing's `feeWad` (WAD = 1e18 scale) — both scales represent
    ///      100% at their own constant, so this ratio is exact with no rounding.
    uint256 private constant FEE_WAD_PER_BPS = WAD / PM_BPS;

    constructor(address aqua) Fee(aqua) {}

    /// @param args Encoded via PortfolioManagerArgsBuilder.build (tokens, weights, feeBps)
    /// @dev Not declared `view`: Solidity won't implicitly widen a view-typed function-pointer
    ///      array literal to the unqualified array type `_opcodes()` needs (same reasoning as
    ///      `BasketXYCSwap.sol`'s identical note).
    function _portfolioManagerSwapXD(Context memory ctx, bytes calldata args) internal {
        (address[] memory tokens, uint256[] memory weights, uint32 feeBps) = PortfolioManagerArgsBuilder.parse(args);

        PortfolioManagerPricing.Quote memory quote = PortfolioManagerPricing.Quote({
            balanceIn: IERC20(ctx.query.tokenIn).balanceOf(ctx.query.maker),
            balanceOut: IERC20(ctx.query.tokenOut).balanceOf(ctx.query.maker),
            weightIn: _weightOf(tokens, weights, ctx.query.tokenIn),
            weightOut: _weightOf(tokens, weights, ctx.query.tokenOut),
            feeWad: uint256(feeBps) * FEE_WAD_PER_BPS
        });

        uint32 daoBps = PortfolioManagerProgramBuilder.daoFeeBps(feeBps);
        uint256 daoAmount;

        if (ctx.query.isExactIn) {
            require(ctx.swap.amountOut == 0, PortfolioManagerSwapRecomputeDetected());
            // The taker's full, requested amountIn — the curve prices off it net of the
            // protocol pull, but SwapVM's own settlement must still collect the full amount
            // from the taker, so it's restored below (matches Fee.sol's own _feeAmountIn
            // exact-in branch, minus the wrap-the-rest-of-program recursion we don't need
            // here — nothing runs after this instruction).
            uint256 fullAmountIn = ctx.swap.amountIn;
            daoAmount = fullAmountIn * daoBps / FEE_BPS;
            ctx.swap.amountIn = fullAmountIn - daoAmount;
            ctx.swap.amountOut = PortfolioManagerPricing.exactIn(quote, ctx.swap.amountIn);
            ctx.swap.amountIn = fullAmountIn;
        } else {
            require(ctx.swap.amountIn == 0, PortfolioManagerSwapRecomputeDetected());
            // Exact-out: the curve first computes the amountIn needed including the LP's own
            // curve fee (PortfolioManagerPricing.exactOut already grosses that up internally),
            // then the protocol fee is grossed up on top of that — mirrors Fee.sol's own
            // exact-out branch, which fees only once the swap amount is known.
            ctx.swap.amountIn = PortfolioManagerPricing.exactOut(quote, ctx.swap.amountOut);
            daoAmount = ctx.swap.amountIn * daoBps / (FEE_BPS - daoBps);
            ctx.swap.amountIn += daoAmount;
        }

        // Best-effort, matching Fee.sol's own _tryPullFee rationale exactly: reverting on an
        // uncollectible fee would make a one-sided position untradable (OpenZeppelin M-09,
        // Theori #10). Skipped entirely in quote() (isStaticContext) — same divergence
        // Fee.sol's transfer-performing variants document.
        if (daoAmount != 0 && !ctx.vm.isStaticContext) {
            address recipient = PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS;
            try _AQUA.pull(ctx.query.maker, ctx.query.orderHash, ctx.query.tokenIn, daoAmount, recipient) {
                ctx.swap.amountNetPulled += daoAmount;
            } catch {
                emit ProtocolFeeSkipped(ctx.query.orderHash, ctx.query.tokenIn, recipient, daoAmount);
            }
        }
    }

    /// @dev A token not found here was never part of the declared universe — the sole guard for
    ///      that now, since `balanceOf` above is a plain, ungated read. Reachable in practice:
    ///      `ship()`'s own `tokens` array can include a token this contract's declared universe
    ///      never gave a weight to (an encoding mismatch, not just a malicious taker) —
    ///      `AQUA.safeBalances()` only checks the token is part of the shipped strategy, not that
    ///      it matches this instruction's own args.
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
