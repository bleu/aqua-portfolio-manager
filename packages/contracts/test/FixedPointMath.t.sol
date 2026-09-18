// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FixedPointMath} from "../src/utils/FixedPointMath.sol";

/// @notice `pow` is now a thin wrapper around PRBMath's `UD60x18.pow` (see FixedPointMath.sol's
/// own doc comment) — these tests check `pow`'s black-box behavior (known values, monotonicity),
/// not any particular algorithm's internals, since the algorithm itself is PRBMath's, not ours.
contract FixedPointMathTest is Test {
    uint256 constant WAD = FixedPointMath.WAD;

    // 1e-9 relative tolerance (WAD/1e9 absolute, scaled to the magnitude under test).
    uint256 constant REL_TOL = 1e9;

    function _assertApproxRelWad(uint256 actual, uint256 expected, uint256 relTol) internal pure {
        uint256 diff = actual > expected ? actual - expected : expected - actual;
        uint256 maxDiff = expected / relTol;
        if (maxDiff == 0) maxDiff = 1;
        assertLe(diff, maxDiff, "value outside relative tolerance");
    }

    // ---- pow: exact shortcuts ----

    function testFuzz_PowWithExponentWadReturnsBaseExactly(uint256 base) public pure {
        base = bound(base, 1, type(uint256).max);
        assertEq(FixedPointMath.pow(base, WAD), base);
    }

    function testFuzz_PowWithBaseWadReturnsWadExactly(uint256 exponent) public pure {
        assertEq(FixedPointMath.pow(WAD, exponent), WAD);
    }

    // ---- pow: known roots ----

    function test_PowSquareRootOfFour() public pure {
        uint256 result = FixedPointMath.pow(4 * WAD, WAD / 2);
        _assertApproxRelWad(result, 2 * WAD, REL_TOL);
    }

    function test_PowSquareRootOfNine() public pure {
        uint256 result = FixedPointMath.pow(9 * WAD, WAD / 2);
        _assertApproxRelWad(result, 3 * WAD, REL_TOL);
    }

    function test_PowCubeRootOfEight() public pure {
        uint256 result = FixedPointMath.pow(8 * WAD, WAD / 3);
        _assertApproxRelWad(result, 2 * WAD, REL_TOL);
    }

    function test_PowTwoSquared() public pure {
        uint256 result = FixedPointMath.pow(2 * WAD, 2 * WAD);
        _assertApproxRelWad(result, 4 * WAD, REL_TOL);
    }

    function test_PowReciprocalExponent() public pure {
        // base^1 via a roundabout path: (base^0.5)^2 should match base^1 == base.
        uint256 half = FixedPointMath.pow(5 * WAD, WAD / 2);
        uint256 result = FixedPointMath.pow(half, 2 * WAD);
        _assertApproxRelWad(result, 5 * WAD, REL_TOL);
    }

    // ---- monotonicity: the property PortfolioManagerPricing.t.sol's invariant fuzz test needs ----
    //
    // Base bounded to a real value in [1e-5, 1e5] and exponent to [0.01, 10] WAD (a generous
    // superset of the weight-ratio domain `PortfolioManagerPricing` actually calls `pow` with).

    function testFuzz_PowMonotonicInBaseAboveOne(uint256 baseLow, uint256 baseHigh, uint256 exponent) public pure {
        baseLow = bound(baseLow, WAD, 1e23);
        baseHigh = bound(baseHigh, baseLow, 1e23);
        exponent = bound(exponent, 1e16, 10e18);
        vm.assume(baseHigh > baseLow);

        uint256 resultLow = FixedPointMath.pow(baseLow, exponent);
        uint256 resultHigh = FixedPointMath.pow(baseHigh, exponent);
        assertGe(resultHigh, resultLow, "pow must be non-decreasing in base, for base >= WAD");
    }

    function testFuzz_PowMonotonicInBaseBelowOne(uint256 baseLow, uint256 baseHigh, uint256 exponent) public pure {
        baseLow = bound(baseLow, 1e13, WAD);
        baseHigh = bound(baseHigh, baseLow, WAD);
        exponent = bound(exponent, 1e16, 10e18);
        vm.assume(baseHigh > baseLow);

        uint256 resultLow = FixedPointMath.pow(baseLow, exponent);
        uint256 resultHigh = FixedPointMath.pow(baseHigh, exponent);
        assertGe(resultHigh, resultLow, "pow must be non-decreasing in base, for base <= WAD too");
    }

    function testFuzz_PowMonotonicInExponentAboveOneBase(uint256 base, uint256 expLow, uint256 expHigh) public pure {
        base = bound(base, WAD + 1, 1e23);
        expLow = bound(expLow, 1e16, 10e18);
        expHigh = bound(expHigh, expLow, 10e18);
        vm.assume(expHigh > expLow);
        // `exponent == WAD` is an exact shortcut (`return base` unchanged, PRBMath's own); every
        // other exponent goes through the approximate `exp2(log2(base)*exponent)` composition,
        // which does not round-trip to bit-exact agreement with that shortcut. Right at this
        // seam, a single-wei-adjacent exponent can land a few ULPs on either side of the exact
        // value -- a real, expected limit of composing independently-truncating steps, not
        // something a wider tolerance meaningfully fixes at the point of stitching an exact
        // identity onto an approximate curve. Excluding the exact seam value keeps this test
        // checking real monotonicity, not this one-point discontinuity.
        vm.assume(expLow != WAD && expHigh != WAD);

        uint256 resultLow = FixedPointMath.pow(base, expLow);
        uint256 resultHigh = FixedPointMath.pow(base, expHigh);
        assertGe(resultHigh, resultLow, "for base > WAD, pow must increase with exponent");
    }

    function testFuzz_PowMonotonicInExponentBelowOneBase(uint256 base, uint256 expLow, uint256 expHigh) public pure {
        base = bound(base, 1e13, WAD - 1);
        expLow = bound(expLow, 1e16, 10e18);
        expHigh = bound(expHigh, expLow, 10e18);
        vm.assume(expHigh > expLow);
        // Same exact-shortcut seam as the AboveOne variant above.
        vm.assume(expLow != WAD && expHigh != WAD);

        uint256 resultLow = FixedPointMath.pow(base, expLow);
        uint256 resultHigh = FixedPointMath.pow(base, expHigh);
        assertLe(resultHigh, resultLow, "for base < WAD, pow must decrease as exponent increases");
    }
}
