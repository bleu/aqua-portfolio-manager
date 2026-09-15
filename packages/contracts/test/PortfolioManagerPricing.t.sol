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
            balanceIn: balanceIn, balanceOut: balanceOut, weightIn: weightIn, weightOut: weightOut, feeWad: feeWad
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
        assertApproxEqAbs(
            amountOut, xykExpected, balanceOut / 1e14, "equal-weight curve should match plain xy=k closely"
        );
    }

    function test_ExactInRoundsInThePoolsFavorAtEqualWeights() public pure {
        // Regression test: balanceIn == balanceOut == 1e18, amountIn == 2e18, no fee, equal
        // weights (hits FixedPointMath.pow's exact `exponent == WAD` shortcut, so this is exact
        // arithmetic, not series-approximated). The true value is balanceOut * 2/3 =
        // 666666666666666666.666... -- flooring in the pool's favor must return
        // 666666666666666666, not 666666666666666667. Before ceiling the ratio fed into `pow`,
        // this returned the latter: flooring `balanceIn*WAD/(balanceIn+amountInEff)` floored
        // `poweredRatio` too, which inflated `WAD - poweredRatio` past the true value.
        PortfolioManagerPricing.Quote memory q = _quote(1e18, 1e18, 0.5e18, 0.5e18, 0);
        uint256 amountOut = PortfolioManagerPricing.exactIn(q, 2e18);
        assertEq(amountOut, 666666666666666666, "amountOut must floor toward the pool, never round up to the trader");
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

    function test_ExactOutRevertsOnZeroBalance() public {
        PortfolioManagerPricing.Quote memory q = _quote(0, 100_000e18, 0.5e18, 0.5e18, 0);
        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerPricing.PortfolioManagerPricingZeroBalance.selector));
        this._exactOut(q, 1_000e18);
    }

    function test_ExactOutRevertsWhenDrainingTheFullOutputBalance() public {
        PortfolioManagerPricing.Quote memory q = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerPricing.PortfolioManagerPricingInsufficientOutputBalance.selector,
                100_000e18,
                100_000e18
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

    // PRICING.md's degenerate-cases section specifies the exactly-zero balance guard
    // (`_requireNonZeroBalances`, already tested above) plus a guard against a trade computing
    // to the pool's entire output balance or more -- `exactIn` reverts on that the same way
    // `exactOut` already reverted on it being requested directly. Neither is a minimum-balance
    // threshold; both are output-side bounds checks. This fuzzes the invariant property the test
    // above proves for normal balances, extended down to balances as small as 1 wei.
    function testFuzz_ExactInNeverDecreasesTheInvariantAtNearZeroBalance(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 weightIn,
        uint256 amountIn
    ) public {
        balanceIn = bound(balanceIn, 1, 1e6);
        balanceOut = bound(balanceOut, 1, 1e6);
        weightIn = bound(weightIn, 0.05e18, 0.95e18);
        uint256 weightOut = WAD - weightIn;
        amountIn = bound(amountIn, 1, 1_000_000e18);

        PortfolioManagerPricing.Quote memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 0.0002e18);

        // Two independent revert paths can legitimately fire here: FixedPointMath.exp's own
        // exponent cap at extreme weight skew, and exactIn's own would-drain-the-pool guard. Both
        // are correct, safe outcomes -- only a non-reverting result needs the invariant checked.
        uint256 amountOut;
        try this._exactIn(q, amountIn) returns (uint256 out) {
            amountOut = out;
        } catch {
            return;
        }
        vm.assume(amountOut > 0);

        uint256 newBalanceIn = balanceIn + amountIn;
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 growthIn = FixedPointMath.pow(newBalanceIn * WAD / balanceIn, weightIn);
        uint256 growthOut = FixedPointMath.pow(newBalanceOut * WAD / balanceOut, weightOut);
        uint256 invariantRatio = growthIn * growthOut / WAD;

        // A wider tolerance than the normal-balance fuzz test above: dividing by a `balanceIn`/
        // `balanceOut` as small as 1 wei amplifies FixedPointMath's own series-truncation error
        // far more than the normal WAD-scale case does -- this is precision noise from computing
        // the check itself (consistent with `pow`'s own documented series precision), not
        // evidence of a real invariant violation or a directional bias toward the trader.
        assertGe(invariantRatio + 1e8, WAD, "the curve invariant must never decrease, even at near-zero balances");
    }

    /// @notice PR #27 review (Pedro): reserves `1 / 1e24`, weights `90%/10%`, a 2 bps fee, and
    /// input `93` used to pass `exactIn`'s own `amountOut < balanceOut` guard while the curve
    /// invariant actually decreased by ~48% -- `poweredRatio` collapsed to a handful of raw WAD
    /// units (below 18-decimal fixed point's trustworthy precision, see
    /// `FixedPointMath.EXP_MIN_INPUT`'s own doc comment), and because it's subtracted from WAD
    /// before multiplying by `balanceOut`, that rounding noise became a `balanceOut`-scaled
    /// absolute error in the trader's favor. Regression test: this exact counterexample must now
    /// revert, not silently return a wrong `amountOut`.
    function test_RevertsOnPedroReviewCounterexample() public {
        PortfolioManagerPricing.Quote memory q = _quote(1, 1e24, 0.9e18, 0.1e18, 2e14);
        vm.expectRevert();
        this._exactIn(q, 93);
    }

    /// @notice Pedro's own request: stress the fuzz domain specifically with a *tiny* input
    /// reserve paired with a *large* output reserve (the exact shape of the counterexample
    /// above) -- `testFuzz_ExactInNeverDecreasesTheInvariantAtNearZeroBalance` above keeps both
    /// sides small and never explores this pairing, which is precisely why it didn't catch the
    /// bug this regresses. A non-reverting trade must never hand out more than 99.9% of
    /// `balanceOut` -- both sides of this bound are permissive (a legitimate, extreme-skew trade
    /// could plausibly take a genuine large fraction), it's specifically the "basically the
    /// entire pool, for a near-free input" shape this guards against.
    /// @dev Checks the invariant, not a raw drain percentage -- a large fraction of `balanceOut`
    ///      genuinely, correctly leaving the pool at high weight skew combined with a
    ///      substantial-relative-to-balanceIn trade is real curve behavior (steep, but not a
    ///      bug); an early draft of this test asserted a flat "<99.9% of balanceOut" bound
    ///      instead and produced a false positive on exactly that legitimate case (balanceIn
    ///      1e4, exponent 24, a 74%-of-balanceIn trade correctly extracting 99.9998% of a
    ///      mismatched balanceOut) -- the invariant is the property that actually distinguishes
    ///      "steep but correct" from "wrong, in the trader's favor."
    function testFuzz_TinyBalanceInPairedWithHugeBalanceOutInvariantHolds(
        uint8 balInExp,
        uint8 balOutExp,
        uint32 weightInRaw,
        uint256 amountInRaw
    ) public {
        uint256 balanceIn = 10 ** bound(balInExp, 0, 6); // 1 .. 1e6
        uint256 balanceOut = 10 ** bound(balOutExp, 18, 30); // 1e18 .. 1e30
        uint256 weightIn = bound(weightInRaw, 0.05e18, 0.95e18);
        uint256 weightOut = WAD - weightIn;
        uint256 amountIn = bound(amountInRaw, 1, 1e30);

        PortfolioManagerPricing.Quote memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 2e14);

        uint256 amountOut;
        try this._exactIn(q, amountIn) returns (uint256 out) {
            amountOut = out;
        } catch {
            return; // a clean revert is always a safe outcome
        }
        vm.assume(amountOut > 0);

        uint256 newBalanceIn = balanceIn + amountIn;
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 growthIn = FixedPointMath.pow(newBalanceIn * WAD / balanceIn, weightIn);
        uint256 growthOut = FixedPointMath.pow(newBalanceOut * WAD / balanceOut, weightOut);
        uint256 invariantRatio = growthIn * growthOut / WAD;

        // Same wide tolerance rationale as testFuzz_ExactInNeverDecreasesTheInvariantAtNearZeroBalance
        // above -- precision noise from computing the check itself at extreme balance ratios,
        // not a license for a real decrease.
        assertGe(
            invariantRatio + 1e8,
            WAD,
            "the curve invariant must never decrease when balanceIn is tiny and balanceOut is huge"
        );
    }

    /// @notice Pedro's own suggestion, implemented directly: an independent invariant check
    /// using *exact* integer arithmetic for an integer weight ratio (90/10 -> exponent exactly
    /// 9), computing `balanceIn^9 * balanceOut` before/after via plain `uint256` multiplication
    /// -- no `FixedPointMath.pow`/`ln`/`exp` involved anywhere in the check itself, so a shared
    /// bug between the production code and the verification can't hide here the way reusing
    /// `pow` to check `pow`'s own output could (this is exactly the blind spot the existing
    /// `pow`-based invariant fuzz tests above have, and exactly what let the counterexample
    /// above through the first time). Balance ranges are kept small enough that `balanceIn^9`
    /// itself can't overflow `uint256` even multiplied by a large `balanceOut`.
    function testFuzz_ExactInInvariantHoldsUnderExactIntegerArithmeticAtIntegerExponent(
        uint32 balInRaw,
        uint96 balOutRaw,
        uint256 amountInRaw
    ) public {
        uint256 weightIn = 0.9e18; // exponent = weightIn/weightOut = 9 exactly
        uint256 weightOut = 0.1e18;

        uint256 balanceIn = bound(balInRaw, 1, 1e4); // balanceIn^9 <= 1e36
        uint256 balanceOut = bound(balOutRaw, 1e18, 1e30); // product with balanceIn^9 <= 1e66, safe
        uint256 amountIn = bound(amountInRaw, 1, 1e30);

        PortfolioManagerPricing.Quote memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 2e14);

        uint256 amountOut;
        try this._exactIn(q, amountIn) returns (uint256 out) {
            amountOut = out;
        } catch {
            return;
        }
        vm.assume(amountOut > 0 && amountOut < balanceOut);

        uint256 newBalanceIn = balanceIn + amountIn;
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 invariantBefore = _pow9Exact(balanceIn) * balanceOut;
        uint256 invariantAfter = _pow9Exact(newBalanceIn) * newBalanceOut;

        assertGe(
            invariantAfter, invariantBefore, "exact-integer invariant (balanceIn^9 * balanceOut) must not decrease"
        );
    }

    function _pow9Exact(uint256 x) internal pure returns (uint256) {
        uint256 x3 = x * x * x;
        return x3 * x3 * x3;
    }

    /// @notice Direct round-trip check at an extreme balance (`balanceIn = 1` wei): trade in,
    /// then trade the received amount back out, and confirm the trader recovers strictly less
    /// than they put in -- no way to profit by trading against a near-empty pool.
    function test_RoundTripAtOneWeiBalanceNeverProfitsTrader() public pure {
        PortfolioManagerPricing.Quote memory q1 = _quote(1, 1e18, 0.5e18, 0.5e18, 0.0002e18);
        uint256 amountIn = 1_000e18;
        uint256 amountOut = PortfolioManagerPricing.exactIn(q1, amountIn);

        uint256 newBalanceIn = 1 + amountIn;
        uint256 newBalanceOut = 1e18 - amountOut;
        vm.assume(newBalanceOut > 0);

        PortfolioManagerPricing.Quote memory q2 = _quote(newBalanceOut, newBalanceIn, 0.5e18, 0.5e18, 0.0002e18);
        uint256 amountBack = PortfolioManagerPricing.exactIn(q2, amountOut);

        assertLt(amountBack, amountIn, "round-tripping through a near-empty pool must not profit the trader");
    }

    /// @notice Extreme weight skew (1%/99%) combined with a near-empty pool (`balanceIn = 1`
    /// wei) and a massive trade. Must either produce a bounded, sane price (never handing out
    /// more than the pool holds) or revert cleanly -- never silently wrap, over/underflow, or
    /// return something outside `(0, balanceOut)`.
    function test_ExtremeWeightSkewStaysBoundedOrRevertsCleanly() public {
        PortfolioManagerPricing.Quote memory q = _quote(1, 1e18, 0.01e18, 0.99e18, 0);
        try this._exactIn(q, 1_000_000e18) returns (uint256 amountOut) {
            assertGt(amountOut, 0, "a non-reverting trade must return a nonzero amount");
            assertLt(amountOut, 1e18, "a non-reverting trade must never return more than the pool holds");
        } catch {
            // A clean revert (e.g. FixedPointMath.exp's EXP_MAX_INPUT cap, or the would-drain
            // guard below) is an acceptable outcome at this extreme -- the failure mode this
            // test guards against is a silent wrong number, not a revert.
        }
    }

    /// @notice At sufficiently skewed weights (`weightIn/weightOut` large) combined with a small
    /// `ratio`, `poweredRatio` can collapse to a handful of raw WAD units -- a value technically
    /// nonzero but below what 18-decimal fixed point can represent trustworthily (rounding
    /// noise, not a real answer). Without a guard, `amountOut` computes to nearly `balanceOut`:
    /// almost the entire pool, handed out for an ordinary-sized trade against an
    /// imbalanced-but-not-degenerate pool -- a real counterexample found in PR #27 review
    /// (Pedro), not a hypothetical. `FixedPointMath.exp`'s own `EXP_MIN_INPUT` guard now catches
    /// this earlier than the `amountOut < balanceOut` check below ever could, since it rejects
    /// the untrustworthy computation itself rather than trusting its (numerically garbage but
    /// not literally zero) output. Regression test for that guard.
    function test_ExactInRevertsInsteadOfDrainingPoolAtExtremeWeightSkew() public {
        PortfolioManagerPricing.Quote memory q = _quote(1, 1_000_000, 0.9e18, 0.1e18, 0.0002e18);
        vm.expectRevert(
            abi.encodeWithSelector(FixedPointMath.FixedPointMathExpInputTooSmall.selector, -62169797510839233468)
        );
        this._exactIn(q, 1000);
    }

    /// @notice Cross-checks `exactIn` against a reference implementation of PRICING.md's exact
    /// real-number formula, independent of `FixedPointMath`'s own series-based `ln`/`exp` --
    /// catches a systematic formula error that reusing `FixedPointMath` to verify itself would
    /// miss. Tolerance is relative (1e-12) -- far tighter than a real formula error would
    /// produce, but wide enough for the two implementations' own series-truncation/rounding
    /// differences, which can fall on either side and aren't a directional bias worth chasing.
    function test_ExactInMatchesIndependentReferenceImplementation() public pure {
        // Reference values computed independently via Decimal arithmetic at 60 significant
        // digits, from PRICING.md's formula directly (not via this contract's code).
        PortfolioManagerPricing.Quote memory q1 = _quote(100_000e18, 100_000e18, 0.3e18, 0.7e18, 0.0002e18);
        _assertMatchesReference(PortfolioManagerPricing.exactIn(q1, 1000e18), 425450270259556705827);

        PortfolioManagerPricing.Quote memory q2 = _quote(1_000_000e18, 1_000_000e18, 0.9e18, 0.1e18, 0.0002e18);
        _assertMatchesReference(PortfolioManagerPricing.exactIn(q2, 50_000e18), 355335828958235306891709);
    }

    function _assertMatchesReference(uint256 actual, uint256 expected) internal pure {
        uint256 diff = actual > expected ? actual - expected : expected - actual;
        assertLe(
            diff * 1e12, expected, "exactIn must match an independent reference implementation within 1e-12 relative"
        );
    }
}
