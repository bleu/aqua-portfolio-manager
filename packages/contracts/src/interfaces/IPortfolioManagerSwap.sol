// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title IPortfolioManagerSwap
/// @notice Errors-only: `PortfolioManagerSwap`'s own swap logic (`_portfolioManagerSwapXD`) is
///         `internal`, dispatched only through the opcode table `PortfolioManagerRouter` wires
///         up — it has no external/public function of its own to declare here. Still separated
///         out so external tooling can decode these custom errors without importing the whole
///         contract.
interface IPortfolioManagerSwap {
    error PortfolioManagerSwapTokenNotDeclared(address token);
    error PortfolioManagerSwapRecomputeDetected();
}
