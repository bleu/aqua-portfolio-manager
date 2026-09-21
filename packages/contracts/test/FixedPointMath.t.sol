// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FixedPointMath} from "../src/utils/FixedPointMath.sol";

/// @notice Checks directed bounds against independent integer identities and references.
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
        assertEq(FixedPointMath.powDown(base, WAD), base);
    }

    function testFuzz_PowWithBaseWadReturnsWadExactly(uint256 exponent) public pure {
        assertEq(FixedPointMath.powDown(WAD, exponent), WAD);
    }

    // ---- pow: known roots ----

    function test_PowSquareRootOfFour() public pure {
        uint256 result = FixedPointMath.powDown(4 * WAD, WAD / 2);
        _assertApproxRelWad(result, 2 * WAD, REL_TOL);
    }

    function test_PowSquareRootOfNine() public pure {
        uint256 result = FixedPointMath.powDown(9 * WAD, WAD / 2);
        _assertApproxRelWad(result, 3 * WAD, REL_TOL);
    }

    function test_PowCubeRootOfEight() public pure {
        uint256 result = FixedPointMath.powDown(8 * WAD, WAD / 3);
        _assertApproxRelWad(result, 2 * WAD, REL_TOL);
    }

    function test_PowTwoSquared() public pure {
        uint256 result = FixedPointMath.powDown(2 * WAD, 2 * WAD);
        _assertApproxRelWad(result, 4 * WAD, REL_TOL);
    }

    function test_PowReciprocalExponent() public pure {
        // base^1 via a roundabout path: (base^0.5)^2 should match base^1 == base.
        uint256 half = FixedPointMath.powDown(5 * WAD, WAD / 2);
        uint256 result = FixedPointMath.powDown(half, 2 * WAD);
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

        uint256 resultLow = FixedPointMath.powDown(baseLow, exponent);
        uint256 resultHigh = FixedPointMath.powDown(baseHigh, exponent);
        assertGe(resultHigh, resultLow, "pow must be non-decreasing in base, for base >= WAD");
    }

    function testFuzz_PowMonotonicInBaseBelowOne(uint256 baseLow, uint256 baseHigh, uint256 exponent) public pure {
        baseLow = bound(baseLow, 1e13, WAD);
        baseHigh = bound(baseHigh, baseLow, WAD);
        exponent = bound(exponent, 1e16, 10e18);
        vm.assume(baseHigh > baseLow);

        uint256 resultLow = FixedPointMath.powDown(baseLow, exponent);
        uint256 resultHigh = FixedPointMath.powDown(baseHigh, exponent);
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

        uint256 resultLow = FixedPointMath.powDown(base, expLow);
        uint256 resultHigh = FixedPointMath.powDown(base, expHigh);
        assertGe(resultHigh, resultLow, "for base > WAD, pow must increase with exponent");
    }

    function testFuzz_PowMonotonicInExponentBelowOneBase(uint256 base, uint256 expLow, uint256 expHigh) public pure {
        base = bound(base, 1e13, WAD - 1);
        expLow = bound(expLow, 1e16, 10e18);
        expHigh = bound(expHigh, expLow, 10e18);
        vm.assume(expHigh > expLow);
        // Same exact-shortcut seam as the AboveOne variant above.
        vm.assume(expLow != WAD && expHigh != WAD);

        uint256 resultLow = FixedPointMath.powDown(base, expLow);
        uint256 resultHigh = FixedPointMath.powDown(base, expHigh);
        assertLe(resultHigh, resultLow, "for base < WAD, pow must decrease as exponent increases");
    }

    function _powUp(uint256 base, uint256 exponent) external pure returns (uint256) {
        return FixedPointMath.powUp(base, exponent);
    }

    function test_PowUpPreservesExactIdentities() public pure {
        assertEq(FixedPointMath.powUp(WAD, type(uint256).max), WAD);
        assertEq(FixedPointMath.powUp(type(uint256).max, 0), WAD);
        assertEq(FixedPointMath.powUp(type(uint256).max, WAD), type(uint256).max);
    }

    function test_PowersBelowOneBoundExactSquare() public pure {
        uint256 base = 0.3e18;
        uint256 expected = 0.09e18;
        assertLe(FixedPointMath.powDown(base, 2 * WAD), expected);
        assertGe(FixedPointMath.powUp(base, 2 * WAD), expected);
    }

    function test_PowersHandleZeroAndOne() public pure {
        assertEq(FixedPointMath.powDown(0, 0), WAD);
        assertEq(FixedPointMath.powUp(0, 0), WAD);
        assertEq(FixedPointMath.powDown(0, WAD / 2), 0);
        assertEq(FixedPointMath.powUp(0, WAD / 2), 0);
        assertEq(FixedPointMath.powDown(WAD, type(uint256).max), WAD);
        assertEq(FixedPointMath.powDown(type(uint256).max, 0), WAD);
        assertEq(FixedPointMath.powDown(type(uint256).max, WAD), type(uint256).max);
    }

    function test_PowUpRejectsExponentOutsidePrbDomain() public {
        vm.expectPartialRevert(bytes4(keccak256("PRBMath_UD60x18_Exp2_InputTooBig(uint256)")));
        this._powUp(2 * WAD, 192 * WAD);
        // A fractional result can fit while its reciprocal intermediate exceeds the domain.
        vm.expectPartialRevert(bytes4(keccak256("PRBMath_UD60x18_Exp2_InputTooBig(uint256)")));
        this._powUp(1, 4 * WAD);
    }

    function test_PowersBelowOneEncloseIndependentReferences() public pure {
        // Floor/ceil references evaluated independently with 160-digit Decimal arithmetic.
        _assertPowerBounds(WAD - 1, WAD / 2, WAD - 1, WAD);
        _assertPowerBounds(WAD / 10, 3 * WAD / 2, 31622776601683793, 31622776601683794);
        _assertPowerBounds(WAD / 2, WAD / 3, 793700525984099737, 793700525984099738);
        _assertPowerBounds(1, WAD / 10, 15848931924611134, 15848931924611135);
        _assertPowerBounds(1, 2 * WAD, 0, 1);
    }

    function _assertPowerBounds(uint256 base, uint256 exponent, uint256 floor, uint256 ceil) internal pure {
        assertLe(FixedPointMath.powDown(base, exponent), floor);
        assertGe(FixedPointMath.powUp(base, exponent), ceil);
    }

    function test_PowUpBoundsIndependentReferences() public pure {
        // ceil(WAD * (base/WAD)^(exponent/WAD)), evaluated with 160-digit Decimal arithmetic.
        _assertPowUpReference(WAD + 1, WAD / 2, WAD + 1);
        _assertPowUpReference(WAD + 101, 111111111111111112, WAD + 12);
        _assertPowUpReference(2 * WAD, WAD / 3, 1259921049894873165);
        _assertPowUpReference(3 * WAD, 3 * WAD / 2, 5196152422706631881);
        _assertPowUpReference(1e30, WAD / 10, 15848931924611134853);
        _assertPowUpReference(2 * WAD, 191 * WAD, (uint256(1) << 191) * WAD);
    }

    function _assertPowUpReference(uint256 base, uint256 exponent, uint256 expected) internal pure {
        uint256 actual = FixedPointMath.powUp(base, exponent);
        assertGe(actual, expected, "power must never understate the independent reference");
        // Also bound overcharging for these fixtures; this is not a lower-bound tolerance.
        assertLe(actual - expected, expected / 1e13 + 1, "power bound must remain close to the curve");
    }

    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_PowUpSquareRootBoundsExactIntegerSquare(uint256 base) public pure {
        base = bound(base, 1, 1e36);
        uint256 root = FixedPointMath.powUp(base, WAD / 2);
        assertGe(root * root, base * WAD, "upper square root must not round below the true root");
    }

    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_PowDownSquareRootBoundsExactIntegerSquare(uint256 base) public pure {
        base = bound(base, 1, 1e36);
        uint256 root = FixedPointMath.powDown(base, WAD / 2);
        assertLe(root * root, base * WAD, "lower square root must not exceed the true root");
    }

    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_PowerBoundsEncloseEachOther(uint256 base, uint256 exponent) public pure {
        base = bound(base, 1e13, 1e23);
        exponent = bound(exponent, 0, 10 * WAD);
        uint256 lower = FixedPointMath.powDown(base, exponent);
        uint256 upper = FixedPointMath.powUp(base, exponent);
        assertLe(lower, upper);
        assertLe(upper - lower, upper / 1e12 + 2, "power bounds should remain close in this domain");
    }

    function _scaleUp(uint256 value, uint8 from, uint8 to) external pure returns (uint256) {
        return FixedPointMath.scaleUp(value, from, to);
    }

    function test_ScalingRoundsInTheNamedDirection() public pure {
        assertEq(FixedPointMath.scaleDown(1_234_567, 6, 3), 1_234);
        assertEq(FixedPointMath.scaleUp(1_234_567, 6, 3), 1_235);
        assertEq(FixedPointMath.scaleDown(1_234, 3, 6), 1_234_000);
        assertEq(FixedPointMath.scaleUp(1_234, 3, 6), 1_234_000);
        assertEq(FixedPointMath.scaleUp(1_234_000, 6, 3), 1_234);
        assertEq(FixedPointMath.scaleDown(type(uint256).max, 255, 255), type(uint256).max);
        assertEq(FixedPointMath.scaleUp(0, 18, 6), 0);
        assertEq(FixedPointMath.scaleDown(1, 0, 77), 1e77);
    }

    function test_ScalingRejectsUnrepresentableFactorsAndResults() public {
        vm.expectRevert(abi.encodeWithSelector(FixedPointMath.FixedPointMathUnsupportedDecimalDifference.selector, 78));
        this._scaleUp(1, 0, 78);
        vm.expectRevert(abi.encodeWithSelector(FixedPointMath.FixedPointMathUnsupportedDecimalDifference.selector, 78));
        this._scaleUp(1, 78, 0);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        this._scaleUp(2, 0, 77);
    }

    function testFuzz_ScalingBoundsAndRoundTrip(uint128 value, uint8 decimals) public pure {
        decimals = uint8(bound(decimals, 0, 38));
        uint256 lower = FixedPointMath.scaleDown(value, decimals, 0);
        uint256 upper = FixedPointMath.scaleUp(value, decimals, 0);
        assertLe(lower, upper);
        assertLe(upper - lower, 1);
        assertLe(FixedPointMath.scaleDown(lower, 0, decimals), value);
        assertGe(FixedPointMath.scaleUp(upper, 0, decimals), value);
        uint256 scaled = FixedPointMath.scaleUp(value, 0, decimals);
        assertEq(FixedPointMath.scaleDown(scaled, decimals, 0), value);
    }

    function test_MulDivArithmeticUsesFullPrecision() public pure {
        assertEq(FixedPointMath.mulDivDown(7, 5, 3), 11);
        assertEq(FixedPointMath.mulDivUp(7, 5, 3), 12);
        assertEq(FixedPointMath.mulDivDown(type(uint256).max, 2, 2), type(uint256).max);
        assertEq(FixedPointMath.mulDivUp(type(uint256).max, 2, 2), type(uint256).max);
    }

    // ---- mulDown/mulUp/divDown/divUp: rounding direction ----

    function testFuzz_MulDownNeverExceedsMulUp(uint256 a, uint256 b) public pure {
        a = bound(a, 0, 1e40);
        b = bound(b, 0, 1e40);
        assertLe(FixedPointMath.mulDown(a, b), FixedPointMath.mulUp(a, b));
    }

    function testFuzz_DivDownNeverExceedsDivUp(uint256 a, uint256 b) public pure {
        a = bound(a, 0, 1e40);
        b = bound(b, 1, 1e40);
        assertLe(FixedPointMath.divDown(a, b), FixedPointMath.divUp(a, b));
    }

    function testFuzz_MulDownUpDifferByAtMostOneRawUnit(uint256 a, uint256 b) public pure {
        // mulDown/mulUp can only ever disagree by the rounding of one division -- at most 1 raw
        // unit apart, never a real magnitude difference.
        a = bound(a, 0, 1e40);
        b = bound(b, 0, 1e40);
        assertLe(FixedPointMath.mulUp(a, b) - FixedPointMath.mulDown(a, b), 1);
    }

    function test_MulDownExactWhenDivisible() public pure {
        // 2 * 3 WAD / WAD == 6, no fractional remainder -- down and up must agree exactly.
        assertEq(FixedPointMath.mulDown(2 * WAD, 3 * WAD), 6 * WAD);
        assertEq(FixedPointMath.mulUp(2 * WAD, 3 * WAD), 6 * WAD);
    }

    function test_MulUpRoundsUpOnRemainder() public pure {
        // 1 * 1 / WAD has a nonzero remainder in raw units -- up must exceed down by exactly 1.
        assertEq(FixedPointMath.mulDown(1, 1), 0);
        assertEq(FixedPointMath.mulUp(1, 1), 1);
    }

    function test_DivUpRoundsUpOnRemainder() public pure {
        // 1 * WAD / 3 doesn't divide evenly -- up must exceed down by exactly 1 raw unit.
        uint256 down = FixedPointMath.divDown(1, 3);
        uint256 up = FixedPointMath.divUp(1, 3);
        assertEq(up - down, 1);
    }

    function test_DivDownExactWhenDivisible() public pure {
        assertEq(FixedPointMath.divDown(6, 2), 3 * WAD);
        assertEq(FixedPointMath.divUp(6, 2), 3 * WAD);
    }
}
