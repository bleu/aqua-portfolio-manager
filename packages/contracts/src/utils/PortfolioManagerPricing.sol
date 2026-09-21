// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {FixedPointMath} from "./FixedPointMath.sol";

/// @title PortfolioManagerPricing — the constant-mean weighted curve, per PRICING.md
/// @notice Implements fixed-point versions of PRICING.md's pricing formulas — the
///         published Balancer weighted-pool formula (Martinelli & Mushegian, 2019,
///         "Balancer: A non-custodial portfolio manager, liquidity provider, and price
///         sensor"), reimplemented from scratch (see THIRD_PARTY_NOTICES.md / ADR-0004), not
///         Balancer's GPL Solidity.
/// @dev Balances and quoted amounts must share the same units. PortfolioManagerSwap supplies
/// oracle-valued group totals and converts native token amounts around these calls. This
/// library itself never reads a balance or price.
library PortfolioManagerPricing {
    uint256 internal constant WAD = FixedPointMath.WAD;

    error PortfolioManagerPricingZeroBalance();
    error PortfolioManagerPricingInsufficientOutputBalance(uint256 balanceOut, uint256 amountOut);
    error PortfolioManagerPricingPoweredRatioBelowPrecisionFloor(uint256 poweredRatio);

    /// @dev Rejects exact-in powers below 1e-9 where fixed-point error can dominate the
    /// remaining output reserve. This is a precision floor on the power, not a minimum
    /// balance. Retained as a limit on near-total depletion even with directed powers.
    uint256 private constant MIN_TRUSTWORTHY_POWERED_RATIO = WAD / 1e9;

    /// @param weightIn/weightOut WAD-scaled; need not sum to WAD by themselves (only the full
    ///        declared universe's weights do, per `PortfolioManagerArgsCodec`) — only their
    ///        ratio matters to this formula.
    /// @param feeWad WAD-scaled fee fraction taken on the input side (ADR-0008: 2 bps = 2e14).
    struct PoolState {
        uint256 balanceIn;
        uint256 balanceOut;
        uint256 weightIn;
        uint256 weightOut;
        uint256 feeWad;
    }

    /// @notice `SP(i→o) = (B_i / w_i) / (B_o / w_o)`, WAD-scaled, before fees — token `i`
    ///         priced in terms of token `o`.
    /// @dev The second multiplication uses weightIn as its explicit scale.
    function spotPrice(PoolState memory q) internal pure returns (uint256) {
        _requireNonZeroBalances(q);
        return FixedPointMath.mulDown(FixedPointMath.divDown(q.balanceIn, q.balanceOut), q.weightOut, q.weightIn);
    }

    /// @notice Amount of token `o` received for exactly `amountIn` of token `i`.
    /// @dev Ceils the input ratio, floors the exponent (the base is <= WAD), and uses an
    /// upper bound on the power before subtracting it from WAD. Flooring the resulting
    /// output therefore preserves the pool-favoring direction through every step.
    /// @dev The existing powered-ratio floor still limits near-total depletion at unequal
    /// weights. The directed power bound supplies conservative rounding independently.
    function exactIn(PoolState memory q, uint256 amountIn) internal pure returns (uint256 amountOut) {
        _requireNonZeroBalances(q);

        uint256 amountInEff = FixedPointMath.mulDown(amountIn, WAD - q.feeWad);
        uint256 ratio = FixedPointMath.divUp(q.balanceIn, q.balanceIn + amountInEff);
        uint256 exponent = FixedPointMath.divDown(q.weightIn, q.weightOut);
        uint256 poweredRatio = FixedPointMath.powUp(ratio, exponent);
        // Equal exponents use the exact identity shortcut and bypass the precision floor.
        require(
            exponent == WAD || poweredRatio >= MIN_TRUSTWORTHY_POWERED_RATIO,
            PortfolioManagerPricingPoweredRatioBelowPrecisionFloor(poweredRatio)
        );

        amountOut = FixedPointMath.mulDown(q.balanceOut, WAD - poweredRatio);
        require(amountOut < q.balanceOut, PortfolioManagerPricingInsufficientOutputBalance(q.balanceOut, amountOut));
    }

    /// @notice Gross amount of token `i` (fee included) required to receive exactly
    ///         `amountOut` of token `o`.
    /// @dev Rounds UP throughout — both the intermediate pre-fee amount and the final
    ///      fee-grossed-up result, per PRICING.md, so every rounding choice favors the pool,
    ///      never the trader. `amountOut < balanceOut` is a required precondition (checked,
    ///      not assumed) — the curve is undefined once the output side would be fully drained.
    /// @dev `exponent` here is `w_o/w_i` — the inverse of `exactIn`'s own `w_i/w_o` — because
    ///      solving the same invariant `(B_i+A_i)^w_i * (B_o-A_o)^w_o = B_i^w_i * B_o^w_o` for
    ///      `A_i` given `A_o` isolates `(B_i+A_i)/B_i` raised to `1/w_i`, not `1/w_o`; the two
    ///      directions aren't the same formula with variables swapped. Only invisible to test at
    ///      `w_i == w_o`, where both ratios equal 1 — see `testFuzz_ExactOutNeverDecreasesTheInvariant`
    ///      for coverage at unequal weights.
    function exactOut(PoolState memory q, uint256 amountOut) internal pure returns (uint256 amountIn) {
        _requireNonZeroBalances(q);
        require(amountOut < q.balanceOut, PortfolioManagerPricingInsufficientOutputBalance(q.balanceOut, amountOut));

        uint256 ratio = FixedPointMath.divUp(q.balanceOut, q.balanceOut - amountOut);
        // Here ratio >= WAD, so increasing either ratio or exponent increases the power.
        // Both must round up, and pow itself needs an upper bound before subtracting WAD:
        // ceiling the later divisions cannot recover precision already lost inside pow.
        uint256 exponent = FixedPointMath.divUp(q.weightOut, q.weightIn);
        uint256 poweredRatio = FixedPointMath.powUp(ratio, exponent);

        uint256 amountInEff = FixedPointMath.mulUp(q.balanceIn, poweredRatio - WAD);
        amountIn = FixedPointMath.divUp(amountInEff, WAD - q.feeWad);
    }

    /// @dev `B_i == 0` or `B_o == 0`: a weighted pool's price is undefined at a zero balance
    ///      on either side — same requirement `BasketXYCSwap.sol`'s PoC already enforces.
    function _requireNonZeroBalances(PoolState memory q) private pure {
        require(q.balanceIn > 0 && q.balanceOut > 0, PortfolioManagerPricingZeroBalance());
    }
}
