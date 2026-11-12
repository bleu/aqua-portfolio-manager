// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {FixedPointMath} from "./FixedPointMath.sol";

/// @title PortfolioManagerDynamicFee
/// @notice Pure implementation of a Synthetix SIP-184-style dynamic fee: a per-feed fee boost
///         that rises when a feed's price moves more than its own deviation threshold allows
///         between two observations, and decays back to zero once the market stabilizes.
/// @dev Exists to neutralize oracle-staleness/front-running arbitrage (1inch devteam review,
///      2026-10-15) as a cheap complement to BLEUDEV-425's TWAP work: TWAP changes which PRICE a
///      swap sees, this changes the FEE charged on top of whatever price is used -- the two
///      compose independently and neither depends on the other. This library reads no state and
///      makes no external calls; PortfolioManagerSwap owns the per-feed storage and calls this
///      once per traded feed per swap.
library PortfolioManagerDynamicFee {
    uint256 internal constant WAD = FixedPointMath.WAD;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @dev Decay constant (tau). Reused verbatim from Synthetix's own published example: at
    ///      tau=0.9 the boost halves roughly every ~7 stable epochs and reverts to dust after
    ///      ~20 -- a starting point for Pedro's review, not independently re-derived for this
    ///      pool's own volatility profile.
    uint256 internal constant DECAY_TAU_WAD = 0.9e18;

    /// @dev Minimum-threshold term (mu) from the SIP-184 formula. Zero here: the 2x-deviation-
    ///      threshold term below already filters out normal feed jitter before mu would apply,
    ///      and Synthetix's own writeup gives no concrete value to copy. Flagged as a tuning
    ///      knob, not a considered default.
    uint256 internal constant MIN_THRESHOLD_WAD = 0;

    /// @dev Safety ceiling, not part of SIP-184's own formula. A pathological feed answer (or
    ///      several consecutive large moves compounding under decay) could otherwise push the
    ///      boost past WAD, underflowing `WAD - feeWad` in PortfolioManagerPricing.exactIn and
    ///      reverting every swap on that pair until it decays back down. Capping here keeps the
    ///      fee always computable; 50% is a first-draft number for review, not derived from the
    ///      pool's own risk tolerance.
    uint256 internal constant MAX_BOOST_WAD = 0.5e18;

    /// @notice One epoch's dynamic fee boost, WAD-scaled (same units as PortfolioManagerPricing's
    ///         feeWad), to add on top of a swap's base LP fee.
    /// @param lastPriceWad The feed's price as of the previous observation. Zero means this feed
    ///        has never been observed before -- the caller must treat that as "no boost, just
    ///        record the first observation" rather than calling this function, since a zero
    ///        `lastPriceWad` has no meaningful ratio to compute against.
    /// @param currentPriceWad The feed's price as of this swap.
    /// @param deviationThresholdBps The feed's own configured deviation threshold (delta), in
    ///        standard basis points (1e4 scale, matching PortfolioManagerFeedRegistry's and
    ///        base-mainnet-feeds.json's existing units -- NOT PortfolioManagerArgsCodec's PM_BPS
    ///        scale). Zero disables the dynamic fee for this feed entirely.
    /// @param priorBoostWad The previous epoch's boost, before this epoch's decay and new move.
    function computeBoostWad(
        uint256 lastPriceWad,
        uint256 currentPriceWad,
        uint16 deviationThresholdBps,
        uint256 priorBoostWad
    ) internal pure returns (uint256 newBoostWad) {
        if (deviationThresholdBps == 0 || lastPriceWad == 0) return 0;

        uint256 priceMoveWad =
            currentPriceWad > lastPriceWad ? currentPriceWad - lastPriceWad : lastPriceWad - currentPriceWad;
        uint256 moveFractionWad = FixedPointMath.divDown(priceMoveWad, lastPriceWad);

        // "2 * delta" per SIP-184: a move has to clear twice the feed's own deviation threshold
        // before it's treated as an exploitable jump rather than the feed's normal behavior.
        uint256 twoThresholdWad = (uint256(deviationThresholdBps) * WAD / BPS_DENOMINATOR) * 2;

        uint256 excessWad = moveFractionWad > twoThresholdWad ? moveFractionWad - twoThresholdWad : 0;
        uint256 rawBoostWad = excessWad > MIN_THRESHOLD_WAD ? excessWad - MIN_THRESHOLD_WAD : 0;

        uint256 decayedPriorBoostWad = FixedPointMath.mulDown(priorBoostWad, DECAY_TAU_WAD);
        newBoostWad = decayedPriorBoostWad + rawBoostWad;
        if (newBoostWad > MAX_BOOST_WAD) newBoostWad = MAX_BOOST_WAD;
    }
}
