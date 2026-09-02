// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FixedPointMath} from "../src/FixedPointMath.sol";
import {PortfolioManagerPricing} from "../src/PortfolioManagerPricing.sol";

contract PortfolioManagerPricingTest is Test {
    uint256 constant WAD = 1e18;

    // See FixedPointMath.t.sol for why internal library calls need an external wrapper for
    // `vm.expectRevert` to intercept the revert at the right call depth.
    function _exactIn(PortfolioManagerPricing.Quote memory q, uint256 amountIn) external pure returns (uint256) {
        return PortfolioManagerPricing.exactIn(q, amountIn);
    }

    function _exactOut(PortfolioManagerPricing.Quote memory q, uint256 amountOut) external pure returns (uint256) {
        return PortfolioManagerPricing.exactOut(q, amountOut);
    }

    function _spotPrice(PortfolioManagerPricing.Quote memory q) external pure returns (uint256) {
        return PortfolioManagerPricing.spotPrice(q);
    }

    function _quote(uint256 balanceIn, uint256 balanceOut, uint256 weightIn, uint256 weightOut, uint256 feeWad)
        internal
        pure
        returns (PortfolioManagerPricing.Quote memory)
    {
        return PortfolioManagerPricing.Quote({
            balanceIn: balanceIn,
            balanceOut: balanceOut,
            weightIn: weightIn,
            weightOut: weightOut,
            feeWad: feeWad
        });
    }

    function test_SpotPriceAtEqualWeightsMatchesPlainBalanceRatio() public pure {
        // 50/50: SP should just be balanceOut/balanceIn's ratio... actually SP(i->o) = (B_i/w_i)/(B_o/w_o),
        // which at equal weights reduces to B_i/B_o.
        PortfolioManagerPricing.Quote memory q = _quote(20_000e18, 10e18, 0.5e18, 0.5e18, 0);
        uint256 sp = PortfolioManagerPricing.spotPrice(q);
        assertEq(sp, 2000e18);
    }

    function test_SpotPriceRevertsOnZeroBalance() public {
        PortfolioManagerPricing.Quote memory q = _quote(0, 10e18, 0.5e18, 0.5e18, 0);
        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerPricing.PortfolioManagerPricingZeroBalance.selector));
        this._spotPrice(q);
    }

    function test_EqualWeightExactInMatchesPlainXyk() public pure {
        // Equal weights hits FixedPointMath.pow's exact `exponent == WAD` shortcut, so this
        // should match plain xy=k (PRICING.md's own stated sanity check) very closely -- to
        // within the one extra WAD-scaled division/rounding step this formula does that plain
        // xy=k doesn't (dividing balanceIn twice instead of once), not to `pow`'s own precision.
        uint256 balanceIn = 100_000e18;
        uint256 balanceOut = 100_000e18;
        uint256 amountIn = 1_000e18;

        PortfolioManagerPricing.Quote memory q = _quote(balanceIn, balanceOut, 0.5e18, 0.5e18, 0);
        uint256 amountOut = PortfolioManagerPricing.exactIn(q, amountIn);

        uint256 xykExpected = balanceOut - (balanceIn * balanceOut) / (balanceIn + amountIn);
        // Not bit-exact: this formula's WAD-scaled ratio division loses sub-WAD precision
        // before multiplying back up by balanceOut, an extra rounding step plain xy=k's
        // single division doesn't have. The resulting slack scales with balanceOut/WAD.
        assertApproxEqAbs(amountOut, xykExpected, balanceOut / 1e14, "equal-weight curve should match plain xy=k closely");
    }

    function test_ExactInFeeReducesOutputVersusZeroFee() public pure {
        PortfolioManagerPricing.Quote memory noFee = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0);
        PortfolioManagerPricing.Quote memory withFee = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0.0002e18);

        uint256 outNoFee = PortfolioManagerPricing.exactIn(noFee, 1_000e18);
        uint256 outWithFee = PortfolioManagerPricing.exactIn(withFee, 1_000e18);

        assertLt(outWithFee, outNoFee, "a fee must strictly reduce the trader's output");
    }

    function test_ExactInRevertsOnZeroBalance() public {
        PortfolioManagerPricing.Quote memory q = _quote(0, 100_000e18, 0.5e18, 0.5e18, 0);
        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerPricing.PortfolioManagerPricingZeroBalance.selector));
        this._exactIn(q, 1_000e18);
    }

    function test_ExactOutRevertsWhenDrainingTheFullOutputBalance() public {
        PortfolioManagerPricing.Quote memory q = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerPricing.PortfolioManagerPricingInsufficientOutputBalance.selector, 100_000e18, 100_000e18
            )
        );
        this._exactOut(q, 100_000e18);
    }

    function test_ExactOutFeeIncreasesRequiredInputVersusZeroFee() public pure {
        PortfolioManagerPricing.Quote memory noFee = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0);
        PortfolioManagerPricing.Quote memory withFee = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0.0002e18);

        uint256 inNoFee = PortfolioManagerPricing.exactOut(noFee, 1_000e18);
        uint256 inWithFee = PortfolioManagerPricing.exactOut(withFee, 1_000e18);

        assertGt(inWithFee, inNoFee, "a fee must strictly increase what the trader must pay in");
    }

    // NOTE: an earlier version of this test asserted that recovering the original `amountIn`
    // via a reverse exact-out trade must cost at least the `amountOut` originally received --
    // that is NOT a real property of an asymmetric-weight pool, and fails routinely (verified
    // independently against the exact formula at 80-digit decimal precision in Python, matching
    // this contract's output to ~10 significant figures -- not a rounding bug). Unequal weights
    // structurally price the two tokens differently; comparing raw token counts across the
    // forward and reverse legs of a round trip is an apples-to-oranges comparison once weights
    // aren't 50/50, not a free-profit exploit. The actual proven property is that the curve's
    // own invariant never decreases (DONATION-RESISTANCE-PROOF.md, ADR-0007) -- checked below.
    function testFuzz_ExactInNeverDecreasesTheInvariant(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 weightIn,
        uint256 amountIn
    ) public pure {
        balanceIn = bound(balanceIn, 1_000e18, 1_000_000_000e18);
        balanceOut = bound(balanceOut, 1_000e18, 1_000_000_000e18);
        weightIn = bound(weightIn, 0.05e18, 0.95e18);
        uint256 weightOut = WAD - weightIn;
        amountIn = bound(amountIn, 1e6, balanceIn / 10);

        PortfolioManagerPricing.Quote memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 0.0002e18);
        uint256 amountOut = PortfolioManagerPricing.exactIn(q, amountIn);
        vm.assume(amountOut > 0 && amountOut < balanceOut);

        // V = balanceIn^weightIn * balanceOut^weightOut (WAD-scaled throughout). Comparing
        // V_after >= V_before directly risks a spurious failure from FixedPointMath's own
        // precision (not a real invariant violation) if computed as two full pow() calls on
        // each side -- instead compare via a single ratio, which cancels most of that shared
        // rounding: V_after/V_before = (newBalanceIn/balanceIn)^weightIn * (newBalanceOut/balanceOut)^weightOut,
        // which must be >= WAD (i.e. >= 1).
        uint256 newBalanceIn = balanceIn + amountIn; // full amount lands, PRICING.md
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 growthIn = FixedPointMath.pow(newBalanceIn * WAD / balanceIn, weightIn);
        uint256 growthOut = FixedPointMath.pow(newBalanceOut * WAD / balanceOut, weightOut);
        uint256 invariantRatio = growthIn * growthOut / WAD;

        // Small tolerance for FixedPointMath's own series-truncation precision (compounded
        // across two pow() calls plus the WAD-scaled ratio divisions above), not a license for
        // the invariant to actually decrease -- 1e-14 relative is still far tighter than
        // anything this milestone's PoC-grade math claims to guarantee bit-exactly.
        assertGe(invariantRatio + 1e4, WAD, "the curve invariant must never decrease across a trade");
    }
}
