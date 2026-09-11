// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {FixedPointMath} from "./FixedPointMath.sol";

/// @title PortfolioManagerPricing — the constant-mean weighted curve, per PRICING.md
/// @notice Implements PRICING.md's spot-price, exact-in, and exact-out formulas exactly — the
///         published Balancer weighted-pool formula (Martinelli & Mushegian, 2019,
///         "Balancer: A non-custodial portfolio manager, liquidity provider, and price
///         sensor"), reimplemented from scratch (see THIRD_PARTY_NOTICES.md / ADR-0004), not
///         Balancer's GPL Solidity.
/// @dev `balanceIn`/`balanceOut` here are already-resolved values — either a single-token
///      group's raw wallet `balanceOf` reading, or a multi-token group's
///      `OracleAdapter.groupValueWad` sum (ADR-0003). This library is opaque to which case
///      produced them and never itself reads a balance or a price — PRICING.md's own scope
///      note is explicit that resolving `B_i`/`B_o` is a prior step, not this formula's job.
library PortfolioManagerPricing {
    uint256 internal constant WAD = 1e18;

    error PortfolioManagerPricingZeroBalance();
    error PortfolioManagerPricingInsufficientOutputBalance(uint256 balanceOut, uint256 amountOut);

    /// @param weightIn/weightOut WAD-scaled; need not sum to WAD by themselves (only the full
    ///        declared universe's weights do, per `PortfolioManagerArgsBuilder`) — only their
    ///        ratio matters to this formula.
    /// @param feeWad WAD-scaled fee fraction taken on the input side (ADR-0008: 2 bps = 2e14).
    struct Quote {
        uint256 balanceIn;
        uint256 balanceOut;
        uint256 weightIn;
        uint256 weightOut;
        uint256 feeWad;
    }

    /// @notice `SP(i→o) = (B_i / w_i) / (B_o / w_o)`, WAD-scaled, before fees — token `i`
    ///         priced in terms of token `o`.
    function spotPrice(Quote memory q) internal pure returns (uint256) {
        _requireNonZeroBalances(q);
        return (q.balanceIn * WAD / q.balanceOut) * q.weightOut / q.weightIn;
    }

    /// @notice Amount of token `o` received for exactly `amountIn` of token `i`.
    /// @dev Rounds `amountOut` DOWN — the pool keeps the remainder, never the trader, same
    ///      direction `BasketXYCSwap.sol`'s xy=k special case already uses. That requires
    ///      `ratio` to be rounded UP (ceiled), not down: `poweredRatio` is monotonic in `ratio`,
    ///      so flooring `ratio` would floor `poweredRatio` too, which *inflates*
    ///      `WAD - poweredRatio` (and therefore `amountOut`) past the true value — handing the
    ///      trader up to a few wei the curve doesn't actually allow (caught by
    ///      `test_ExactInRoundsInThePoolsFavorAtEqualWeights`, which hits `pow`'s exact
    ///      `exponent == WAD` shortcut, so this fix is exact there). Off the equal-weight
    ///      shortcut, `pow`'s own series truncation (already floor-biased, see
    ///      `FixedPointMath.pow`) is composed on top of this ceiled input rather than proven
    ///      bit-exact through the general case — PoC-grade precision, not a closed rounding
    ///      proof through `ln`/`exp`.
    function exactIn(Quote memory q, uint256 amountIn) internal pure returns (uint256 amountOut) {
        _requireNonZeroBalances(q);

        uint256 amountInEff = amountIn * (WAD - q.feeWad) / WAD;
        uint256 ratio = _ceilDiv(q.balanceIn * WAD, q.balanceIn + amountInEff);
        uint256 exponent = q.weightIn * WAD / q.weightOut;
        uint256 poweredRatio = FixedPointMath.pow(ratio, exponent);

        amountOut = q.balanceOut * (WAD - poweredRatio) / WAD;
    }

    /// @notice Gross amount of token `i` (fee included) required to receive exactly
    ///         `amountOut` of token `o`.
    /// @dev Rounds UP throughout — both the intermediate pre-fee amount and the final
    ///      fee-grossed-up result, per PRICING.md, so every rounding choice favors the pool,
    ///      never the trader. `amountOut < balanceOut` is a required precondition (checked,
    ///      not assumed) — the curve is undefined once the output side would be fully drained.
    function exactOut(Quote memory q, uint256 amountOut) internal pure returns (uint256 amountIn) {
        _requireNonZeroBalances(q);
        require(amountOut < q.balanceOut, PortfolioManagerPricingInsufficientOutputBalance(q.balanceOut, amountOut));

        uint256 ratio = q.balanceOut * WAD / (q.balanceOut - amountOut);
        uint256 exponent = q.weightIn * WAD / q.weightOut;
        uint256 poweredRatio = FixedPointMath.pow(ratio, exponent);

        uint256 amountInEff = _ceilDiv(q.balanceIn * (poweredRatio - WAD), WAD);
        amountIn = _ceilDiv(amountInEff * WAD, WAD - q.feeWad);
    }

    /// @dev `B_i == 0` or `B_o == 0`: a weighted pool's price is undefined at a zero balance
    ///      on either side — same requirement `BasketXYCSwap.sol`'s PoC already enforces.
    function _requireNonZeroBalances(Quote memory q) private pure {
        require(q.balanceIn > 0 && q.balanceOut > 0, PortfolioManagerPricingZeroBalance());
    }

    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        return (a + b - 1) / b;
    }
}
