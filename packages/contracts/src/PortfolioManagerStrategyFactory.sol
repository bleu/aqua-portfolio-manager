// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {IPortfolioManagerStrategyFactory} from "./interfaces/IPortfolioManagerStrategyFactory.sol";
import {PortfolioManagerArgsBuilder, PM_BPS} from "./PortfolioManagerArgsBuilder.sol";
import {PortfolioManagerProgramBuilder} from "./PortfolioManagerProgramBuilder.sol";

/// @title PortfolioManagerStrategyFactory — validates a PM strategy's ship() encoding
/// @notice A PM strategy's declared universe exists in two places `IAqua.ship()` never
///         cross-checks: `PortfolioManagerArgsBuilder`'s encoded args (what the curve opcode
///         actually prices against) and the `tokens` array passed to `ship()` itself (what
///         Aqua's ledger actually tracks). `ship()` succeeds either way, even when they
///         disagree -- the mismatch only surfaces later, when some taker happens to trade the
///         specific token that's missing on one side, reverting for them, not for the LP who
///         made the mistake, at the point they made it.
///
/// Deliberately does NOT forward to `IAqua.ship()` itself: `Aqua.ship()` keys its ledger entry
/// by `msg.sender`, but every real trade (`SwapVM._transferIn`, `Aqua.safeBalances`) looks that
/// same ledger up by `order.maker`. A wrapper that called `ship()` on the maker's behalf would
/// key the ledger to its own address instead of the maker's, permanently breaking settlement for
/// every strategy shipped through it. The maker must still call `Aqua.ship()` itself; this
/// contract only validates. Callers batch a call here together with the real
/// `ship()` call in the same atomic transaction, e.g. via Safe's own audited
/// `MultiSendCallOnly` -- see `PortfolioManagerE2EBase.sol::_shipOnly`.
contract PortfolioManagerStrategyFactory is IPortfolioManagerStrategyFactory {
    uint256 private constant WAD = 1e18;

    /// @inheritdoc IPortfolioManagerStrategyFactory
    mapping(bytes32 => bool) public buildParamsAttested;

    /// @inheritdoc IPortfolioManagerStrategyFactory
    function requireUniverseMatches(ISwapVM.Order calldata order, address[] calldata tokens) external pure {
        (PortfolioManagerArgsBuilder.Group[] memory groups,,) = PortfolioManagerArgsBuilder.parse(_args(order));
        _requireUniverseMatches(groups, tokens);
    }

    /// @inheritdoc IPortfolioManagerStrategyFactory
    function requireBalancedWithinTolerance(ISwapVM.Order calldata order, address maker) external view {
        (PortfolioManagerArgsBuilder.Group[] memory groups,, uint32 maxDeviationBps) =
            PortfolioManagerArgsBuilder.parse(_args(order));
        _requireBalancedWithinTolerance(groups, maxDeviationBps, maker);
    }

    /// @inheritdoc IPortfolioManagerStrategyFactory
    function attestBuildParameters(ISwapVM.Order calldata order, address[] calldata tokens) external {
        (PortfolioManagerArgsBuilder.Group[] memory groups,, uint32 maxDeviationBps) =
            PortfolioManagerArgsBuilder.parse(_args(order));
        _requireUniverseMatches(groups, tokens);
        _requireBalancedWithinTolerance(groups, maxDeviationBps, order.maker);

        bytes32 strategyHash = keccak256(abi.encode(order));
        buildParamsAttested[strategyHash] = true;
        emit BuildParametersAttested(strategyHash);
    }

    function _requireUniverseMatches(PortfolioManagerArgsBuilder.Group[] memory groups, address[] calldata tokens)
        private
        pure
    {
        address[] memory declared = PortfolioManagerArgsBuilder.flattenTokens(groups);

        for (uint256 i = 0; i < declared.length; i++) {
            bool shipped = false;
            for (uint256 j = 0; j < tokens.length; j++) {
                if (declared[i] == tokens[j]) {
                    shipped = true;
                    break;
                }
            }
            require(shipped, PortfolioManagerStrategyFactoryDeclaredTokenNotShipped(declared[i]));
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            bool isDeclared = false;
            for (uint256 j = 0; j < declared.length; j++) {
                if (tokens[i] == declared[j]) {
                    isDeclared = true;
                    break;
                }
            }
            require(isDeclared, PortfolioManagerStrategyFactoryShippedTokenNotDeclared(tokens[i]));
        }
    }

    function _requireBalancedWithinTolerance(
        PortfolioManagerArgsBuilder.Group[] memory groups,
        uint32 maxDeviationBps,
        address maker
    ) private view {
        if (maxDeviationBps == 0) return;

        uint256 n = groups.length;
        uint256[] memory groupValuesWad = new uint256[](n);
        uint256 totalValueWad;
        for (uint256 i = 0; i < n; i++) {
            groupValuesWad[i] = PortfolioManagerArgsBuilder.groupValueWad(groups[i], maker);
            totalValueWad += groupValuesWad[i];
        }

        for (uint256 i = 0; i < n; i++) {
            uint256 actualShareWad = groupValuesWad[i] * WAD / totalValueWad;
            uint256 targetWeightWad = groups[i].weight;
            uint256 diffWad =
                actualShareWad > targetWeightWad ? actualShareWad - targetWeightWad : targetWeightWad - actualShareWad;
            uint256 deviationBps = diffWad * PM_BPS / targetWeightWad;
            require(
                deviationBps <= maxDeviationBps,
                PortfolioManagerStrategyFactoryExcessivePriceDeviation(i, actualShareWad, targetWeightWad)
            );
        }
    }

    /// @dev Shared by both validators: extracts the curve opcode's own encoded `args` out of
    ///      `order`'s program bytes -- same opcode/length checks `requireUniverseMatches` always
    ///      did, factored out so `requireBalancedWithinTolerance` doesn't repeat them.
    function _args(ISwapVM.Order calldata order) private pure returns (bytes calldata args) {
        bytes calldata program = MakerTraitsLib.program(order.traits, order.data);
        require(
            program.length >= 2 && uint8(program[0]) == PortfolioManagerProgramBuilder.CURVE_OPCODE,
            PortfolioManagerStrategyFactoryNotAPortfolioManagerStrategy()
        );

        uint256 argsLength = uint8(program[1]);
        args = program[2:2 + argsLength];
    }
}
