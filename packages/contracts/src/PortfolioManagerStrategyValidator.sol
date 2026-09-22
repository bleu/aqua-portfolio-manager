// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {IPortfolioManagerStrategyValidator} from "./interfaces/IPortfolioManagerStrategyValidator.sol";
import {PortfolioManagerArgsCodec} from "./utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "./utils/PortfolioManagerProgramBuilder.sol";
import {OracleAdapter} from "./utils/OracleAdapter.sol";

/// @title PortfolioManagerStrategyValidator
/// @notice Validates the declared universe and initial composition, then records attestation.
/// @dev Aqua does not compare ship() tokens with the encoded PM universe.
///      Batch attestation and shipping from the maker with identical tokens.
///      This contract must not forward ship(): Aqua uses msg.sender as the maker.
contract PortfolioManagerStrategyValidator is IPortfolioManagerStrategyValidator {
    uint256 private constant WAD = 1e18;

    /// @inheritdoc IPortfolioManagerStrategyValidator
    mapping(bytes32 => bool) public buildParamsAttested;

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

        uint256 n = groups.length;
        uint256[] memory groupValuesWad = new uint256[](n);
        uint256 totalValueWad;
        for (uint256 i = 0; i < n; i++) {
            groupValuesWad[i] = PortfolioManagerArgsCodec.groupValueWad(groups[i], maker, OracleAdapter.Rounding.Down);
            totalValueWad += groupValuesWad[i];
        }
        require(totalValueWad > 0, PortfolioManagerStrategyValidatorEmptyPortfolio());

        for (uint256 i = 0; i < n; i++) {
            uint256 actualShareWad = groupValuesWad[i] * WAD / totalValueWad;
            uint256 targetWeightWad = groups[i].weight;
            uint256 diffWad =
                actualShareWad > targetWeightWad ? actualShareWad - targetWeightWad : targetWeightWad - actualShareWad;
            uint256 deviationBps = diffWad * PortfolioManagerArgsCodec.PM_BPS / targetWeightWad;
            require(
                deviationBps <= maxDeviationBps,
                PortfolioManagerStrategyValidatorExcessivePriceDeviation(i, actualShareWad, targetWeightWad)
            );
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
    }
}
