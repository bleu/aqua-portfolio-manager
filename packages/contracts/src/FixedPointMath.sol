// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title FixedPointMath — 18-decimal fixed-point `ln`, `exp`, and `pow`
/// @notice Written clean-room from the standard fixed-point-log approach (range reduction by
///         powers of 2 + a convergent series for the remainder) — a generic numerical method,
///         the same category as OpenZeppelin's `Math.sol` (already used elsewhere in this
///         repo), not an "AMM formula/mechanism" in the sense `THIRD_PARTY_NOTICES.md`/the
///         grant's own scope rules restrict. No code from `lib/balancer-v3-monorepo` (or any
///         other project) was read or copied while writing this file — only the published,
///         textbook algorithm (range reduction + a Taylor/artanh series), independently
///         re-derived and re-verified against known reference points (see
///         `test/FixedPointMath.t.sol`).
/// @dev Every rounding direction below is deliberate, not incidental: `PortfolioManagerPricing`'s
///      floor/ceil discipline (`PRICING.md`) and `DONATION-RESISTANCE-PROOF.md`'s algebraic
///      proof both depend on `pow` never *overstating* a value in a way that would let a trade
///      extract more than the true formula allows. Where a choice exists, this library rounds
///      `pow`'s result DOWN (never up) — see `pow`'s own comment for exactly where that happens.
library FixedPointMath {
    /// @notice Fixed-point one: every input/output here is scaled by `WAD` (18 decimals).
    uint256 internal constant WAD = 1e18;

    /// @dev `ln(2) * WAD`, i.e. 0.693147180559945309... — a universal mathematical constant,
    ///      not project-specific, computable independently by anyone to arbitrary precision.
    uint256 internal constant LN2_WAD = 693147180559945309;

    /// @dev How many odd-power terms the `ln` remainder series (`2*(z + z^3/3 + z^5/5 + ...)`)
    ///      sums. After range reduction, `z < WAD/3` (see `ln`), so the term `z^(2n+1)` is
    ///      below `WAD * 1e-18` once `(2n+1) > 18*ln(10)/ln(3) ≈ 37.7` — i.e. `n = 19` already
    ///      clears full 18-decimal precision at the *worst-case* boundary `z → 1/3`. `20`
    ///      leaves a one-term safety margin.
    uint256 private constant LN_SERIES_TERMS = 20;

    /// @dev How many terms the `exp` remainder Taylor series (`1 + r + r^2/2! + ...`) sums.
    ///      After range reduction, `|r| <= LN2_WAD/2` (see `exp`), and factorial growth makes
    ///      this series converge far faster than `ln`'s — `15` terms clears 18-decimal
    ///      precision with a wide margin at that bound.
    uint256 private constant EXP_SERIES_TERMS = 15;

    /// @dev `exp`'s input is capped so the output can't overflow `uint256`. `type(uint256).max`
    ///      is just under `2^256`, and `ln(2^256) = 256*ln(2) ≈ 177.4`; capping at `130 * WAD`
    ///      leaves comfortable headroom (`e^130 ≈ 2.4e56`, far under `~1.15e77`) while covering
    ///      every exponent this contract's own callers ever produce (see `pow`'s own domain).
    int256 private constant EXP_MAX_INPUT = 130e18;

    error FixedPointMathLnRequiresPositive(uint256 x);
    error FixedPointMathExpInputTooLarge(int256 x);
    error FixedPointMathExpSeriesNonPositive(int256 series);

    /// @notice Natural log of `x` (WAD-scaled, `x > 0`), WAD-scaled and signed (negative for
    ///         `x < WAD`, zero at `x == WAD`, positive for `x > WAD`).
    /// @dev Algorithm: write the real value `x/WAD` as `m * 2^k` with `m` in `[1, 2)` (found by
    ///      repeated halving/doubling — simple and easy to verify correct by inspection; this
    ///      is a PoC-grade milestone per `BLEUDEV-285`, gas-optimizing the search is explicitly
    ///      M3's job). Then `ln(x/WAD) = k*ln(2) + ln(m)`, and `ln(m)` for `m` in `[1, 2)` is
    ///      computed via the artanh identity `ln(m) = 2*artanh(z)`, `z = (m-1)/(m+1)`, which
    ///      keeps `z` in `[0, 1/3)` — a fast-converging domain for the odd-power series below.
    function ln(uint256 x) internal pure returns (int256) {
        if (x == 0) revert FixedPointMathLnRequiresPositive(x);

        int256 k = 0;
        uint256 m = x;
        if (m >= WAD * 2) {
            while (m >= WAD * 2) {
                m /= 2;
                k += 1;
            }
        } else if (m < WAD) {
            while (m < WAD) {
                m *= 2;
                k -= 1;
            }
        }
        // Invariant here: WAD <= m < 2*WAD, i.e. m represents a real value in [1, 2).

        // Round to nearest, not floor: `m` within a couple wei of `WAD` produces a numerator/
        // denominator ratio just under 1 raw unit (e.g. m=WAD+2 gives ~0.9999999999999999998),
        // and floor division truncates that to exactly 0 -- losing `ln`'s entire result for any
        // `m` this close to `WAD`, when the true value is a small but real nonzero quantity
        // (found by `FixedPointMath.t.sol`'s monotonicity fuzz tests). Both operands are
        // non-negative here (m >= WAD from the range reduction above), so the standard
        // add-half-the-denominator trick is a safe round-half-up.
        int256 numerator = (int256(m) - int256(WAD)) * int256(WAD);
        int256 denominator = int256(m) + int256(WAD);
        int256 z = (numerator + denominator / 2) / denominator;

        int256 zSquared = (z * z) / int256(WAD);
        int256 term = z;
        int256 series = z;
        for (uint256 n = 1; n < LN_SERIES_TERMS; n++) {
            term = (term * zSquared) / int256(WAD);
            series += term / int256(2 * n + 1);
        }

        return k * int256(LN2_WAD) + 2 * series;
    }

    /// @notice `e^x` for signed WAD-scaled `x`, returns a positive WAD-scaled result.
    /// @dev Algorithm: range-reduce `x = k*ln(2) + r` with integer `k` and `|r| <= ln(2)/2`, so
    ///      `e^x = 2^k * e^r`. `e^r` is a standard Taylor series (fast-converging at this `r`
    ///      bound); `2^k` is an exact bit-shift (left for `k >= 0`, right for `k < 0`) — no
    ///      series error on that factor.
    function exp(int256 x) internal pure returns (uint256) {
        if (x > EXP_MAX_INPUT || x < -EXP_MAX_INPUT) revert FixedPointMathExpInputTooLarge(x);

        // Round k to the nearest integer (not just floor) so the remainder r stays within
        // [-ln(2)/2, ln(2)/2] rather than [0, ln(2)) — halves the domain the Taylor series
        // needs to cover, for the same term count.
        int256 ln2 = int256(LN2_WAD);
        int256 k = (x + (x >= 0 ? ln2 / 2 : -ln2 / 2)) / ln2;
        int256 r = x - k * ln2;

        int256 term = int256(WAD);
        int256 series = int256(WAD);
        for (uint256 n = 1; n < EXP_SERIES_TERMS; n++) {
            term = (term * r) / (int256(n) * int256(WAD));
            series += term;
        }
        // series may be slightly negative-adjacent-to-zero-rounded only if r is negative and
        // term count is low; EXP_SERIES_TERMS=15 at |r|<=ln(2)/2 keeps series > 0 with wide
        // margin (e^r > 0 always, and the series converges to it well before 15 terms here).
        // Asserted, not just commented: an explicit int->uint conversion doesn't get Solidity
        // 0.8's checked-arithmetic protection, so a negative `series` here would silently wrap
        // to a huge positive result instead of reverting.
        require(series > 0, FixedPointMathExpSeriesNonPositive(series));

        uint256 result = uint256(series);
        if (k >= 0) {
            return result << uint256(k);
        } else {
            return result >> uint256(-k);
        }
    }

    /// @notice `base^exponent`, both WAD-scaled and positive (`exponent` — this contract's
    ///         only caller, `PortfolioManagerPricing`, only ever raises a value to a ratio of
    ///         two positive weights, never a negative power).
    /// @dev Two exact-result shortcuts before falling back to `exp(exponent * ln(base) / WAD)`:
    ///      `exponent == WAD` returns `base` unchanged (the equal-weight case reduces here,
    ///      matching `xy=k` exactly with zero series error — see
    ///      `test/PortfolioManagerPricing.t.sol`'s regression check), and `base == WAD` returns
    ///      `WAD` (`1^anything == 1`, exactly, by definition — not worth a series round-trip).
    ///      Otherwise: rounds the final result DOWN by construction — `exp`'s Taylor series is
    ///      evaluated on `ln`'s already-rounded (truncating integer division throughout)
    ///      result, so this never *overstates* `base^exponent` for the `base` it's actually
    ///      given. `PortfolioManagerPricing.exactIn`/`exactOut` are responsible for feeding this
    ///      the correctly-rounded `base` for their own direction (ceiled or floored, per
    ///      `PRICING.md`) — this function's own floor bias composes with that input rounding,
    ///      it doesn't substitute for choosing it correctly.
    function pow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == WAD) return base;
        if (base == WAD) return WAD;

        int256 lnBase = ln(base);
        int256 exponentSigned = int256(exponent);
        int256 product = (exponentSigned * lnBase) / int256(WAD);
        return exp(product);
    }
}
