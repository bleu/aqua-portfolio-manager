// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMath} from "./FixedPointMath.sol";

/// @title PortfolioManagerPricing — the constant-mean weighted curve, per PRICING.md
/// @notice Implements fixed-point versions of PRICING.md's pricing formulas — the
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
    uint256 internal constant WAD = FixedPointMath.WAD;

    error PortfolioManagerPricingZeroBalance();
    error PortfolioManagerPricingInsufficientOutputBalance(uint256 balanceOut, uint256 amountOut);
    error PortfolioManagerPricingPoweredRatioBelowPrecisionFloor(uint256 poweredRatio);

    /// @dev Rejects exact-in powers below 1e-9 where fixed-point error can dominate the
    /// remaining output reserve. This is a precision floor on the power, not a minimum
    /// balance or a proof of directed rounding for all accepted quotes.
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
    /// @dev The second step multiplies by a *weight ratio*, not a WAD-scaled factor, so it's
    ///      `Math.mulDiv(x, weightOut, weightIn)` directly rather than `FixedPointMath.mulDown`
    ///      (which assumes a `/ WAD` denominator) -- same floor rounding either way.
    function spotPrice(PoolState memory q) internal pure returns (uint256) {
        _requireNonZeroBalances(q);
        return Math.mulDiv(FixedPointMath.divDown(q.balanceIn, q.balanceOut), q.weightOut, q.weightIn);
    }

    /// @notice Amount of token `o` received for exactly `amountIn` of token `i`.
    /// @dev Ceils the input ratio and floors the final output division. For equal weights,
    /// pow returns the ratio exactly and those steps round in the pool's favor. At unequal
    /// weights, PRBMath pow is approximate: the precision floor and invariant tests provide
    /// coverage, not a closed proof that every accepted quote rounds in the pool's favor.
    /// @dev At an extreme weight ratio combined with a small `balanceIn` and a large trade,
    ///      `poweredRatio` can collapse to a raw WAD value near (or exactly) 0 -- a value
    ///      technically nonzero but well below what fixed-point precision can represent
    ///      trustworthily -- which would otherwise silently hand out close to the pool's entire
    ///      `balanceOut` for an ordinary-sized trade. Guarded explicitly below
    ///      (`MIN_TRUSTWORTHY_POWERED_RATIO`), not just via the downstream `amountOut <
    ///      balanceOut` check, which only catches the exactly-zero case.
    function exactIn(PoolState memory q, uint256 amountIn) internal pure returns (uint256 amountOut) {
        _requireNonZeroBalances(q);

        uint256 amountInEff = FixedPointMath.mulDown(amountIn, WAD - q.feeWad);
        uint256 ratio = FixedPointMath.divUp(q.balanceIn, q.balanceIn + amountInEff);
        uint256 exponent = FixedPointMath.divDown(q.weightIn, q.weightOut);
        uint256 poweredRatio = FixedPointMath.pow(ratio, exponent);
        // `exponent == WAD` is `pow`'s own exact shortcut (returns `ratio` unchanged, no series
        // involved) -- a legitimately tiny `poweredRatio` there is an exact value, not a
        // precision artifact, so the floor only applies off that shortcut.
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
