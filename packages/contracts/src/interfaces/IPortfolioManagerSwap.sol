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
    ///      traded member's own raw balance can't -- reachable whenever a member's raw balance
    ///      diverges from its share of the group's total value, whether from oracle price
    ///      divergence (a depeg) or simply an imbalanced raw funding across members.
    error PortfolioManagerSwapInsufficientMemberBalance(address token, uint256 requested, uint256 available);
    /// @dev Pre-trade circuit breaker: the traded pair's current spot price (`spotPrice`, exactly
    ///      `WAD` at perfect target composition regardless of weight ratio) has drifted further
    ///      from `WAD` than `maxDeviationBps` allows -- e.g. a direct Safe-owner withdrawal that
    ///      bypasses `ship()`/`BasketScopeGuard` entirely. Checked against current state, not the
    ///      post-trade state, so once a pair is skewed past this, no single trade can self-correct
    ///      past the check in one step -- that pair stays untradeable until external action
    ///      (a deposit, or a fresh strategy) restores it within tolerance.
    error PortfolioManagerSwapExcessivePriceDeviation(uint256 spotPriceWad, uint256 maxDeviationBps);
}
