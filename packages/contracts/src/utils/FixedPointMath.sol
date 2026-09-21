// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ud} from "prb-math/UD60x18.sol";

/// @title FixedPointMath — 18-decimal fixed-point `pow` (PRBMath-backed) plus explicit-rounding
///        `mul`/`div`
/// @notice `pow` is a thin wrapper around PRBMath (`lib/prb-math`, MIT), not a hand-rolled
///         `ln`/`exp`/`pow` — a battle-tested, widely-used library beats reimplementing
///         transcendental math from scratch. `mulUp`/`mulDown`/`divUp`/`divDown` are thin
///         wrappers around OpenZeppelin's `Math.mulDiv` — every other WAD-scaled multiply/divide
///         in this codebase is otherwise plain `a * b / WAD`-style floor division (Solidity's
///         own default), so these exist specifically for callers that need the *other*
///         direction (ceiling) named explicitly, instead of composing it by hand at each call
///         site the way `PortfolioManagerPricing` used to.
library FixedPointMath {
    /// @notice Fixed-point one: every input/output here is scaled by `WAD` (18 decimals).
    uint256 internal constant WAD = 1e18;

    error FixedPointMathBaseBelowOne();

    /// @notice `base^exponent`, both WAD-scaled and positive (`exponent` — this contract's
    ///         only caller, `PortfolioManagerPricing`, only ever raises a value to a ratio of
    ///         two positive weights, never a negative power).
    /// @dev PRBMath does not provide a directed rounding guarantee for this approximation.
    /// Exact-in uses it with a powered-ratio precision floor and empirical invariant tests;
    /// those checks are not a universal rounding proof. Exact-out uses powUp below because
    /// subtracting WAD from an underestimated power can undercharge the trader.
    function pow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        return ud(base).pow(ud(exponent)).unwrap();
    }

    /// @notice Upper bound on base^exponent for base >= WAD, both inputs WAD-scaled.
    /// @dev Uses the pinned PRBMath log2/exp2 implementation; recheck these bounds on upgrades.
    /// log2 has 59 fractional iterations. Its first 18 bit weights are exact; the remaining
    /// 41 lose <1 raw unit each. The uncomputed tail loses <2 units, and normalization plus
    /// the geometrically weighted state truncations lose <3 more. Adding 64 therefore
    /// upper-bounds log2. Ceiling its product with exponent preserves that upper bound.
    /// exp2 loses <4e-18 relatively before its final integer truncation: 64 factors each
    /// lose <2^-64, the argument conversion loses <2^-64, and product shifts <64*2^-191.
    /// Adding ceil(result * 8e-18) + 1 covers that relative loss and the final truncation.
    /// PRBMath's exponent limit and checked arithmetic revert if the bound cannot fit.
    /// Exact identities bypass the approximation so zero-size/equal-weight quotes stay exact.
    function powUp(uint256 base, uint256 exponent) internal pure returns (uint256) {
        require(base >= WAD, FixedPointMathBaseBelowOne());
        if (base == WAD || exponent == 0) return WAD;
        if (exponent == WAD) return base;

        uint256 logUpper = ud(base).log2().unwrap() + 64;
        uint256 result = ud(mulUp(logUpper, exponent)).exp2().unwrap();
        return result + mulUp(result, 8) + 1;
    }

    /// @notice `a * b / WAD`, rounded down (floor).
    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, b, WAD);
    }

    /// @notice `a * b / WAD`, rounded up (ceil).
    function mulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, b, WAD, Math.Rounding.Ceil);
    }

    /// @notice `a * WAD / b`, rounded down (floor).
    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, WAD, b);
    }

    /// @notice `a * WAD / b`, rounded up (ceil).
    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, WAD, b, Math.Rounding.Ceil);
    }
}
