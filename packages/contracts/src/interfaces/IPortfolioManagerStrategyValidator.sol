// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";

/// @title IPortfolioManagerStrategyValidator
/// @notice External interface for `PortfolioManagerStrategyValidator` — see that contract for the
///         full rationale (why it validates a PM strategy's `ship()` encoding rather than
///         forwarding to `IAqua.ship()` itself).
interface IPortfolioManagerStrategyValidator {
    error PortfolioManagerStrategyValidatorNotAPortfolioManagerStrategy();
    error PortfolioManagerStrategyValidatorDeclaredTokenNotShipped(address token);
    error PortfolioManagerStrategyValidatorShippedTokenNotDeclared(address token);

    /// @notice Reverts unless `order`'s own encoded universe matches `tokens` exactly -- same
    ///         members, both directions. Only accepts programs whose first (and, for a real PM
    ///         strategy, only) instruction is `PortfolioManagerProgramBuilder.CURVE_OPCODE`.
    function requireUniverseMatches(ISwapVM.Order calldata order, address[] calldata tokens) external pure;
}
