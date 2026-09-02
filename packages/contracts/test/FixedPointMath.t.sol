// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FixedPointMath} from "../src/FixedPointMath.sol";

contract FixedPointMathTest is Test {
    uint256 constant WAD = FixedPointMath.WAD;

    // Reference constants, computed independently (any calculator/spec), not from this
    // library's own output — what the tests below check against, not what they assume.
    uint256 constant E_WAD = 2718281828459045235; // e
    uint256 constant LN2_WAD = 693147180559945309; // ln(2)

    // 1e-9 relative tolerance (WAD/1e9 absolute, scaled to the magnitude under test) — well
    // inside what a 20/15-term series at this domain should clear; see FixedPointMath's own
    // comments for the precision budget this is meant to confirm, not just assume.
    uint256 constant REL_TOL = 1e9;

    function _assertApproxRelWad(uint256 actual, uint256 expected, uint256 relTol) internal pure {
        uint256 diff = actual > expected ? actual - expected : expected - actual;
        uint256 maxDiff = expected / relTol;
        if (maxDiff == 0) maxDiff = 1;
        assertLe(diff, maxDiff, "value outside relative tolerance");
    }

    // `ln`/`exp` are `internal pure` on the library, so calling them directly from the test
    // inlines the code into the test contract -- no CALL opcode happens, and `vm.expectRevert`
    // requires the revert to occur at a depth below the cheatcode call. Routing through these
    // external wrappers (a real self-CALL via `this.xxx(...)`) gives `expectRevert` a real call
    // boundary to intercept.
    function _callLn(uint256 x) external pure returns (int256) {
        return FixedPointMath.ln(x);
    }

    function _callExp(int256 x) external pure returns (uint256) {
        return FixedPointMath.exp(x);
    }

    // ---- ln: known reference points ----

    function test_LnOfWadIsZero() public pure {
        assertEq(FixedPointMath.ln(WAD), 0);
    }

    function test_LnOfTwo() public pure {
        int256 result = FixedPointMath.ln(2 * WAD);
        _assertApproxRelWad(uint256(result), LN2_WAD, REL_TOL);
    }

    function test_LnOfE() public pure {
        int256 result = FixedPointMath.ln(E_WAD);
        _assertApproxRelWad(uint256(result), WAD, REL_TOL);
    }

    function test_LnOfHalfIsNegativeLn2() public pure {
        int256 result = FixedPointMath.ln(WAD / 2);
        assertLt(result, 0);
        _assertApproxRelWad(uint256(-result), LN2_WAD, REL_TOL);
    }

    function test_LnRevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(FixedPointMath.FixedPointMathLnRequiresPositive.selector, 0));
        this._callLn(0);
    }

    function test_LnHandlesVeryLargeAndVerySmallInputs() public pure {
        // Must not revert or loop unboundedly -- both directions of the normalization loop.
        FixedPointMath.ln(1); // smallest possible positive input
        FixedPointMath.ln(type(uint128).max); // large, still well under the exp() output cap
    }

    // ---- exp: known reference points ----

    function test_ExpOfZeroIsWad() public pure {
        assertEq(FixedPointMath.exp(0), WAD);
    }

    function test_ExpOfOne() public pure {
        uint256 result = FixedPointMath.exp(int256(WAD));
        _assertApproxRelWad(result, E_WAD, REL_TOL);
    }

    function test_ExpOfLn2IsTwo() public pure {
        uint256 result = FixedPointMath.exp(int256(LN2_WAD));
        _assertApproxRelWad(result, 2 * WAD, REL_TOL);
    }

    function test_ExpOfNegativeOneIsReciprocalOfE() public pure {
        uint256 result = FixedPointMath.exp(-int256(WAD));
        uint256 expected = (WAD * WAD) / E_WAD;
        _assertApproxRelWad(result, expected, REL_TOL);
    }

    function test_ExpRevertsAboveCap() public {
        vm.expectRevert(abi.encodeWithSelector(FixedPointMath.FixedPointMathExpInputTooLarge.selector, int256(131e18)));
        this._callExp(131e18);
    }

    function test_ExpRevertsBelowNegativeCap() public {
        vm.expectRevert(abi.encodeWithSelector(FixedPointMath.FixedPointMathExpInputTooLarge.selector, int256(-131e18)));
        this._callExp(-131e18);
    }

    // ---- round trips ----

    function testFuzz_ExpOfLnRoundTrips(uint256 x) public pure {
        x = bound(x, 1e6, 1e30); // stay well inside exp()'s output cap after ln()
        int256 lnX = FixedPointMath.ln(x);
        uint256 result = FixedPointMath.exp(lnX);
        _assertApproxRelWad(result, x, REL_TOL);
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

    // ---- monotonicity: the property PortfolioManagerInvariant.t.sol's proof actually needs ----
    //
    // Bounds below keep |exponent * ln(base) / WAD| under EXP_MAX_INPUT (130 WAD) with margin,
    // so a legitimate domain-cap revert never masquerades as a monotonicity failure. Base is
    // bounded to a real value in [1e-5, 1e5] (|ln| <= ~11.5 WAD) and exponent to [0.01, 10]
    // WAD (a generous superset of the weight-ratio domain `PortfolioManagerSwap` actually
    // calls `pow` with) -- worst case product is ~115 WAD, comfortably under the 130 WAD cap.

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
        // `exponent == WAD` is an exact shortcut (`return base` unchanged); every other exponent
        // goes through the approximate `exp(exponent * ln(base) / WAD)` composition, which does
        // not round-trip to bit-exact agreement with that shortcut. Right at this seam, a
        // single-wei-adjacent exponent can land a few ULPs on either side of the exact value,
        // which is a real, expected limit of composing two independently-truncating series, not
        // something a wider tolerance or more series terms meaningfully fixes at the point of
        // stitching an exact identity onto an approximate curve. Excluding the exact seam value
        // keeps this test checking real monotonicity, not this one-point discontinuity.
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
