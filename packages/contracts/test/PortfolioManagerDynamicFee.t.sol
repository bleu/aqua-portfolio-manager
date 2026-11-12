// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerDynamicFee} from "../src/utils/PortfolioManagerDynamicFee.sol";

contract PortfolioManagerDynamicFeeTest is Test {
    uint256 constant WAD = 1e18;

    function test_NoBoostWhenMoveIsWithinTwiceTheDeviationThreshold() public pure {
        // WBTC-style feed: deviationThresholdBps = 10 (0.10%). A 0.15% move (1.5x threshold)
        // stays under the 2x-threshold gate, so it should not trigger any boost at all.
        uint256 lastPrice = 100_000e18;
        uint256 currentPrice = lastPrice + (lastPrice * 15 / 10_000); // +0.15%
        uint256 boost = PortfolioManagerDynamicFee.computeBoostWad(lastPrice, currentPrice, 10, 0);
        assertEq(boost, 0);
    }

    function test_BoostEqualsExcessOverTwiceTheDeviationThreshold() public pure {
        // Same feed, a 0.50% move (5x threshold): boost = 0.50% - 2*0.10% = 0.30%.
        uint256 lastPrice = 100_000e18;
        uint256 currentPrice = lastPrice + (lastPrice * 50 / 10_000); // +0.50%
        uint256 boost = PortfolioManagerDynamicFee.computeBoostWad(lastPrice, currentPrice, 10, 0);
        assertApproxEqAbs(boost, 0.003e18, 1e9); // 0.30%, WAD-scaled, within tiny rounding slack
    }

    function test_BoostIsSymmetricForPriceDrops() public pure {
        uint256 lastPrice = 100_000e18;
        uint256 currentPrice = lastPrice - (lastPrice * 50 / 10_000); // -0.50%
        uint256 boost = PortfolioManagerDynamicFee.computeBoostWad(lastPrice, currentPrice, 10, 0);
        assertApproxEqAbs(boost, 0.003e18, 1e9);
    }

    function test_PriorBoostDecaysByTau() public pure {
        // No new move (currentPrice == lastPrice): the whole boost should just be the prior
        // boost times tau (0.9), per the decay term alone.
        uint256 lastPrice = 100_000e18;
        uint256 priorBoost = 0.01e18;
        uint256 boost = PortfolioManagerDynamicFee.computeBoostWad(lastPrice, lastPrice, 10, priorBoost);
        assertApproxEqAbs(boost, 0.009e18, 1e9); // 0.01 * 0.9
    }

    function test_DecayAndNewMoveCompose() public pure {
        uint256 lastPrice = 100_000e18;
        uint256 currentPrice = lastPrice + (lastPrice * 50 / 10_000); // +0.50% -> raw boost 0.30%
        uint256 priorBoost = 0.01e18;
        uint256 boost = PortfolioManagerDynamicFee.computeBoostWad(lastPrice, currentPrice, 10, priorBoost);
        // decayed prior (0.01 * 0.9 = 0.009) + this epoch's raw boost (0.003) = 0.012
        assertApproxEqAbs(boost, 0.012e18, 1e9);
    }

    function test_ZeroDeviationThresholdDisablesTheFeeEntirely() public pure {
        uint256 lastPrice = 100_000e18;
        uint256 currentPrice = lastPrice * 2; // a massive move
        uint256 boost = PortfolioManagerDynamicFee.computeBoostWad(lastPrice, currentPrice, 0, 0.4e18);
        assertEq(boost, 0);
    }

    function test_ZeroLastPriceReturnsZero() public pure {
        // The caller's own contract (PortfolioManagerSwap) is responsible for not calling this
        // for a feed's first-ever observation, but the library stays safe either way.
        uint256 boost = PortfolioManagerDynamicFee.computeBoostWad(0, 100_000e18, 10, 0);
        assertEq(boost, 0);
    }

    function test_BoostIsCappedEvenAfterAnExtremeMoveAndHighPriorBoost() public pure {
        uint256 lastPrice = 100_000e18;
        uint256 currentPrice = lastPrice * 10; // +900%, a wildly broken feed answer
        uint256 boost = PortfolioManagerDynamicFee.computeBoostWad(lastPrice, currentPrice, 10, 0.49e18);
        assertEq(boost, 0.5e18);
    }

    function test_RepeatedStableEpochsDecayBoostTowardZero() public pure {
        uint256 lastPrice = 100_000e18;
        uint256 startingBoost = 0.1e18;
        uint256 boost = startingBoost;
        for (uint256 i = 0; i < 20; i++) {
            boost = PortfolioManagerDynamicFee.computeBoostWad(lastPrice, lastPrice, 10, boost);
        }
        // tau=0.9 over 20 stable epochs: 0.1 * 0.9^20 ~= 0.01216 (an 88% reduction) -- Synthetix's
        // own writeup calls this "reverts to zero after 20 stable epochs" loosely; it's a steep
        // decay, not literally zero. Assert the reduction instead of a specific absolute floor.
        assertLt(boost, startingBoost / 5);
    }
}
