// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {IPortfolioManagerStrategyValidator} from "./interfaces/IPortfolioManagerStrategyValidator.sol";
import {PortfolioManagerArgsCodec} from "./utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "./utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerPricing} from "./utils/PortfolioManagerPricing.sol";
import {OracleAdapter} from "./utils/OracleAdapter.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @title PortfolioManagerStrategyValidator
/// @notice Validates the declared universe and initial composition, then records attestation.
/// @dev Aqua does not compare ship() tokens with the encoded PM universe.
///      Batch attestation and shipping from the maker with identical tokens.
///      This contract must not forward ship(): Aqua uses msg.sender as the maker.
contract PortfolioManagerStrategyValidator is IPortfolioManagerStrategyValidator {
    uint256 private constant WAD = 1e18;

    /// @dev Chainlink's L2 sequencer-uptime feed for this chain. See OracleAdapter.requireSequencerUp.
    AggregatorV3Interface private immutable SEQUENCER_UPTIME_FEED;

    /// @inheritdoc IPortfolioManagerStrategyValidator
    mapping(bytes32 => bool) public buildParamsAttested;

    constructor(address sequencerUptimeFeed) {
        SEQUENCER_UPTIME_FEED = AggregatorV3Interface(sequencerUptimeFeed);
    }

    /// @inheritdoc IPortfolioManagerStrategyValidator
    function requireUniverseMatches(ISwapVM.Order calldata order, address[] calldata tokens) external pure {
        (PortfolioManagerArgsCodec.Group[] memory groups,,) = PortfolioManagerArgsCodec.parse(_args(order));
        _requireUniverseMatches(groups, tokens);
    }

    /// @inheritdoc IPortfolioManagerStrategyValidator
    function requireBalancedWithinTolerance(ISwapVM.Order calldata order, address maker) external view {
        (PortfolioManagerArgsCodec.Group[] memory groups,, uint32 maxDeviationBps) =
            PortfolioManagerArgsCodec.parse(_args(order));
        _requireBalancedWithinTolerance(groups, maxDeviationBps, maker);
    }

    /// @inheritdoc IPortfolioManagerStrategyValidator
    function attestBuildParameters(ISwapVM.Order calldata order, address[] calldata tokens) external {
        (PortfolioManagerArgsCodec.Group[] memory groups,, uint32 maxDeviationBps) =
            PortfolioManagerArgsCodec.parse(_args(order));
        _requireUniverseMatches(groups, tokens);
        _requireBalancedWithinTolerance(groups, maxDeviationBps, order.maker);

        bytes32 strategyHash = keccak256(abi.encode(order));
        buildParamsAttested[strategyHash] = true;
        emit BuildParametersAttested(strategyHash);
    }

    function _requireUniverseMatches(PortfolioManagerArgsCodec.Group[] memory groups, address[] calldata tokens)
        private
        pure
    {
        address[] memory declared = PortfolioManagerArgsCodec.flattenTokens(groups);

        for (uint256 i = 0; i < declared.length; i++) {
            bool shipped = false;
            for (uint256 j = 0; j < tokens.length; j++) {
                if (declared[i] == tokens[j]) {
                    shipped = true;
                    break;
                }
            }
            require(shipped, PortfolioManagerStrategyValidatorDeclaredTokenNotShipped(declared[i]));
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            bool isDeclared = false;
            for (uint256 j = 0; j < declared.length; j++) {
                if (tokens[i] == declared[j]) {
                    isDeclared = true;
                    break;
                }
            }
            require(isDeclared, PortfolioManagerStrategyValidatorShippedTokenNotDeclared(tokens[i]));
        }
    }

    function _requireBalancedWithinTolerance(
        PortfolioManagerArgsCodec.Group[] memory groups,
        uint32 maxDeviationBps,
        address maker
    ) private view {
        if (maxDeviationBps == 0) return;
        OracleAdapter.requireSequencerUp(SEQUENCER_UPTIME_FEED);

        uint256 n = groups.length;
        uint256[] memory groupValuesWad = new uint256[](n);
        uint256 totalValueWad;
        for (uint256 i = 0; i < n; i++) {
            groupValuesWad[i] = PortfolioManagerArgsCodec.groupValueWad(groups[i], maker, OracleAdapter.Rounding.Down);
            totalValueWad += groupValuesWad[i];
        }
        require(totalValueWad > 0, PortfolioManagerStrategyValidatorEmptyPortfolio());

        // Checks every cross-group pair with PortfolioManagerSwap's own pairwise spot-price
        // formula, not each group's share of the total -- the two metrics diverge once a
        // strategy has more than two groups, and only the pairwise one guarantees every
        // direction a swap could actually trade is still within tolerance right after shipping.
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                PortfolioManagerPricing.PoolState memory quote = PortfolioManagerPricing.PoolState({
                    balanceIn: groupValuesWad[i],
                    balanceOut: groupValuesWad[j],
                    weightIn: groups[i].weight,
                    weightOut: groups[j].weight,
                    feeWad: 0
                });
                uint256 sp = PortfolioManagerPricing.spotPrice(quote);
                uint256 deviationBps = (sp > WAD ? sp - WAD : WAD - sp) * PortfolioManagerArgsCodec.PM_BPS / WAD;
                require(
                    deviationBps <= maxDeviationBps,
                    PortfolioManagerStrategyValidatorExcessivePriceDeviation(i, j, sp, maxDeviationBps)
                );
            }
        }
    }

    /// @dev Extracts arguments from the required leading PM opcode.
    function _args(ISwapVM.Order calldata order) private pure returns (bytes calldata args) {
        bytes calldata program = MakerTraitsLib.program(order.traits, order.data);
        require(
            program.length >= 2 && uint8(program[0]) == PortfolioManagerProgramBuilder.CURVE_OPCODE,
            PortfolioManagerStrategyValidatorNotAPortfolioManagerStrategy()
        );

        uint256 argsLength = uint8(program[1]);
        args = program[2:2 + argsLength];

        // Walks every instruction after the leading curve and rejects a second one -- its args
        // would never be checked or bound to this validated curve. A non-curve trailing
        // instruction (e.g. GatedPortfolioManagerProgramBuilder's resolver KYC gate) is fine:
        // it can't touch pricing, only gate who's allowed to trade at all.
        uint256 pc = 2 + argsLength;
        while (pc < program.length) {
            uint8 opcode = uint8(program[pc]);
            require(
                opcode != PortfolioManagerProgramBuilder.CURVE_OPCODE,
                PortfolioManagerStrategyValidatorTrailingCurveInstruction()
            );
            uint256 trailingArgsLength = uint8(program[pc + 1]);
            pc += 2 + trailingArgsLength;
        }
    }
}
