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

    /// @dev Uses the pinned PRBMath log2/exp2 implementation; recheck these bounds on upgrades.
    /// log2 has 59 fractional iterations. Its first 18 bit weights are exact; the remaining
    /// 41 lose <1 raw unit each. The uncomputed tail loses <2 units, and normalization plus
    /// the geometrically weighted state truncations lose <3 more. Adding 64 therefore
    /// upper-bounds log2. Ceiling its product with exponent preserves that upper bound.
    /// exp2 loses <4e-18 relatively before its final integer truncation: 64 factors each
    /// lose <2^-64, the argument conversion loses <2^-64, and product shifts <64*2^-191.
    /// Adding ceil(result * 8e-18) + 1 covers that relative loss and the final truncation.
    /// PRBMath's exponent limit and checked arithmetic revert if the bound cannot fit.
    function _powUpAboveOne(uint256 base, uint256 exponent) private pure returns (uint256) {
        uint256 logUpper = ud(base).log2().unwrap() + 64;
        uint256 result = ud(mulUp(logUpper, exponent)).exp2().unwrap();
        return result + mulUp(result, 8) + 1;
    }

    /// @dev PRBMath log2 truncates downward. Flooring its product with exponent preserves
    /// a lower binary exponent. exp2's factors can err in either direction, so subtract
    /// ceil(result * 8e-18) to cover its relative overestimate (<4e-18). Its final integer
    /// truncation already favors this lower bound. The true result is at least WAD here.
    function _powDownAboveOne(uint256 base, uint256 exponent) private pure returns (uint256) {
        uint256 result = ud(mulDown(ud(base).log2().unwrap(), exponent)).exp2().unwrap();
        return Math.max(WAD, result - mulUp(result, 8));
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
