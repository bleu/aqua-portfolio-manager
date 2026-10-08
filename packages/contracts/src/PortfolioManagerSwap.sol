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

/// @title PortfolioManagerSwap
/// @notice Prices cross-group swaps from real wallet balances, oracle values, and target weights.
/// @dev Every group member uses its feed, including single-token groups, except the strategy's
///      optional numeraire member (BLEUDEV-412/ADR-0017), which uses none.
///      The DAO fee transfer is inside this opcode so programs cannot omit a separate fee instruction.
///      Collection remains best-effort. Fee inheritance supplies the Aqua reference, scale, and skipped-fee event.
///      See docs/PRICING.md for formulas and units.
abstract contract PortfolioManagerSwap is Fee, IPortfolioManagerSwap {
    using ContextLib for Context;

    uint256 private constant WAD = FixedPointMath.WAD;

    /// @dev Aqua.ship() does not enforce validation. The opcode checks this validator's attestation.
    IPortfolioManagerStrategyValidator private immutable STRATEGY_VALIDATOR;
    /// @dev Chainlink's L2 sequencer-uptime feed for this chain. See OracleAdapter.requireSequencerUp.
    AggregatorV3Interface private immutable SEQUENCER_UPTIME_FEED;

    constructor(address aqua, address strategyValidator, address sequencerUptimeFeed) Fee(aqua) {
        STRATEGY_VALIDATOR = IPortfolioManagerStrategyValidator(strategyValidator);
        SEQUENCER_UPTIME_FEED = AggregatorV3Interface(sequencerUptimeFeed);
    }

    /// @param args Group configuration, LP fee, and deviation limit encoded by PortfolioManagerArgsCodec.
    /// @dev The opcode table requires a non-view function pointer.
    function _portfolioManagerSwapXD(Context memory ctx, bytes calldata args) internal {
        // Checked before decoding args to skip parse cost when unattested; the flag is
        // monotonic (set once, never unset), so re-checking every swap is intentional, not a
        // missed firstness optimization.
        require(
            STRATEGY_VALIDATOR.buildParamsAttested(ctx.query.orderHash),
            PortfolioManagerSwapBuildParametersNotAttested(ctx.query.orderHash)
        );
        OracleAdapter.requireSequencerUp(SEQUENCER_UPTIME_FEED);

        // Attestation validates these exact argument bytes. Decode them without repeating validation.
        (PortfolioManagerArgsCodec.Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps) =
            PortfolioManagerArgsCodec.decodeTrusted(args);

        (uint256 groupInIdx, uint256 memberInIdx) = _resolve(groups, ctx.query.tokenIn);
        (uint256 groupOutIdx, uint256 memberOutIdx) = _resolve(groups, ctx.query.tokenOut);
        require(groupInIdx != groupOutIdx, PortfolioManagerSwapSameGroupSwap(groupInIdx));

        // Each traded member's feed is read at most once here, however many times its group
        // valuation and native-unit conversion need its price (BLEUDEV-412): _buildQuote fetches
        // the raw (answer, decimals) for both traded members and reuses it for every rounding
        // direction the rest of this function needs, instead of re-reading the same feed.
        (
            PortfolioManagerPricing.PoolState memory quote,
            OracleAdapter.RawPrice memory rawIn,
            OracleAdapter.RawPrice memory rawOut,
            uint8 tokenInDecimals,
            uint8 tokenOutDecimals,
            uint256 tokenOutWalletBalance
        ) = _buildQuote(groups[groupInIdx], memberInIdx, groups[groupOutIdx], memberOutIdx, ctx.query.maker, feeBps);

        uint256 daoAmount;
        if (ctx.query.isExactIn) {
            require(ctx.swap.amountOut == 0, PortfolioManagerSwapRecomputeDetected());
            (ctx.swap.amountOut, daoAmount) = _priceExactIn(
                quote, rawIn, rawOut, tokenInDecimals, tokenOutDecimals, ctx.swap.amountIn, feeBps, maxDeviationBps
            );
        } else {
            require(ctx.swap.amountIn == 0, PortfolioManagerSwapRecomputeDetected());
            (ctx.swap.amountIn, daoAmount) = _priceExactOut(
                quote, rawIn, rawOut, tokenInDecimals, tokenOutDecimals, ctx.swap.amountOut, feeBps, maxDeviationBps
            );
        }

        // A group's total value does not guarantee enough units of the output token -- and
        // neither does the wallet balance alone: Aqua's own ledger authorization for this
        // strategy (set at ship() time, independent of the wallet's own balance) is a separate
        // settlement constraint. A computed output that fits the wallet but exceeds the
        // strategy's remaining Aqua allocation can never actually settle. tokenOutWalletBalance
        // was already read while valuing groupOut above -- no second balanceOf call here.
        (uint256 tokenOutLedgerBalance,) =
            _AQUA.rawBalances(ctx.query.maker, address(this), ctx.query.orderHash, ctx.query.tokenOut);
        uint256 tokenOutAvailable =
            tokenOutWalletBalance < tokenOutLedgerBalance ? tokenOutWalletBalance : tokenOutLedgerBalance;
        require(
            ctx.swap.amountOut <= tokenOutAvailable,
            PortfolioManagerSwapInsufficientMemberBalance(ctx.query.tokenOut, ctx.swap.amountOut, tokenOutAvailable)
        );

        // Preserve swap availability when fee collection fails, matching Fee.sol (OpenZeppelin M-09, Theori #10).
        // Quotes skip the transfer. The protocol-fee cut splits 50/50 between the DAO and Bleu
        // (agreed separately between Bleu and 1inch, outside 1IP-103); each half is pulled
        // independently so one recipient's failure never blocks the other or the swap. The DAO
        // gets the extra unit on an odd split.
        if (daoAmount != 0 && !ctx.vm.isStaticContext) {
            uint256 bleuAmount = daoAmount / 2;
            uint256 daoShare = daoAmount - bleuAmount;

            address daoRecipient = PortfolioManagerFee.DAO_TREASURY_ADDRESS;
            try _AQUA.pull(ctx.query.maker, ctx.query.orderHash, ctx.query.tokenIn, daoShare, daoRecipient) {
                ctx.swap.amountNetPulled += daoShare;
            } catch {
                emit ProtocolFeeSkipped(ctx.query.orderHash, ctx.query.tokenIn, daoRecipient, daoShare);
            }

            if (bleuAmount != 0) {
                address bleuRecipient = PortfolioManagerFee.BLEU_TREASURY_ADDRESS;
                try _AQUA.pull(ctx.query.maker, ctx.query.orderHash, ctx.query.tokenIn, bleuAmount, bleuRecipient) {
                    ctx.swap.amountNetPulled += bleuAmount;
                } catch {
                    emit ProtocolFeeSkipped(ctx.query.orderHash, ctx.query.tokenIn, bleuRecipient, bleuAmount);
                }
            }
        }
    }

    /// @dev Fetches each traded member's raw price once and values both groups, reusing that
    ///      single read instead of letting group valuation and native-unit conversion each read
    ///      the same feed under their own rounding (BLEUDEV-412). Split out of
    ///      _portfolioManagerSwapXD to keep that function under the stack-depth limit.
    function _buildQuote(
        PortfolioManagerArgsCodec.Group memory groupIn,
        uint256 memberInIdx,
        PortfolioManagerArgsCodec.Group memory groupOut,
        uint256 memberOutIdx,
        address maker,
        uint32 feeBps
    )
        private
        view
        returns (
            PortfolioManagerPricing.PoolState memory quote,
            OracleAdapter.RawPrice memory rawIn,
            OracleAdapter.RawPrice memory rawOut,
            uint8 tokenInDecimals,
            uint8 tokenOutDecimals,
            uint256 tokenOutWalletBalance
        )
    {
        rawIn = OracleAdapter.fetchRawPrice(_feedOf(groupIn.members[memberInIdx]));
        rawOut = OracleAdapter.fetchRawPrice(_feedOf(groupOut.members[memberOutIdx]));

        uint256 balanceInWad;
        uint256 balanceOutWad;
        (balanceInWad, tokenInDecimals,) = _groupValueWad(groupIn, maker, OracleAdapter.Rounding.Up, memberInIdx, rawIn);
        (balanceOutWad, tokenOutDecimals, tokenOutWalletBalance) =
            _groupValueWad(groupOut, maker, OracleAdapter.Rounding.Down, memberOutIdx, rawOut);

        quote = PortfolioManagerPricing.PoolState({
            balanceIn: balanceInWad,
            balanceOut: balanceOutWad,
            weightIn: groupIn.weight,
            weightOut: groupOut.weight,
            feeWad: FixedPointMath.divDown(feeBps, PortfolioManagerArgsCodec.PM_BPS)
        });
    }

    /// @dev Prices an exact-in trade and enforces the ADR-0016 deviation step cap, from an
    ///      already-built quote and already-fetched traded-member raw prices (BLEUDEV-412) --
    ///      no oracle or balanceOf calls happen in this function.
    function _priceExactIn(
        PortfolioManagerPricing.PoolState memory quote,
        OracleAdapter.RawPrice memory rawIn,
        OracleAdapter.RawPrice memory rawOut,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals,
        uint256 fullAmountIn,
        uint32 feeBps,
        uint32 maxDeviationBps
    ) private pure returns (uint256 amountOut, uint256 daoAmount) {
        uint256 tokenInPriceWad = OracleAdapter.roundPrice(rawIn, OracleAdapter.Rounding.Down);
        uint256 tokenOutPriceWad = OracleAdapter.roundPrice(rawOut, OracleAdapter.Rounding.Up);
        uint256 tokenInUnit = FixedPointMath.scaleDown(1, 0, tokenInDecimals);
        uint256 tokenOutUnit = FixedPointMath.scaleDown(1, 0, tokenOutDecimals);

        // Price after the DAO cut; the caller keeps the full input for SwapVM settlement.
        uint32 daoBps = PortfolioManagerFee.daoFeeBps(feeBps);
        daoAmount = FixedPointMath.mulDivDown(fullAmountIn, daoBps, FEE_BPS);
        uint256 netAmountIn = fullAmountIn - daoAmount;

        uint256 curveAmountInValueWad = FixedPointMath.mulDivDown(netAmountIn, tokenInPriceWad, tokenInUnit);
        uint256 curveAmountOutValueWad = PortfolioManagerPricing.exactIn(quote, curveAmountInValueWad);
        if (maxDeviationBps != 0) {
            _requireWithinDeviationStep(quote, curveAmountInValueWad, curveAmountOutValueWad, maxDeviationBps);
        }
        amountOut = FixedPointMath.mulDivDown(curveAmountOutValueWad, tokenOutUnit, tokenOutPriceWad);
    }

    /// @dev Prices an exact-out trade and enforces the ADR-0016 deviation step cap. See
    ///      _priceExactIn's doc comment for why this takes a pre-built quote and pre-fetched
    ///      raw prices instead of fetching its own.
    function _priceExactOut(
        PortfolioManagerPricing.PoolState memory quote,
        OracleAdapter.RawPrice memory rawIn,
        OracleAdapter.RawPrice memory rawOut,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals,
        uint256 amountOut,
        uint32 feeBps,
        uint32 maxDeviationBps
    ) private pure returns (uint256 amountIn, uint256 daoAmount) {
        uint256 tokenInPriceWad = OracleAdapter.roundPrice(rawIn, OracleAdapter.Rounding.Down);
        uint256 tokenOutPriceWad = OracleAdapter.roundPrice(rawOut, OracleAdapter.Rounding.Up);
        uint256 tokenInUnit = FixedPointMath.scaleDown(1, 0, tokenInDecimals);
        uint256 tokenOutUnit = FixedPointMath.scaleDown(1, 0, tokenOutDecimals);

        // The curve includes the LP fee. Add the DAO fee to its required input.
        uint256 curveAmountOutValueWad = FixedPointMath.mulDivUp(amountOut, tokenOutPriceWad, tokenOutUnit);
        uint256 curveAmountInValueWad = PortfolioManagerPricing.exactOut(quote, curveAmountOutValueWad);
        if (maxDeviationBps != 0) {
            _requireWithinDeviationStep(quote, curveAmountInValueWad, curveAmountOutValueWad, maxDeviationBps);
        }
        uint256 cleanAmountIn = FixedPointMath.mulDivUp(curveAmountInValueWad, tokenInUnit, tokenInPriceWad);
        uint32 daoBps = PortfolioManagerFee.daoFeeBps(feeBps);
        daoAmount = FixedPointMath.mulDivDown(cleanAmountIn, daoBps, FEE_BPS - daoBps);
        amountIn = cleanAmountIn + daoAmount;
    }

    /// @dev ADR-0016: caps how far this trade itself moves the pair, not the pair's starting
    ///      deviation -- a trade that already passed the curve (so curveAmountOutValueWad <
    ///      quote.balanceOut, per PortfolioManagerPricing's own invariant) can't push spotPrice
    ///      more than maxDeviationBps away from where it started, in either direction. Split out
    ///      from _portfolioManagerSwapXD, and recomputes spBefore here instead of taking it as a
    ///      param, to keep that function under the stack-depth limit.
    function _requireWithinDeviationStep(
        PortfolioManagerPricing.PoolState memory quote,
        uint256 curveAmountInValueWad,
        uint256 curveAmountOutValueWad,
        uint32 maxDeviationBps
    ) private pure {
        uint256 spBefore = PortfolioManagerPricing.spotPrice(quote);
        PortfolioManagerPricing.PoolState memory postQuote = PortfolioManagerPricing.PoolState({
            balanceIn: quote.balanceIn + curveAmountInValueWad,
            balanceOut: quote.balanceOut - curveAmountOutValueWad,
            weightIn: quote.weightIn,
            weightOut: quote.weightOut,
            feeWad: quote.feeWad
        });
        uint256 spAfter = PortfolioManagerPricing.spotPrice(postQuote);
        uint256 stepBps =
            (spAfter > spBefore ? spAfter - spBefore : spBefore - spAfter) * PortfolioManagerArgsCodec.PM_BPS / WAD;
        require(stepBps <= maxDeviationBps, PortfolioManagerSwapExcessivePriceDeviation(spAfter, maxDeviationBps));
    }

    /// @dev Aqua's token list can differ from the encoded PM universe. Enforce membership here too.
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

    function _feedOf(PortfolioManagerArgsCodec.Member memory member)
        private
        pure
        returns (OracleAdapter.PriceFeed memory)
    {
        return OracleAdapter.PriceFeed({feed: AggregatorV3Interface(member.feed), maxStaleness: member.maxStaleness});
    }

    /// @dev Values every member through OracleAdapter, including single-token groups, except the
    ///      strategy's numeraire member if any (BLEUDEV-412/ADR-0017). Reuses `tradedMemberRaw`
    ///      for the member at `tradedMemberIdx` instead of fetching its feed again, and returns
    ///      that member's decimals and native balance alongside the group total so the caller
    ///      doesn't have to look either up a second time.
    function _groupValueWad(
        PortfolioManagerArgsCodec.Group memory group,
        address maker,
        OracleAdapter.Rounding rounding,
        uint256 tradedMemberIdx,
        OracleAdapter.RawPrice memory tradedMemberRaw
    ) private view returns (uint256 totalValueWad, uint8 tradedMemberDecimals, uint256 tradedMemberBalance) {
        uint256 n = group.members.length;
        address[] memory tokens = new address[](n);
        uint256[] memory balances = new uint256[](n);
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](n);
        for (uint256 i = 0; i < n; i++) {
            PortfolioManagerArgsCodec.Member memory m = group.members[i];
            tokens[i] = m.token;
            balances[i] = IERC20(m.token).balanceOf(maker);
            feeds[i] = _feedOf(m);
        }
        (totalValueWad, tradedMemberDecimals) = OracleAdapter.groupValueWadWithOverride(
            tokens, balances, feeds, rounding, tradedMemberIdx, tradedMemberRaw
        );
        tradedMemberBalance = balances[tradedMemberIdx];
    }
}
