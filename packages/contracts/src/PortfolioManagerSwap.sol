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
/// @dev Every group member uses its feed, including single-token groups.
///      The DAO fee transfer is inside this opcode so programs cannot omit a separate fee instruction.
///      Collection remains best-effort. Fee inheritance supplies the Aqua reference, scale, and skipped-fee event.
///      See docs/PRICING.md for formulas and units.
abstract contract PortfolioManagerSwap is Fee, IPortfolioManagerSwap {
    using ContextLib for Context;

    uint256 private constant WAD = FixedPointMath.WAD;

    /// @dev Aqua.ship() does not enforce validation. The opcode checks this validator's attestation.
    IPortfolioManagerStrategyValidator private immutable STRATEGY_VALIDATOR;

    constructor(address aqua, address strategyValidator) Fee(aqua) {
        STRATEGY_VALIDATOR = IPortfolioManagerStrategyValidator(strategyValidator);
    }

    /// @param args Group configuration, LP fee, and deviation limit encoded by PortfolioManagerArgsCodec.
    /// @dev The opcode table requires a non-view function pointer.
    function _portfolioManagerSwapXD(Context memory ctx, bytes calldata args) internal {
        // Reject unattested orders before decoding their arguments.
        require(
            STRATEGY_VALIDATOR.buildParamsAttested(ctx.query.orderHash),
            PortfolioManagerSwapBuildParametersNotAttested(ctx.query.orderHash)
        );

        // Attestation validates these exact argument bytes. Decode them without repeating validation.
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

        // Convert traded amounts to the reserves' value unit before pricing, then back to native token units.
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
            // Price after the DAO cut, but retain the full input for SwapVM settlement.
            uint256 fullAmountIn = ctx.swap.amountIn;
            daoAmount = FixedPointMath.mulDivDown(fullAmountIn, daoBps, FEE_BPS);
            uint256 netAmountIn = fullAmountIn - daoAmount;

            uint256 netAmountInValueWad = FixedPointMath.mulDivDown(netAmountIn, tokenInPriceWad, tokenInUnit);
            uint256 amountOutValueWad = PortfolioManagerPricing.exactIn(quote, netAmountInValueWad);
            ctx.swap.amountOut = FixedPointMath.mulDivDown(amountOutValueWad, tokenOutUnit, tokenOutPriceWad);
            ctx.swap.amountIn = fullAmountIn;
        } else {
            require(ctx.swap.amountIn == 0, PortfolioManagerSwapRecomputeDetected());
            // The curve includes the LP fee. Add the DAO fee to its required input.
            uint256 amountOutValueWad = FixedPointMath.mulDivUp(ctx.swap.amountOut, tokenOutPriceWad, tokenOutUnit);
            uint256 amountInValueWad = PortfolioManagerPricing.exactOut(quote, amountOutValueWad);
            uint256 cleanAmountIn = FixedPointMath.mulDivUp(amountInValueWad, tokenInUnit, tokenInPriceWad);
            daoAmount = FixedPointMath.mulDivDown(cleanAmountIn, daoBps, FEE_BPS - daoBps);
            ctx.swap.amountIn = cleanAmountIn + daoAmount;
        }

        // A group's total value does not guarantee enough units of the output token.
        uint256 tokenOutAvailable = IERC20(ctx.query.tokenOut).balanceOf(ctx.query.maker);
        require(
            ctx.swap.amountOut <= tokenOutAvailable,
            PortfolioManagerSwapInsufficientMemberBalance(ctx.query.tokenOut, ctx.swap.amountOut, tokenOutAvailable)
        );

        // Preserve swap availability when fee collection fails, matching Fee.sol (OpenZeppelin M-09, Theori #10).
        // Quotes skip the transfer.
        if (daoAmount != 0 && !ctx.vm.isStaticContext) {
            address recipient = PortfolioManagerFee.DAO_TREASURY_ADDRESS;
            try _AQUA.pull(ctx.query.maker, ctx.query.orderHash, ctx.query.tokenIn, daoAmount, recipient) {
                ctx.swap.amountNetPulled += daoAmount;
            } catch {
                emit ProtocolFeeSkipped(ctx.query.orderHash, ctx.query.tokenIn, recipient, daoAmount);
            }
        }
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

    /// @dev Gets the traded member's price and decimals for native-token/value conversion.
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

    /// @dev Values every member through OracleAdapter, including single-token groups.
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
