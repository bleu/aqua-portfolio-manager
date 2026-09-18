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

    /// @notice `base^exponent`, both WAD-scaled and positive (`exponent` — this contract's
    ///         only caller, `PortfolioManagerPricing`, only ever raises a value to a ratio of
    ///         two positive weights, never a negative power).
    /// @dev PRBMath's `pow` does not document a directional (always-round-down) rounding
    ///      guarantee for the composed `x^y = 2^(log2(x)*y)` pipeline the way the previous
    ///      hand-rolled implementation did (its internal division/truncation steps aren't
    ///      proven to compose in one direction only). `PortfolioManagerPricing`'s own floor/ceil
    ///      discipline (`PRICING.md`) and `DONATION-RESISTANCE-PROOF.md`'s invariant proof both
    ///      depend on `pow` never *overstating* a value — this is verified empirically instead,
    ///      via the existing `test/FixedPointMath.t.sol` known-value/monotonicity suite plus
    ///      `PortfolioManagerPricing.t.sol`'s `testFuzz_Exact{In,Out}NeverDecreasesTheInvariant`
    ///      fuzz tests (run at high iteration counts specifically to hunt for any case where the
    ///      curve invariant decreases — the same mechanism that caught the exponent bug this
    ///      formula had before).
    function pow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        return ud(base).pow(ud(exponent)).unwrap();
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
