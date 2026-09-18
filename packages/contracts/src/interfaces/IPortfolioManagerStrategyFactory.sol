// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";

/// @title IPortfolioManagerStrategyFactory
/// @notice External interface for `PortfolioManagerStrategyFactory` — see that contract for the
///         full rationale (why it validates a PM strategy's `ship()` encoding rather than
///         forwarding to `IAqua.ship()` itself).
interface IPortfolioManagerStrategyFactory {
    error PortfolioManagerStrategyFactoryNotAPortfolioManagerStrategy();
    error PortfolioManagerStrategyFactoryDeclaredTokenNotShipped(address token);
    error PortfolioManagerStrategyFactoryShippedTokenNotDeclared(address token);
    /// @dev Ship-time counterpart to `IPortfolioManagerSwap.PortfolioManagerSwapExcessivePriceDeviation`
    ///      -- `maker`'s wallet is already off-target beyond `maxDeviationBps` before the strategy
    ///      even starts trading (e.g. it was funded that way, or drifted between an earlier
    ///      strategy's expiry and this one's `ship()`).
    error PortfolioManagerStrategyFactoryExcessivePriceDeviation(
        uint256 groupIndex, uint256 actualShareWad, uint256 targetWeightWad
    );

    /// @dev Emitted once per successful `attestBuildParameters` call -- not just on the first,
    ///      since re-attesting an already-attested strategy is a harmless no-op, not an error.
    event BuildParametersAttested(bytes32 indexed strategyHash);

    /// @notice Reverts unless `order`'s own encoded universe matches `tokens` exactly -- same
    ///         members, both directions. Only accepts programs whose first (and, for a real PM
    ///         strategy, only) instruction is `PortfolioManagerProgramBuilder.CURVE_OPCODE`.
    function requireUniverseMatches(ISwapVM.Order calldata order, address[] calldata tokens) external pure;

    /// @notice Reverts unless `maker`'s current wallet composition is within `order`'s declared
    ///         `maxDeviationBps` of every group's target weight (no-op when it's 0). A one-time
    ///         ship()-time check, batched alongside `requireUniverseMatches` -- see
    ///         `PortfolioManagerE2EBase.sol::_shipOnly`.
    function requireBalancedWithinTolerance(ISwapVM.Order calldata order, address maker) external view;

    /// @notice Runs both `requireUniverseMatches` (against `tokens`) and
    ///         `requireBalancedWithinTolerance` (against `order.maker`), then records that this
    ///         strategy's build parameters were validated -- `PortfolioManagerSwap` refuses to
    ///         price any trade for a strategy that was never attested. Permissionless and
    ///         idempotent: the result is a purely mechanical, independently-recomputable on-chain
    ///         fact, not an authorization decision, so who calls it or how many times doesn't
    ///         matter.
    function attestBuildParameters(ISwapVM.Order calldata order, address[] calldata tokens) external;

    /// @notice Whether `attestBuildParameters` has ever succeeded for this `strategyHash`
    ///         (`keccak256(abi.encode(order))` for Aqua-native orders).
    function buildParamsAttested(bytes32 strategyHash) external view returns (bool);
}
