// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Context, ContextLib} from "swap-vm/libs/VM.sol";
import {Fee, BPS as FEE_BPS} from "swap-vm/instructions/Fee.sol";
import {IPortfolioManagerSwap} from "./interfaces/IPortfolioManagerSwap.sol";
import {IPortfolioManagerStrategyValidator} from "./interfaces/IPortfolioManagerStrategyValidator.sol";
import {PortfolioManagerArgsCodec} from "./utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerPricing} from "./utils/PortfolioManagerPricing.sol";
import {PortfolioManagerFee} from "./utils/PortfolioManagerFee.sol";
import {PortfolioManagerTokenRegistry} from "./utils/PortfolioManagerTokenRegistry.sol";
import {PortfolioManagerFeedRegistry} from "./utils/PortfolioManagerFeedRegistry.sol";
import {OracleAdapter} from "./utils/OracleAdapter.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {FixedPointMath} from "./utils/FixedPointMath.sol";

/// @title PortfolioManagerSwap
/// @notice Prices cross-group swaps from real wallet balances, oracle values, and target weights.
/// @dev Every group member uses its feed, including single-token groups, except each group's own
///      optional numeraire member (BLEUDEV-412/ADR-0017), which uses none. Different groups may
///      use different numeraires (or none) -- this contract never needs to reconcile them.
///      Members reference a token and a feed by registry index (BLEUDEV-412/ADR-0018) --
///      TOKEN_REGISTRY/FEED_REGISTRY are immutables so every helper below can resolve one
///      directly instead of carrying it as a parameter through the whole call chain.
///      All three fee transfers are inside this opcode so programs cannot omit a separate fee instruction.
///      Collection remains best-effort. Fee inheritance supplies the Aqua reference, scale, and skipped-fee event.
///      See docs/PRICING.md for formulas and units.
abstract contract PortfolioManagerSwap is Fee, IPortfolioManagerSwap {
    using ContextLib for Context;

    uint256 private constant WAD = FixedPointMath.WAD;

    /// @dev Aqua.ship() does not enforce validation. The opcode checks this validator's attestation.
    IPortfolioManagerStrategyValidator private immutable STRATEGY_VALIDATOR;
    /// @dev Chainlink's L2 sequencer-uptime feed for this chain. See OracleAdapter.requireSequencerUp.
    AggregatorV3Interface private immutable SEQUENCER_UPTIME_FEED;
    PortfolioManagerTokenRegistry private immutable TOKEN_REGISTRY;
    PortfolioManagerFeedRegistry private immutable FEED_REGISTRY;

    /// @notice 1inch DAO's treasury for this deployment. Set at construction, not compiled in --
    ///         can differ per chain, and a key rotation needs a new Router either way. Only
    ///         1inch's governance can change this today, by deploying a new Router -- there is no
    ///         setter, matching Kene's ask that 1inch's own fee stay outside Bleu's control.
    address public immutable PROTOCOL_TREASURY;
    /// @notice DAO's share of the LP fee, PM_BPS-scaled (1e9 = 100%). Same reasoning as PROTOCOL_TREASURY.
    uint32 public immutable PROTOCOL_FEE_RATE_BPS;

    /// @notice The only address that may call `setOperatorTreasury`/`setOperatorFeeRateBps` below.
    ///         Set at construction; Bleu/Trim's own operational key.
    address public immutable OPERATOR;
    /// @notice Bleu/Trim's own treasury for this deployment. Mutable by OPERATOR, unlike
    ///         PROTOCOL_TREASURY -- this is Bleu's own fee, independent of 1inch's.
    address public operatorTreasury;
    /// @notice Bleu/Trim's own share of the LP fee, PM_BPS-scaled. Mutable by OPERATOR, unlike
    ///         PROTOCOL_FEE_RATE_BPS.
    uint32 public operatorFeeRateBps;

    /// @notice The only address that may call `setRevenueShareTreasury`/`setRevenueShareRateBps`
    ///         below. Set at construction; 1inch's own operational key for this cut -- unlike
    ///         PROTOCOL_TREASURY/PROTOCOL_FEE_RATE_BPS, 1inch asked for this specific cut to stay
    ///         adjustable by their own wallet without a new Router deployment.
    address public immutable REVENUE_SHARE_ADMIN;
    /// @notice 1inch's revenue-share treasury for this deployment. Mutable by REVENUE_SHARE_ADMIN.
    ///         A separate, independently-tracked cut from PROTOCOL_TREASURY's, even though both
    ///         currently pay the same address.
    address public revenueShareTreasury;
    /// @notice 1inch's revenue-share rate, PM_BPS-scaled. Mutable by REVENUE_SHARE_ADMIN, unlike
    ///         PROTOCOL_FEE_RATE_BPS. Launches at 1/60 of the LP fee (10% of the existing 1/6
    ///         protocol fee), on top of -- not instead of -- that protocol fee.
    uint32 public revenueShareRateBps;

    constructor(
        address aqua,
        address strategyValidator,
        address sequencerUptimeFeed,
        address tokenRegistry,
        address feedRegistry,
        address protocolTreasury,
        address operatorTreasury_,
        address operator,
        uint32 protocolFeeRateBps,
        uint32 operatorFeeRateBps_,
        address revenueShareAdmin,
        address revenueShareTreasury_,
        uint32 revenueShareRateBps_
    ) Fee(aqua) {
        require(
            aqua != address(0) && strategyValidator != address(0) && sequencerUptimeFeed != address(0)
                && tokenRegistry != address(0) && feedRegistry != address(0) && protocolTreasury != address(0)
                && operatorTreasury_ != address(0) && operator != address(0) && revenueShareAdmin != address(0)
                && revenueShareTreasury_ != address(0),
            PortfolioManagerSwapZeroAddressDependency()
        );
        STRATEGY_VALIDATOR = IPortfolioManagerStrategyValidator(strategyValidator);
        SEQUENCER_UPTIME_FEED = AggregatorV3Interface(sequencerUptimeFeed);
        TOKEN_REGISTRY = PortfolioManagerTokenRegistry(tokenRegistry);
        FEED_REGISTRY = PortfolioManagerFeedRegistry(feedRegistry);
        PROTOCOL_TREASURY = protocolTreasury;
        PROTOCOL_FEE_RATE_BPS = protocolFeeRateBps;
        OPERATOR = operator;
        operatorTreasury = operatorTreasury_;
        operatorFeeRateBps = operatorFeeRateBps_;
        REVENUE_SHARE_ADMIN = revenueShareAdmin;
        revenueShareTreasury = revenueShareTreasury_;
        revenueShareRateBps = revenueShareRateBps_;
        _requireCombinedFeeRateBelowCap(operatorFeeRateBps_, revenueShareRateBps_);
    }

    /// @dev Three independently-mutable-or-not rates share one `feeBps` budget. Nothing upstream
    ///      stops their sum reaching or exceeding PM_BPS (100%) on its own -- that would underflow
    ///      `netBps` in `_priceExactOut` and revert every exact-out swap for the strategy. Checked
    ///      here, at construction and from every setter that can move one of the two mutable
    ///      rates, instead of only bounding each rate in isolation.
    function _requireCombinedFeeRateBelowCap(uint32 operatorFeeRateBps_, uint32 revenueShareRateBps_) private view {
        uint256 combinedBps = uint256(PROTOCOL_FEE_RATE_BPS) + operatorFeeRateBps_ + revenueShareRateBps_;
        require(combinedBps < PortfolioManagerArgsCodec.PM_BPS, PortfolioManagerSwapCombinedFeeRateTooHigh(combinedBps));
    }

    /// @notice Lets OPERATOR redirect Bleu/Trim's own fee to a new treasury, without a new
    ///         Router deployment. Does not affect PROTOCOL_TREASURY.
    function setOperatorTreasury(address newOperatorTreasury) external {
        require(msg.sender == OPERATOR, PortfolioManagerSwapOnlyOperator());
        require(newOperatorTreasury != address(0), PortfolioManagerSwapZeroAddressDependency());
        emit OperatorTreasuryUpdated(operatorTreasury, newOperatorTreasury);
        operatorTreasury = newOperatorTreasury;
    }

    /// @notice Lets OPERATOR change Bleu/Trim's own fee rate, without a new Router deployment.
    ///         Does not affect PROTOCOL_FEE_RATE_BPS.
    /// @dev Bounded below 100% as a sanity check against a fat-fingered rate, and bounded again,
    ///      combined with the other two rates, against reaching feeBps's own 100% budget.
    function setOperatorFeeRateBps(uint32 newOperatorFeeRateBps) external {
        require(msg.sender == OPERATOR, PortfolioManagerSwapOnlyOperator());
        require(
            newOperatorFeeRateBps < PortfolioManagerArgsCodec.PM_BPS,
            PortfolioManagerSwapFeeRateTooHigh(newOperatorFeeRateBps)
        );
        _requireCombinedFeeRateBelowCap(newOperatorFeeRateBps, revenueShareRateBps);
        emit OperatorFeeRateUpdated(operatorFeeRateBps, newOperatorFeeRateBps);
        operatorFeeRateBps = newOperatorFeeRateBps;
    }

    /// @notice Lets REVENUE_SHARE_ADMIN redirect 1inch's revenue-share cut to a new treasury,
    ///         without a new Router deployment. Does not affect PROTOCOL_TREASURY.
    function setRevenueShareTreasury(address newRevenueShareTreasury) external {
        require(msg.sender == REVENUE_SHARE_ADMIN, PortfolioManagerSwapOnlyRevenueShareAdmin());
        require(newRevenueShareTreasury != address(0), PortfolioManagerSwapZeroAddressDependency());
        emit RevenueShareTreasuryUpdated(revenueShareTreasury, newRevenueShareTreasury);
        revenueShareTreasury = newRevenueShareTreasury;
    }

    /// @notice Lets REVENUE_SHARE_ADMIN change 1inch's own revenue-share rate, without a new
    ///         Router deployment -- 1inch asked to keep this one adjustable by their own wallet,
    ///         unlike PROTOCOL_FEE_RATE_BPS. Does not affect PROTOCOL_FEE_RATE_BPS.
    /// @dev Same two bounds as setOperatorFeeRateBps: below 100% alone, and below feeBps's budget combined.
    function setRevenueShareRateBps(uint32 newRevenueShareRateBps) external {
        require(msg.sender == REVENUE_SHARE_ADMIN, PortfolioManagerSwapOnlyRevenueShareAdmin());
        require(
            newRevenueShareRateBps < PortfolioManagerArgsCodec.PM_BPS,
            PortfolioManagerSwapFeeRateTooHigh(newRevenueShareRateBps)
        );
        _requireCombinedFeeRateBelowCap(operatorFeeRateBps, newRevenueShareRateBps);
        emit RevenueShareRateUpdated(revenueShareRateBps, newRevenueShareRateBps);
        revenueShareRateBps = newRevenueShareRateBps;
    }

    /// @param args Group configuration, LP fee, and deviation limit encoded by PortfolioManagerArgsCodec.
    /// @dev The opcode table requires a non-view function pointer.
    function _portfolioManagerSwapXd(Context memory ctx, bytes calldata args) internal {
        // Checked before decoding args to skip parse cost when unattested; the flag is
        // monotonic (set once, never unset), so re-checking every swap is intentional, not a
        // missed firstness optimization.
        require(
            STRATEGY_VALIDATOR.buildParamsAttested(ctx.query.orderHash),
            PortfolioManagerSwapBuildParametersNotAttested(ctx.query.orderHash)
        );
        OracleAdapter.requireSequencerUp(SEQUENCER_UPTIME_FEED);

        // Attestation validates these exact argument bytes. Decode them without repeating
        // validation. Bridge feeds (ADR-0017) exist only for the ship-time deviation check --
        // swap pricing always uses each group's own unit, never a bridge -- so this skips
        // decoding them entirely instead of materializing an unused Bridge[] every swap.
        (PortfolioManagerArgsCodec.Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps) =
            PortfolioManagerArgsCodec.decodeTrustedForSwap(args);

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

        uint256 protocolAmount;
        uint256 operatorAmount;
        uint256 revenueShareAmount;
        if (ctx.query.isExactIn) {
            require(ctx.swap.amountOut == 0, PortfolioManagerSwapRecomputeDetected());
            (ctx.swap.amountOut, protocolAmount, operatorAmount, revenueShareAmount) = _priceExactIn(
                quote, rawIn, rawOut, tokenInDecimals, tokenOutDecimals, ctx.swap.amountIn, feeBps, maxDeviationBps
            );
        } else {
            require(ctx.swap.amountIn == 0, PortfolioManagerSwapRecomputeDetected());
            (ctx.swap.amountIn, protocolAmount, operatorAmount, revenueShareAmount) = _priceExactOut(
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
        // Quotes skip the transfer. The DAO's 1/6 protocol cut, 1inch's own 1/60 revenue-share
        // cut, and Bleu/Trim's own 1/6 cut are computed independently of each other (not split
        // from one combined amount) and pulled independently, so one recipient's failure never
        // blocks the others or the swap.
        if (!ctx.vm.isStaticContext) {
            if (protocolAmount != 0) {
                try _AQUA.pull(
                    ctx.query.maker, ctx.query.orderHash, ctx.query.tokenIn, protocolAmount, PROTOCOL_TREASURY
                ) {
                    ctx.swap.amountNetPulled += protocolAmount;
                } catch {
                    emit ProtocolFeeSkipped(ctx.query.orderHash, ctx.query.tokenIn, PROTOCOL_TREASURY, protocolAmount);
                }
            }

            if (revenueShareAmount != 0) {
                try _AQUA.pull(
                    ctx.query.maker, ctx.query.orderHash, ctx.query.tokenIn, revenueShareAmount, revenueShareTreasury
                ) {
                    ctx.swap.amountNetPulled += revenueShareAmount;
                } catch {
                    emit ProtocolFeeSkipped(
                        ctx.query.orderHash, ctx.query.tokenIn, revenueShareTreasury, revenueShareAmount
                    );
                }
            }

            if (operatorAmount != 0) {
                try _AQUA.pull(
                    ctx.query.maker, ctx.query.orderHash, ctx.query.tokenIn, operatorAmount, operatorTreasury
                ) {
                    ctx.swap.amountNetPulled += operatorAmount;
                } catch {
                    emit ProtocolFeeSkipped(ctx.query.orderHash, ctx.query.tokenIn, operatorTreasury, operatorAmount);
                }
            }
        }
    }

    /// @dev Fetches each traded member's raw price once and values both groups, reusing that
    ///      single read instead of letting group valuation and native-unit conversion each read
    ///      the same feed under their own rounding (BLEUDEV-412). Split out of
    ///      _portfolioManagerSwapXd to keep that function under the stack-depth limit.
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
    )
        private
        view
        returns (uint256 amountOut, uint256 protocolAmount, uint256 operatorAmount, uint256 revenueShareAmount)
    {
        uint256 tokenInPriceWad = OracleAdapter.roundPrice(rawIn, OracleAdapter.Rounding.Down);
        uint256 tokenOutPriceWad = OracleAdapter.roundPrice(rawOut, OracleAdapter.Rounding.Up);
        uint256 tokenInUnit = FixedPointMath.scaleDown(1, 0, tokenInDecimals);
        uint256 tokenOutUnit = FixedPointMath.scaleDown(1, 0, tokenOutDecimals);

        // Price after all three cuts; the caller keeps the full input for SwapVM settlement.
        uint32 protocolBps = PortfolioManagerFee.shareBps(feeBps, PROTOCOL_FEE_RATE_BPS);
        uint32 operatorBps = PortfolioManagerFee.shareBps(feeBps, operatorFeeRateBps);
        uint32 revenueShareBps = PortfolioManagerFee.shareBps(feeBps, revenueShareRateBps);
        protocolAmount = FixedPointMath.mulDivDown(fullAmountIn, protocolBps, FEE_BPS);
        operatorAmount = FixedPointMath.mulDivDown(fullAmountIn, operatorBps, FEE_BPS);
        revenueShareAmount = FixedPointMath.mulDivDown(fullAmountIn, revenueShareBps, FEE_BPS);
        uint256 netAmountIn = fullAmountIn - protocolAmount - operatorAmount - revenueShareAmount;

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
    )
        private
        view
        returns (uint256 amountIn, uint256 protocolAmount, uint256 operatorAmount, uint256 revenueShareAmount)
    {
        uint256 tokenInPriceWad = OracleAdapter.roundPrice(rawIn, OracleAdapter.Rounding.Down);
        uint256 tokenOutPriceWad = OracleAdapter.roundPrice(rawOut, OracleAdapter.Rounding.Up);
        uint256 tokenInUnit = FixedPointMath.scaleDown(1, 0, tokenInDecimals);
        uint256 tokenOutUnit = FixedPointMath.scaleDown(1, 0, tokenOutDecimals);

        // The curve includes the LP fee. Add all three independent cuts to its required input.
        uint256 curveAmountOutValueWad = FixedPointMath.mulDivUp(amountOut, tokenOutPriceWad, tokenOutUnit);
        uint256 curveAmountInValueWad = PortfolioManagerPricing.exactOut(quote, curveAmountOutValueWad);
        if (maxDeviationBps != 0) {
            _requireWithinDeviationStep(quote, curveAmountInValueWad, curveAmountOutValueWad, maxDeviationBps);
        }
        uint256 cleanAmountIn = FixedPointMath.mulDivUp(curveAmountInValueWad, tokenInUnit, tokenInPriceWad);
        uint32 protocolBps = PortfolioManagerFee.shareBps(feeBps, PROTOCOL_FEE_RATE_BPS);
        uint32 operatorBps = PortfolioManagerFee.shareBps(feeBps, operatorFeeRateBps);
        uint32 revenueShareBps = PortfolioManagerFee.shareBps(feeBps, revenueShareRateBps);
        uint256 netBps = FEE_BPS - protocolBps - operatorBps - revenueShareBps;
        protocolAmount = FixedPointMath.mulDivDown(cleanAmountIn, protocolBps, netBps);
        operatorAmount = FixedPointMath.mulDivDown(cleanAmountIn, operatorBps, netBps);
        revenueShareAmount = FixedPointMath.mulDivDown(cleanAmountIn, revenueShareBps, netBps);
        amountIn = cleanAmountIn + protocolAmount + operatorAmount + revenueShareAmount;
    }

    /// @dev ADR-0016: caps how far this trade itself moves the pair, not the pair's starting
    ///      deviation -- a trade that already passed the curve (so curveAmountOutValueWad <
    ///      quote.balanceOut, per PortfolioManagerPricing's own invariant) can't push spotPrice
    ///      more than maxDeviationBps away from where it started, in either direction. Split out
    ///      from _portfolioManagerSwapXd, and recomputes spBefore here instead of taking it as a
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
        uint256 stepBps = FixedPointMath.mulDivDown(
            spAfter > spBefore ? spAfter - spBefore : spBefore - spAfter, PortfolioManagerArgsCodec.PM_BPS, WAD
        );
        require(stepBps <= maxDeviationBps, PortfolioManagerSwapExcessivePriceDeviation(spAfter, maxDeviationBps));
    }

    /// @dev Aqua's token list can differ from the encoded PM universe. Enforce membership here
    ///      too. Resolves `token` to its registry index once (one external call), then scans
    ///      members comparing indices directly -- cheaper than resolving every candidate
    ///      member's own tokenIndex just to find the match.
    function _resolve(PortfolioManagerArgsCodec.Group[] memory groups, address token)
        private
        view
        returns (uint256 groupIdx, uint256 memberIdx)
    {
        uint16 tokenIndex = TOKEN_REGISTRY.indexOf(token);
        for (uint256 i = 0; i < groups.length; i++) {
            PortfolioManagerArgsCodec.Member[] memory members = groups[i].members;
            for (uint256 j = 0; j < members.length; j++) {
                if (members[j].tokenIndex == tokenIndex) return (i, j);
            }
        }
        revert PortfolioManagerSwapTokenNotDeclared(token);
    }

    function _feedOf(PortfolioManagerArgsCodec.Member memory member)
        private
        view
        returns (OracleAdapter.PriceFeed memory)
    {
        (address feed, uint32 maxStaleness) = FEED_REGISTRY.feedAt(member.feedIndex);
        return OracleAdapter.PriceFeed({feed: AggregatorV3Interface(feed), maxStaleness: maxStaleness});
    }

    /// @dev Values every member through OracleAdapter, including single-token groups, except
    ///      this group's own numeraire member if any (BLEUDEV-412/ADR-0017). Reuses `tradedMemberRaw`
    ///      for the member at `tradedMemberIdx` instead of fetching its feed again, and returns
    ///      that member's decimals and native balance alongside the group total so the caller
    ///      doesn't have to look either up a second time.
    /// @dev The token registry is permissionless, so `token` below can be a
    ///      malicious contract. Its `balanceOf()`/`decimals()` cannot reenter this router with any
    ///      state-changing call: both are invoked through `IERC20`/`IERC20Metadata`, interfaces
    ///      that declare them `view`, so Solidity compiles these two calls as `STATICCALL` --
    ///      and the EVM itself (not just Solidity) propagates that read-only context to every call
    ///      the token's own code makes in turn, with no bypass available to the callee (not even
    ///      via inline assembly). Confirmed empirically for `balanceOf()`, not assumed: see
    ///      test/PortfolioManagerSwapReentrancyGuard.t.sol, which has a malicious member token
    ///      attempt exactly this and shows it revert with `StateChangeDuringStaticCall` -- the
    ///      same STATICCALL-propagation mechanism protects `decimals()` identically, since both
    ///      calls go through an interface that declares the function `view`.
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
            address token = TOKEN_REGISTRY.tokenAt(m.tokenIndex);
            tokens[i] = token;
            balances[i] = IERC20(token).balanceOf(maker);
            feeds[i] = _feedOf(m);
        }
        (totalValueWad, tradedMemberDecimals) = OracleAdapter.groupValueWadWithOverride(
            tokens, balances, feeds, rounding, tradedMemberIdx, tradedMemberRaw
        );
        tradedMemberBalance = balances[tradedMemberIdx];
    }
}
