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
    /// @dev The curve only prices cross-group pairs (ADR-0003: "intra-group drift is allowed
    ///      by design," i.e. not priced by this formula at all) — a same-group swap would
    ///      silently degenerate to a spot price of exactly 1 with zero skew-based curve
    ///      behavior, so it's rejected outright instead of left as an undefined edge case.
    error PortfolioManagerSwapSameGroupSwap(uint256 groupIndex);
    /// @dev A multi-member group's aggregate value can afford `amountOut`, but the specific
    ///      traded member's own raw balance can't -- only reachable when a group's members hold
    ///      sufficiently divergent oracle prices (a depeg) that one low-priced member's raw
    ///      balance no longer tracks its share of the group's total value.
    error PortfolioManagerSwapInsufficientMemberBalance(address token, uint256 requested, uint256 available);
}
