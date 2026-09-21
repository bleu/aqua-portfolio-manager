// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Context, ContextLib} from "swap-vm/libs/VM.sol";
import {Fee, BPS as FEE_BPS} from "swap-vm/instructions/Fee.sol";
import {IPortfolioManagerSwap} from "./interfaces/IPortfolioManagerSwap.sol";
import {IPortfolioManagerStrategyValidator} from "./interfaces/IPortfolioManagerStrategyValidator.sol";
import {PortfolioManagerArgsCodec} from "./utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerPricing} from "./utils/PortfolioManagerPricing.sol";
import {PortfolioManagerFee} from "./utils/PortfolioManagerFee.sol";
import {OracleAdapter} from "./utils/OracleAdapter.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {FixedPointMath} from "./utils/FixedPointMath.sol";

/// @title PortfolioManagerSwap — the real weighted-curve SwapVM instruction, per PRICING.md
/// @notice Wires PortfolioManagerArgsCodec's declared groups and PortfolioManagerPricing's
///         curve math into an actual instruction: reads real wallet balances via plain
///         `balanceOf` (ADR-0002 — never AQUA's own ledger via ctx.swap.balanceIn/Out, which is
///         a same-strategy-only accounting entry, not a wallet-wide reading), resolves which
///         declared group tokenIn/tokenOut each belong to, values that group's full member set
///         through `OracleAdapter` (ADR-0003), and prices the trade against the two groups'
///         weights.
/// @dev Real multi-token oracle-valued groups (ADR-0003) — every group, including a
///      single-member one, goes through `OracleAdapter` uniformly (no "skip the oracle"
///      special case), so decimal normalization and price conversion always apply the same
///      way regardless of group size.
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
/// @dev Never deployed on its own -- only ever inherited by `PortfolioManagerOpcodes`.
abstract contract PortfolioManagerSwap is Fee, IPortfolioManagerSwap {
    using ContextLib for Context;

    uint256 private constant WAD = FixedPointMath.WAD;

    /// @dev The multicall validation that's supposed to run alongside `Aqua.ship()` is
    ///      convention, not enforced by `ship()` itself -- this is what lets the swap opcode
    ///      independently check it actually happened, instead of trusting the caller.
    IPortfolioManagerStrategyValidator private immutable STRATEGY_VALIDATOR;

    constructor(address aqua, address strategyValidator) Fee(aqua) {
        STRATEGY_VALIDATOR = IPortfolioManagerStrategyValidator(strategyValidator);
    }

    /// @param args Encoded via PortfolioManagerArgsCodec.build (tokens, weights, feeBps)
    /// @dev Not declared `view`: Solidity won't implicitly widen a view-typed function-pointer
    ///      array literal to the unqualified array type `_opcodes()` needs (same reasoning as
    ///      `BasketXYCSwap.sol`'s identical note).
    function _portfolioManagerSwapXD(Context memory ctx, bytes calldata args) internal {
        // Checked first, before parsing args, so an unattested strategy never pays parse cost.
        // The flag is monotonic, so re-checking every swap (not just the first) is behaviorally
        // identical and needs no firstness special-case.
        require(
            STRATEGY_VALIDATOR.buildParamsAttested(ctx.query.orderHash),
            PortfolioManagerSwapBuildParametersNotAttested(ctx.query.orderHash)
        );

        // decodeTrusted, not parse: STRATEGY_VALIDATOR.buildParamsAttested above already proves
        // attestBuildParameters ran parse() successfully against these exact bytes once --
        // re-deriving group/member bounds, weight sum, duplicate tokens, and fee range on every
        // swap would just repeat work whose answer can't have changed since attestation.
        (PortfolioManagerArgsCodec.Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps) =
            PortfolioManagerArgsCodec.decodeTrusted(args);

        (uint256 groupInIdx, uint256 memberInIdx) = _resolve(groups, ctx.query.tokenIn);
        (uint256 groupOutIdx, uint256 memberOutIdx) = _resolve(groups, ctx.query.tokenOut);
        require(groupInIdx != groupOutIdx, PortfolioManagerSwapSameGroupSwap(groupInIdx));

        PortfolioManagerPricing.PoolState memory quote = PortfolioManagerPricing.PoolState({
            balanceIn: _groupValueWad(groups[groupInIdx], ctx.query.maker, OracleAdapter.Rounding.Up),
            balanceOut: _groupValueWad(groups[groupOutIdx], ctx.query.maker, OracleAdapter.Rounding.Down),
            weightIn: groups[groupInIdx].weight,
            weightOut: groups[groupOutIdx].weight,
            feeWad: FixedPointMath.divDown(feeBps, PortfolioManagerArgsCodec.PM_BPS)
        });

        if (maxDeviationBps != 0) {
            uint256 sp = PortfolioManagerPricing.spotPrice(quote);
            uint256 deviationBps = (sp > WAD ? sp - WAD : WAD - sp) * PortfolioManagerArgsCodec.PM_BPS / WAD;
            require(deviationBps <= maxDeviationBps, PortfolioManagerSwapExcessivePriceDeviation(sp, maxDeviationBps));
        }

        // The curve's own balanceIn/balanceOut are oracle-VALUE-scaled (ADR-0003: `Σ balance_j
        // × price_j` per group), not the traded token's native units — so the traded amount
        // must be converted into that same value numeraire before the formula call, and the
        // result converted back, using the specific traded token's own price/decimals. Skipping
        // this (as an earlier version of this function did) silently prices a $2,500 WETH unit
        // as if it were a $1 unit, since PortfolioManagerPricing itself is unit-agnostic and
        // trusts amountIn/amountOut to already share balanceIn/balanceOut's unit system.
        (uint256 tokenInPriceWad, uint8 tokenInDecimals) =
            _priceAndDecimals(groups[groupInIdx].members[memberInIdx], ctx.query.tokenIn, OracleAdapter.Rounding.Down);
        (uint256 tokenOutPriceWad, uint8 tokenOutDecimals) =
            _priceAndDecimals(groups[groupOutIdx].members[memberOutIdx], ctx.query.tokenOut, OracleAdapter.Rounding.Up);

        uint256 tokenInUnit = FixedPointMath.scaleDown(1, 0, tokenInDecimals);
        uint256 tokenOutUnit = FixedPointMath.scaleDown(1, 0, tokenOutDecimals);

        uint32 daoBps = PortfolioManagerFee.daoFeeBps(feeBps);
        uint256 daoAmount;

        if (ctx.query.isExactIn) {
            require(ctx.swap.amountOut == 0, PortfolioManagerSwapRecomputeDetected());
            // The taker's full, requested amountIn — the curve prices off it net of the
            // protocol pull, but SwapVM's own settlement must still collect the full amount
            // from the taker, so it's restored below (matches Fee.sol's own _feeAmountIn
            // exact-in branch, minus the wrap-the-rest-of-program recursion we don't need
            // here — nothing runs after this instruction).
            uint256 fullAmountIn = ctx.swap.amountIn;
            daoAmount = FixedPointMath.mulDivDown(fullAmountIn, daoBps, FEE_BPS);
            uint256 netAmountIn = fullAmountIn - daoAmount;

            uint256 netAmountInValueWad = FixedPointMath.mulDivDown(netAmountIn, tokenInPriceWad, tokenInUnit);
            uint256 amountOutValueWad = PortfolioManagerPricing.exactIn(quote, netAmountInValueWad);
            ctx.swap.amountOut = FixedPointMath.mulDivDown(amountOutValueWad, tokenOutUnit, tokenOutPriceWad);
            ctx.swap.amountIn = fullAmountIn;
        } else {
            require(ctx.swap.amountIn == 0, PortfolioManagerSwapRecomputeDetected());
            // Exact-out: the curve first computes the amountIn needed including the LP's own
            // curve fee (PortfolioManagerPricing.exactOut already grosses that up internally),
            // then the protocol fee is grossed up on top of that — mirrors Fee.sol's own
            // exact-out branch, which fees only once the swap amount is known.
            uint256 amountOutValueWad = FixedPointMath.mulDivUp(ctx.swap.amountOut, tokenOutPriceWad, tokenOutUnit);
            uint256 amountInValueWad = PortfolioManagerPricing.exactOut(quote, amountOutValueWad);
            uint256 cleanAmountIn = FixedPointMath.mulDivUp(amountInValueWad, tokenInUnit, tokenInPriceWad);
            daoAmount = FixedPointMath.mulDivDown(cleanAmountIn, daoBps, FEE_BPS - daoBps);
            ctx.swap.amountIn = cleanAmountIn + daoAmount;
        }

        // Best-effort, matching Fee.sol's own _tryPullFee rationale exactly: reverting on an
        // uncollectible fee would make a one-sided position untradable (OpenZeppelin M-09,
        // Theori #10). Skipped entirely in quote() (isStaticContext) — same divergence
        // Fee.sol's transfer-performing variants document.
        if (daoAmount != 0 && !ctx.vm.isStaticContext) {
            address recipient = PortfolioManagerFee.DAO_TREASURY_ADDRESS;
            try _AQUA.pull(ctx.query.maker, ctx.query.orderHash, ctx.query.tokenIn, daoAmount, recipient) {
                ctx.swap.amountNetPulled += daoAmount;
            } catch {
                emit ProtocolFeeSkipped(ctx.query.orderHash, ctx.query.tokenIn, recipient, daoAmount);
            }
        }
    }

    /// @dev Sole guard on the declared universe now (balances below are ungated) — reachable
    ///      via a `ship()`/args encoding mismatch, since `AQUA.safeBalances()` only checks the
    ///      token is part of the shipped strategy, not that it matches this instruction's args.
    function _resolve(PortfolioManagerArgsCodec.Group[] memory groups, address token)
        private
        pure
        returns (uint256 groupIdx, uint256 memberIdx)
    {
        for (uint256 i = 0; i < groups.length; i++) {
            PortfolioManagerArgsCodec.Member[] memory members = groups[i].members;
            for (uint256 j = 0; j < members.length; j++) {
                if (members[j].token == token) return (i, j);
            }
        }
        revert PortfolioManagerSwapTokenNotDeclared(token);
    }

    /// @dev The specific traded token's own price/decimals, separate from its group's
    ///      aggregate `groupValueWad` sum -- needed to convert the traded amount into and back
    ///      out of the group-value numeraire (see the main function's own note on why).
    function _priceAndDecimals(
        PortfolioManagerArgsCodec.Member memory member,
        address token,
        OracleAdapter.Rounding rounding
    ) private view returns (uint256 priceWad, uint8 decimals) {
        priceWad = OracleAdapter.priceWad(
            OracleAdapter.PriceFeed({feed: AggregatorV3Interface(member.feed), maxStaleness: member.maxStaleness}),
            rounding
        );
        decimals = IERC20Metadata(token).decimals();
    }

    /// @dev `Σ (member_balance × oracle_price)` over a group's full member set (ADR-0003) —
    ///      always goes through `OracleAdapter`, even for a single-member group, so decimal
    ///      normalization and price conversion are uniform regardless of group size.
    function _groupValueWad(
        PortfolioManagerArgsCodec.Group memory group,
        address maker,
        OracleAdapter.Rounding rounding
    ) private view returns (uint256) {
        uint256 n = group.members.length;
        address[] memory tokens = new address[](n);
        uint256[] memory balances = new uint256[](n);
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](n);
        for (uint256 i = 0; i < n; i++) {
            PortfolioManagerArgsCodec.Member memory m = group.members[i];
            tokens[i] = m.token;
            balances[i] = IERC20(m.token).balanceOf(maker);
            feeds[i] = OracleAdapter.PriceFeed({feed: AggregatorV3Interface(m.feed), maxStaleness: m.maxStaleness});
        }
        return OracleAdapter.groupValueWad(tokens, balances, feeds, rounding);
    }
}
