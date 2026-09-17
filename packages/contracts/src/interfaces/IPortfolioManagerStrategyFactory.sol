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

    /// @notice Reverts unless `order`'s own encoded universe matches `tokens` exactly -- same
    ///         members, both directions. Only accepts programs whose first (and, for a real PM
    ///         strategy, only) instruction is `PortfolioManagerProgramBuilder.CURVE_OPCODE`.
    function requireUniverseMatches(ISwapVM.Order calldata order, address[] calldata tokens) external pure;

    /// @notice Reverts unless `maker`'s current wallet composition is within `order`'s declared
    ///         `maxDeviationBps` of every group's target weight (no-op when it's 0). A one-time
    ///         ship()-time check, batched alongside `requireUniverseMatches` -- see
    ///         `PortfolioManagerE2EBase.sol::_shipOnly`.
    function requireBalancedWithinTolerance(ISwapVM.Order calldata order, address maker) external view;
}
