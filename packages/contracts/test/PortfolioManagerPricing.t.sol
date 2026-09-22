// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {FixedPointMath} from "../src/utils/FixedPointMath.sol";
import {PortfolioManagerPricing} from "../src/utils/PortfolioManagerPricing.sol";

contract PortfolioManagerPricingTest is Test {
    uint256 constant WAD = 1e18;

    // See FixedPointMath.t.sol for why internal library calls need an external wrapper for
    // `vm.expectRevert` to intercept the revert at the right call depth.
    function _exactIn(PortfolioManagerPricing.PoolState memory q, uint256 amountIn) external pure returns (uint256) {
        return PortfolioManagerPricing.exactIn(q, amountIn);
    }

    function _exactOut(PortfolioManagerPricing.PoolState memory q, uint256 amountOut) external pure returns (uint256) {
        return PortfolioManagerPricing.exactOut(q, amountOut);
    }

    function _spotPrice(PortfolioManagerPricing.PoolState memory q) external pure returns (uint256) {
        return PortfolioManagerPricing.spotPrice(q);
    }

    function _quote(uint256 balanceIn, uint256 balanceOut, uint256 weightIn, uint256 weightOut, uint256 feeWad)
        internal
        pure
        returns (PortfolioManagerPricing.PoolState memory)
    {
        return PortfolioManagerPricing.PoolState({
            balanceIn: balanceIn, balanceOut: balanceOut, weightIn: weightIn, weightOut: weightOut, feeWad: feeWad
        });
    }

    function test_SpotPriceAtEqualWeightsMatchesPlainBalanceRatio() public pure {
        // 50/50: SP should just be balanceOut/balanceIn's ratio... actually SP(i->o) = (B_i/w_i)/(B_o/w_o),
        // which at equal weights reduces to B_i/B_o.
        PortfolioManagerPricing.PoolState memory q = _quote(20_000e18, 10e18, 0.5e18, 0.5e18, 0);
        uint256 sp = PortfolioManagerPricing.spotPrice(q);
        assertEq(sp, 2000e18);
    }

    function test_SpotPriceRevertsOnZeroBalance() public {
        PortfolioManagerPricing.PoolState memory q = _quote(0, 10e18, 0.5e18, 0.5e18, 0);
        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerPricing.PortfolioManagerPricingZeroBalance.selector));
        this._spotPrice(q);
    }

    function test_EqualWeightExactInMatchesPlainXyk() public pure {
        // Equal weights use the exact exponent == WAD shortcut.
        uint256 balanceIn = 100_000e18;
        uint256 balanceOut = 100_000e18;
        uint256 amountIn = 1_000e18;

        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, 0.5e18, 0.5e18, 0);
        uint256 amountOut = PortfolioManagerPricing.exactIn(q, amountIn);

        uint256 xykExpected = balanceOut - (balanceIn * balanceOut) / (balanceIn + amountIn);
        // The extra WAD ratio division introduces rounding slack proportional to balanceOut/WAD.
        assertApproxEqAbs(
            amountOut, xykExpected, balanceOut / 1e14, "equal-weight curve should match plain xy=k closely"
        );
    }

    function test_ExactInRoundsInThePoolsFavorAtEqualWeights() public pure {
        // Regression: flooring the ratio previously paid one extra wei. Ceil it before subtracting its power from WAD.
        PortfolioManagerPricing.PoolState memory q = _quote(1e18, 1e18, 0.5e18, 0.5e18, 0);
        uint256 amountOut = PortfolioManagerPricing.exactIn(q, 2e18);
        assertEq(amountOut, 666666666666666666, "amountOut must floor toward the pool, never round up to the trader");
    }

    function test_ExactInFeeReducesOutputVersusZeroFee() public pure {
        PortfolioManagerPricing.PoolState memory noFee = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0);
        PortfolioManagerPricing.PoolState memory withFee = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0.0002e18);

        uint256 outNoFee = PortfolioManagerPricing.exactIn(noFee, 1_000e18);
        uint256 outWithFee = PortfolioManagerPricing.exactIn(withFee, 1_000e18);

        assertLt(outWithFee, outNoFee, "a fee must strictly reduce the trader's output");
    }

    function test_ExactInRevertsOnZeroBalance() public {
        PortfolioManagerPricing.PoolState memory q = _quote(0, 100_000e18, 0.5e18, 0.5e18, 0);
        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerPricing.PortfolioManagerPricingZeroBalance.selector));
        this._exactIn(q, 1_000e18);
    }

    function test_ExactOutRevertsOnZeroBalance() public {
        PortfolioManagerPricing.PoolState memory q = _quote(0, 100_000e18, 0.5e18, 0.5e18, 0);
        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerPricing.PortfolioManagerPricingZeroBalance.selector));
        this._exactOut(q, 1_000e18);
    }

    function test_ExactOutRevertsWhenDrainingTheFullOutputBalance() public {
        PortfolioManagerPricing.PoolState memory q = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0);
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
        PortfolioManagerPricing.PoolState memory noFee = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0);
        PortfolioManagerPricing.PoolState memory withFee = _quote(100_000e18, 100_000e18, 0.5e18, 0.5e18, 0.0002e18);

        uint256 inNoFee = PortfolioManagerPricing.exactOut(noFee, 1_000e18);
        uint256 inWithFee = PortfolioManagerPricing.exactOut(withFee, 1_000e18);

        assertGt(inWithFee, inNoFee, "a fee must strictly increase what the trader must pay in");
    }

    function test_ExactOutRoundsTinyTradeUpAtUnequalWeights() public pure {
        PortfolioManagerPricing.PoolState memory q = _quote(1e24, 1e24, 0.9e18, 0.1e18, 2e14);
        // Independently evaluated at 160-digit Decimal precision:
        // ceil(1e24 * ((1e24 / (1e24 - 1e8))^(1/9) - 1) / 0.9998).
        // Previously returned 10,002,001, below even the fee-free invariant minimum.
        assertGe(PortfolioManagerPricing.exactOut(q, 1e8), 11_113_334);
        // Even smaller positive output must not round to free input.
        assertGt(PortfolioManagerPricing.exactOut(q, 1e6), 0);
    }

    function test_ExactOutZeroOutputRequiresZeroInput() public pure {
        PortfolioManagerPricing.PoolState memory q = _quote(1e24, 1e24, 0.9e18, 0.1e18, 2e14);
        assertEq(PortfolioManagerPricing.exactOut(q, 0), 0);
    }

    function test_ExactOutRoundsWeightRatioUp() public pure {
        PortfolioManagerPricing.PoolState memory q = _quote(1e18, 1e50, 0.9e18, 0.1e18, 0);
        // ceil(1e18 * ((1e50)^(1/9) - 1)), independently evaluated at 160 digits.
        // A large base magnifies rounding the exponent 1/9 down.
        assertGe(PortfolioManagerPricing.exactOut(q, 1e50 - 1), 359380366380462730218817);
    }

    function test_ExactOutEqualWeightsKeepsExactRounding() public pure {
        PortfolioManagerPricing.PoolState memory q = _quote(1e18, 1e18, 0.5e18, 0.5e18, 0);
        assertEq(PortfolioManagerPricing.exactOut(q, 0.5e18), 1e18);
    }

    /// @dev Exact integer oracle, independent of production pow and without a tolerance.
    /// Pair weights need not sum to WAD: 60%/30% and 30%/60% give exact ratios 2 and 1/2.
    /// With output <= half the reserve, input is at most about 3 * balanceIn, so all
    /// degree-three invariant products remain below 5e72 and fit uint256.
    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_ExactOutPreservesExactIntegerInvariant(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountOut,
        bool largerInputWeight
    ) public pure {
        balanceIn = bound(balanceIn, 1, 1e24);
        balanceOut = bound(balanceOut, 2, 1e24);
        amountOut = bound(amountOut, 1, balanceOut / 2);
        uint256 weightIn = largerInputWeight ? 0.6e18 : 0.3e18;
        uint256 weightOut = largerInputWeight ? 0.3e18 : 0.6e18;
        // Zero fee prevents fees from hiding a rounding error.
        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 0);
        uint256 amountIn = PortfolioManagerPricing.exactOut(q, amountOut);
        uint256 afterIn = balanceIn + amountIn;
        uint256 afterOut = balanceOut - amountOut;
        uint256 beforeInvariant =
            largerInputWeight ? balanceIn * balanceIn * balanceOut : balanceIn * balanceOut * balanceOut;
        uint256 afterInvariant = largerInputWeight ? afterIn * afterIn * afterOut : afterIn * afterOut * afterOut;
        assertGe(afterInvariant, beforeInvariant, "exact-out must preserve the exact integer invariant");
    }

    /// @dev No fee or tolerance to hide an incorrect direction in the power bound.
    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_ExactInPreservesExactIntegerInvariantWithoutFee(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountIn,
        bool largerInputWeight
    ) public pure {
        balanceIn = bound(balanceIn, 2, 1e24);
        balanceOut = bound(balanceOut, 1, 1e24);
        amountIn = bound(amountIn, 1, balanceIn / 2);
        uint256 weightIn = largerInputWeight ? 0.6e18 : 0.3e18;
        uint256 weightOut = largerInputWeight ? 0.3e18 : 0.6e18;
        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 0);
        uint256 amountOut = PortfolioManagerPricing.exactIn(q, amountIn);
        assertLt(amountOut, balanceOut);
        uint256 afterIn = balanceIn + amountIn;
        uint256 afterOut = balanceOut - amountOut;
        // Degree-three products are below 2.25e72, so both fit uint256.
        uint256 beforeInvariant =
            largerInputWeight ? balanceIn * balanceIn * balanceOut : balanceIn * balanceOut * balanceOut;
        uint256 afterInvariant = largerInputWeight ? afterIn * afterIn * afterOut : afterIn * afterOut * afterOut;
        assertGe(afterInvariant, beforeInvariant, "exact-in must preserve the exact integer invariant without fees");
    }

    /// @dev Broad coverage with a conservative ratio oracle. The independent integer tests
    /// check selected weight ratios exactly without composing production power helpers.
    /// forge-config: default.fuzz.runs = 50000
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

        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 0.0002e18);
        uint256 amountOut = PortfolioManagerPricing.exactIn(q, amountIn);
        assertLt(amountOut, balanceOut, "exact-in must leave a nonzero output reserve");

        // Compare V_after/V_before to WAD to reduce shared power-rounding error:
        // (newBalanceIn/balanceIn)^weightIn * (newBalanceOut/balanceOut)^weightOut.
        uint256 newBalanceIn = balanceIn + amountIn; // full amount lands, PRICING.md
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 growthIn = FixedPointMath.powDown(newBalanceIn * WAD / balanceIn, weightIn);
        uint256 growthOut = FixedPointMath.powDown(newBalanceOut * WAD / balanceOut, weightOut);
        uint256 invariantRatio = growthIn * growthOut / WAD;

        // Allow 1e-14 relative error from the two approximate powers and ratio divisions.
        assertGe(invariantRatio + 1e4, WAD, "the curve invariant must never decrease across a trade");
    }

    /// @notice Check accepted exact-in quotes down to one-wei reserves.
    /// forge-config: default.fuzz.runs = 50000
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

        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 0.0002e18);

        // Power-domain and reserve-depletion reverts are valid. Check the invariant only for accepted quotes.
        uint256 amountOut;
        try this._exactIn(q, amountIn) returns (uint256 out) {
            amountOut = out;
        } catch {
            return;
        }
        vm.assume(amountOut > 0);

        uint256 newBalanceIn = balanceIn + amountIn;
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 growthIn = FixedPointMath.powDown(newBalanceIn * WAD / balanceIn, weightIn);
        uint256 growthOut = FixedPointMath.powDown(newBalanceOut * WAD / balanceOut, weightOut);
        uint256 invariantRatio = growthIn * growthOut / WAD;

        // Tiny divisors amplify rounding error. This approximate oracle cannot detect decreases below its tolerance.
        // Independent integer tests cover selected weight ratios without tolerance.
        assertGe(invariantRatio + 1e8, WAD, "the curve invariant must never decrease, even at near-zero balances");
    }

    /// @notice This trade used to reduce the invariant despite leaving a nonzero reserve.
    /// The precision floor must reject its tiny powered ratio.
    function test_RevertsOnTinyBalanceInHugeBalanceOutCounterexample() public {
        PortfolioManagerPricing.PoolState memory q = _quote(1, 1e24, 0.9e18, 0.1e18, 2e14);
        vm.expectPartialRevert(PortfolioManagerPricing.PortfolioManagerPricingPoweredRatioBelowPrecisionFloor.selector);
        this._exactIn(q, 93);
    }

    /// @notice Exercise accepted quotes and precision-floor reverts with tiny input and large output reserves.
    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_TinyBalanceInPairedWithHugeBalanceOutInvariantHolds(
        uint8 balInExp,
        uint8 balOutExp,
        uint256 weightInRaw,
        uint256 amountInRaw
    ) public {
        uint256 balanceIn = 10 ** bound(balInExp, 0, 6); // 1 .. 1e6
        uint256 balanceOut = 10 ** bound(balOutExp, 18, 30); // 1e18 .. 1e30
        uint256 weightIn = bound(weightInRaw, 0.05e18, 0.95e18);
        uint256 weightOut = WAD - weightIn;
        uint256 amountIn = bound(amountInRaw, 1, 10 * balanceIn);

        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 2e14);

        uint256 amountOut;
        try this._exactIn(q, amountIn) returns (uint256 out) {
            amountOut = out;
        } catch (bytes memory reason) {
            assertEq(
                bytes4(reason),
                PortfolioManagerPricing.PortfolioManagerPricingPoweredRatioBelowPrecisionFloor.selector,
                "only the precision floor may reject a trade in this domain"
            );
            return;
        }
        assertLt(amountOut, balanceOut, "exact-in must leave a nonzero output reserve");

        uint256 newBalanceIn = balanceIn + amountIn;
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 growthIn = FixedPointMath.powDown(newBalanceIn * WAD / balanceIn, weightIn);
        uint256 growthOut = FixedPointMath.powDown(newBalanceOut * WAD / balanceOut, weightOut);
        uint256 invariantRatio = growthIn * growthOut / WAD;

        // This approximate oracle can miss decreases within its tolerance. The independent
        // integer oracle below checks the 90%/10% case without that blind spot.
        assertGe(
            invariantRatio + 1e8,
            WAD,
            "the curve invariant must never decrease when balanceIn is tiny and balanceOut is huge"
        );
    }

    /// @notice Check balanceIn^9 * balanceOut with exact integer arithmetic, independent of production powers.
    /// @dev Bounds keep the post-trade product below (11e4)^9 * 1e30 < 2.36e75, within uint256.
    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_ExactInInvariantHoldsUnderExactIntegerArithmeticAtIntegerExponent(
        uint32 balInRaw,
        uint256 balOutRaw,
        uint256 amountInRaw
    ) public {
        uint256 weightIn = 0.9e18; // exponent = weightIn/weightOut = 9 exactly
        uint256 weightOut = 0.1e18;

        uint256 balanceIn = bound(balInRaw, 1, 1e4); // balanceIn^9 <= 1e36
        uint256 balanceOut = bound(balOutRaw, 1e18, 1e30); // product with balanceIn^9 <= 1e66, safe
        uint256 amountIn = bound(amountInRaw, 1, 10 * balanceIn);

        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 2e14);

        uint256 amountOut;
        try this._exactIn(q, amountIn) returns (uint256 out) {
            amountOut = out;
        } catch (bytes memory reason) {
            assertEq(
                bytes4(reason),
                PortfolioManagerPricing.PortfolioManagerPricingPoweredRatioBelowPrecisionFloor.selector,
                "only the precision floor may reject a trade in this domain"
            );
            return;
        }
        assertLt(amountOut, balanceOut, "exact-in must leave a nonzero output reserve");

        uint256 newBalanceIn = balanceIn + amountIn;

        uint256 invariantBefore = _pow9Exact(balanceIn) * balanceOut;
        uint256 invariantAfter = _pow9Exact(newBalanceIn) * (balanceOut - amountOut);

        assertGe(
            invariantAfter, invariantBefore, "exact-integer invariant (balanceIn^9 * balanceOut) must not decrease"
        );
    }

    function _pow9Exact(uint256 x) internal pure returns (uint256) {
        uint256 x3 = x * x * x;
        return x3 * x3 * x3;
    }

    /// @notice Check ordinary reserves and unequal weights with an approximate ratio oracle.
    /// @dev Independent integer and reference tests separately check rounding without tolerance.
    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_ExactOutNeverDecreasesTheInvariant(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 weightIn,
        uint256 amountOut
    ) public pure {
        balanceIn = bound(balanceIn, 1_000e18, 1_000_000_000e18);
        balanceOut = bound(balanceOut, 1_000e18, 1_000_000_000e18);
        weightIn = bound(weightIn, 0.05e18, 0.95e18);
        uint256 weightOut = WAD - weightIn;
        amountOut = bound(amountOut, 1e6, balanceOut / 10);

        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 0.0002e18);
        uint256 amountIn = PortfolioManagerPricing.exactOut(q, amountOut);
        assertTrue(amountOut == 0 || amountIn > 0, "positive output must require positive input");

        uint256 newBalanceIn = balanceIn + amountIn;
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 growthIn = FixedPointMath.powDown(newBalanceIn * WAD / balanceIn, weightIn);
        uint256 growthOut = FixedPointMath.powDown(newBalanceOut * WAD / balanceOut, weightOut);
        uint256 invariantRatio = growthIn * growthOut / WAD;

        assertGe(invariantRatio + 1e8, WAD, "the curve invariant must never decrease across an exact-out trade");
    }

    /// @notice Check exact-out at tiny reserves, with output capped at 10% of the reserve.
    /// @dev This isolates small-balance precision from near-total depletion.
    /// forge-config: default.fuzz.runs = 50000
    function testFuzz_ExactOutNeverDecreasesTheInvariantAtNearZeroBalance(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 weightIn,
        uint256 amountOut
    ) public {
        balanceIn = bound(balanceIn, 1, 1e6);
        balanceOut = bound(balanceOut, 1, 1e6);
        weightIn = bound(weightIn, 0.05e18, 0.95e18);
        uint256 weightOut = WAD - weightIn;
        amountOut = bound(amountOut, 0, balanceOut / 10);

        PortfolioManagerPricing.PoolState memory q = _quote(balanceIn, balanceOut, weightIn, weightOut, 0.0002e18);

        // Domain and precondition reverts are valid. Check the invariant only for accepted quotes.
        uint256 amountIn;
        try this._exactOut(q, amountOut) returns (uint256 in_) {
            amountIn = in_;
        } catch {
            return;
        }
        assertTrue(amountOut == 0 || amountIn > 0, "positive output must require positive input");

        uint256 newBalanceIn = balanceIn + amountIn;
        uint256 newBalanceOut = balanceOut - amountOut;

        uint256 growthIn = FixedPointMath.powDown(newBalanceIn * WAD / balanceIn, weightIn);
        uint256 growthOut = FixedPointMath.powDown(newBalanceOut * WAD / balanceOut, weightOut);
        uint256 invariantRatio = growthIn * growthOut / WAD;

        assertGe(
            invariantRatio + 1e8, WAD, "the curve invariant must never decrease, even at near-zero balances (exact-out)"
        );
    }

    function test_RoundTripAtOneWeiBalanceNeverProfitsTrader() public pure {
        PortfolioManagerPricing.PoolState memory q1 = _quote(1, 1e18, 0.5e18, 0.5e18, 0.0002e18);
        uint256 amountIn = 1_000e18;
        uint256 amountOut = PortfolioManagerPricing.exactIn(q1, amountIn);

        uint256 newBalanceIn = 1 + amountIn;
        uint256 newBalanceOut = 1e18 - amountOut;
        assertGt(newBalanceOut, 0, "exact-in must leave a nonzero output reserve");

        PortfolioManagerPricing.PoolState memory q2 = _quote(newBalanceOut, newBalanceIn, 0.5e18, 0.5e18, 0.0002e18);
        uint256 amountBack = PortfolioManagerPricing.exactIn(q2, amountOut);

        assertLt(amountBack, amountIn, "round-tripping through a near-empty pool must not profit the trader");
    }

    /// @notice Extreme weights and reserves must yield output inside (0, balanceOut) or revert.
    function test_ExtremeWeightSkewStaysBoundedOrRevertsCleanly() public {
        PortfolioManagerPricing.PoolState memory q = _quote(1, 1e18, 0.01e18, 0.99e18, 0);
        try this._exactIn(q, 1_000_000e18) returns (uint256 amountOut) {
            assertGt(amountOut, 0, "a non-reverting trade must return a nonzero amount");
            assertLt(amountOut, 1e18, "a non-reverting trade must never return more than the pool holds");
        } catch {
            // A clean revert is valid at this extreme.
        }
    }

    /// @notice Reject a powered ratio too small for reliable fixed-point pricing before it nearly drains the reserve.
    function test_ExactInRevertsInsteadOfDrainingPoolAtExtremeWeightSkew() public {
        PortfolioManagerPricing.PoolState memory q = _quote(1, 1_000_000, 0.9e18, 0.1e18, 0.0002e18);
        vm.expectPartialRevert(PortfolioManagerPricing.PortfolioManagerPricingPoweredRatioBelowPrecisionFloor.selector);
        this._exactIn(q, 1000);
    }

    /// @notice Compare exact-in with an independent real-number reference at 1e-12 relative tolerance.
    /// @dev Checks formula accuracy, not rounding direction.
    function test_ExactInMatchesIndependentReferenceImplementation() public pure {
        // Reference values computed independently via Decimal arithmetic at 60 significant
        // digits, from PRICING.md's formula directly (not via this contract's code).
        PortfolioManagerPricing.PoolState memory q1 = _quote(100_000e18, 100_000e18, 0.3e18, 0.7e18, 0.0002e18);
        _assertMatchesReference(PortfolioManagerPricing.exactIn(q1, 1000e18), 425450270259556705827);

        PortfolioManagerPricing.PoolState memory q2 = _quote(1_000_000e18, 1_000_000e18, 0.9e18, 0.1e18, 0.0002e18);
        _assertMatchesReference(PortfolioManagerPricing.exactIn(q2, 50_000e18), 355335828958235306891709);
    }

    function _assertMatchesReference(uint256 actual, uint256 expected) internal pure {
        uint256 diff = actual > expected ? actual - expected : expected - actual;
        assertLe(
            diff * 1e12, expected, "exactIn must match an independent reference implementation within 1e-12 relative"
        );
    }
}
