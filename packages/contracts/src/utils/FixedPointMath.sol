// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ud} from "prb-math/UD60x18.sol";

/// @title FixedPointMath — arithmetic with explicit rounding directions
/// @notice Up/Down denote rounding direction, including when converting decimal scales.
/// Multiplication and division use WAD; mulDivDown/mulDivUp accept an explicit denominator. Powers
/// use WAD inputs/outputs and provide conservative bounds rather than nearest estimates.
library FixedPointMath {
    /// @notice Fixed-point one for powers and the default multiplication/division scale.
    uint256 internal constant WAD = 1e18;

    // PRBMath log2: 59 steps, 18 exact weights, 41 truncations (<41 raw units),
    // tail <2 and normalization/state loss <3. A 64-unit correction covers these losses.
    uint256 private constant LOG2_ERROR = 64;
    // exp2's 64 factors and input conversion each err by <2^-64; product shifts add
    // <64*2^-191. Total relative error is <4e-18; allow 8e-18 in either direction.
    uint256 private constant EXP2_RELATIVE_ERROR = 8;

    error FixedPointMathUnsupportedDecimalDifference(uint8 difference);

    /// @notice Lower bound on base^exponent, with WAD-scaled inputs/output; 0^0 is WAD.
    /// @dev Reverts when an intermediate reciprocal power exceeds PRBMath's domain, even
    /// if the final value would fit. Exact shortcuts can cause small discontinuities in
    /// the bounds; directed rounding does not promise strict monotonicity across them.
    function powDown(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == 0 || base == WAD) return WAD;
        if (base == 0 || exponent == WAD) return base;
        if (base < WAD) return divDown(WAD, _powUpAboveOne(divUp(WAD, base), exponent));
        return _powDownAboveOne(base, exponent);
    }

    /// @notice Upper bound on base^exponent, with WAD-scaled inputs/output; 0^0 is WAD.
    /// @dev Shares powDown's intermediate-domain limits and exact shortcut semantics.
    function powUp(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == 0 || base == WAD) return WAD;
        if (base == 0 || exponent == WAD) return base;
        if (base < WAD) return divUp(WAD, _powDownAboveOne(divDown(WAD, base), exponent));
        return _powUpAboveOne(base, exponent);
    }

    /// @dev Recheck the margins against pinned PRBMath on upgrades; +1 covers final truncation.
    /// FixedPointMath.t.sol checks direction with test_PowUpBoundsIndependentReferences and
    /// testFuzz_PowUpSquareRootBoundsExactIntegerSquare, independently of these helpers.
    function _powUpAboveOne(uint256 base, uint256 exponent) private pure returns (uint256) {
        uint256 logUpper = ud(base).log2().unwrap() + LOG2_ERROR;
        uint256 result = ud(mulUp(logUpper, exponent)).exp2().unwrap();
        return result + mulUp(result, EXP2_RELATIVE_ERROR) + 1;
    }

    /// @dev log2 and its product round down; subtract exp2's error margin. The result is >= WAD.
    /// See FixedPointMath.t.sol's testFuzz_PowDownSquareRootBoundsExactIntegerSquare.
    function _powDownAboveOne(uint256 base, uint256 exponent) private pure returns (uint256) {
        uint256 result = ud(mulDown(ud(base).log2().unwrap(), exponent)).exp2().unwrap();
        return Math.max(WAD, result - mulUp(result, EXP2_RELATIVE_ERROR));
    }

    /// @notice `a * b / WAD`, rounded down (floor).
    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return mulDivDown(a, b, WAD);
    }

    /// @notice `a * b / WAD`, rounded up (ceil).
    function mulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return mulDivUp(a, b, WAD);
    }

    /// @notice `a * WAD / b`, rounded down (floor).
    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return mulDivDown(a, WAD, b);
    }

    /// @notice `a * WAD / b`, rounded up (ceil).
    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return mulDivUp(a, WAD, b);
    }

    /// @notice a * b / denominator, rounded down with a full-precision intermediate product.
    function mulDivDown(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        return Math.mulDiv(a, b, denominator);
    }

    /// @notice a * b / denominator, rounded up with a full-precision intermediate product.
    function mulDivUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        return Math.mulDiv(a, b, denominator, Math.Rounding.Ceil);
    }

    /// @notice Converts decimal units, rounding down when precision is lost.
    /// @dev Decimal differences above 77 and unrepresentable scaled results revert.
    function scaleDown(uint256 value, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return value;
        if (fromDecimals < toDecimals) return value * _decimalFactor(toDecimals - fromDecimals);
        return mulDivDown(value, 1, _decimalFactor(fromDecimals - toDecimals));
    }

    /// @notice Converts decimal units, rounding up when precision is lost.
    /// @dev Increasing precision is exact and has the same behavior as scaleDown.
    function scaleUp(uint256 value, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return value;
        if (fromDecimals < toDecimals) return value * _decimalFactor(toDecimals - fromDecimals);
        return mulDivUp(value, 1, _decimalFactor(fromDecimals - toDecimals));
    }

    function _decimalFactor(uint8 difference) private pure returns (uint256) {
        require(difference <= 77, FixedPointMathUnsupportedDecimalDifference(difference));
        return 10 ** uint256(difference);
    }
}
