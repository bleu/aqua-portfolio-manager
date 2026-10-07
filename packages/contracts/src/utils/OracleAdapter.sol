// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {FixedPointMath} from "./FixedPointMath.sol";

/// @title OracleAdapter
/// @notice Converts token balances through fresh push feeds into a common WAD-scaled value.
/// @dev All feeds must use the same quote currency. Stale or non-positive prices revert.
library OracleAdapter {
    uint256 internal constant WAD = FixedPointMath.WAD;

    error OracleAdapterStalePrice(address feed, uint256 updatedAt, uint256 maxStaleness);
    error OracleAdapterInvalidPrice(address feed, int256 answer);
    error OracleAdapterTokensFeedsLengthMismatch();
    /// @dev `answeredInRound < roundId` means this round's price carried over from an earlier,
    ///      possibly-stale aggregator round instead of being freshly reported in this one --
    ///      Chainlink's own documented pattern for detecting an incomplete round. A zero roundId
    ///      is never valid either.
    error OracleAdapterIncompleteRound(address feed, uint80 roundId, uint80 answeredInRound);
    error OracleAdapterSequencerDown(address sequencerUptimeFeed);
    /// @dev Chainlink's documented L2 pattern: feeds can keep reporting a pre-outage price for a
    ///      while after the sequencer recovers, since nothing forced an update during the outage.
    ///      A fixed post-recovery grace period gives feeds time to catch up to the real market
    ///      before this adapter trusts them again.
    error OracleAdapterSequencerGracePeriodNotElapsed(
        address sequencerUptimeFeed, uint256 timeSinceUp, uint256 gracePeriod
    );

    /// @dev Chainlink's own recommended grace period for L2 sequencer-uptime feeds.
    uint256 internal constant SEQUENCER_GRACE_PERIOD = 1 hours;

    enum Rounding {
        Down,
        Up
    }

    /// @param feed Chainlink-style feed for one token.
    /// @param maxStaleness Maximum permitted price age in seconds.
    struct PriceFeed {
        AggregatorV3Interface feed;
        uint256 maxStaleness;
    }

    /// @notice Returns the WAD-scaled price of one whole token with the requested rounding.
    /// @dev Rejects stale, non-positive prices and prices below one raw WAD unit.
    function priceWad(PriceFeed memory config, Rounding rounding) internal view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = config.feed.latestRoundData();
        require(answer > 0, OracleAdapterInvalidPrice(address(config.feed), answer));
        require(
            roundId != 0 && answeredInRound >= roundId,
            OracleAdapterIncompleteRound(address(config.feed), roundId, answeredInRound)
        );
        require(
            updatedAt <= block.timestamp, OracleAdapterStalePrice(address(config.feed), updatedAt, config.maxStaleness)
        );
        require(
            block.timestamp - updatedAt <= config.maxStaleness,
            OracleAdapterStalePrice(address(config.feed), updatedAt, config.maxStaleness)
        );

        uint8 decimals = config.feed.decimals();
        uint256 lower = FixedPointMath.scaleDown(uint256(answer), decimals, 18);
        require(lower > 0, OracleAdapterInvalidPrice(address(config.feed), answer));
        return rounding == Rounding.Up ? FixedPointMath.scaleUp(uint256(answer), decimals, 18) : lower;
    }

    /// @notice Reverts unless the L2 sequencer is up and has stayed up through the grace period.
    /// @dev Chainlink's sequencer-uptime feed reuses AggregatorV3Interface: answer == 0 means up,
    ///      answer == 1 means down, and startedAt is when that status last changed.
    function requireSequencerUp(AggregatorV3Interface sequencerUptimeFeed) internal view {
        (, int256 answer,, uint256 startedAt,) = sequencerUptimeFeed.latestRoundData();
        require(answer == 0, OracleAdapterSequencerDown(address(sequencerUptimeFeed)));

        uint256 timeSinceUp = block.timestamp - startedAt;
        require(
            timeSinceUp >= SEQUENCER_GRACE_PERIOD,
            OracleAdapterSequencerGracePeriodNotElapsed(
                address(sequencerUptimeFeed), timeSinceUp, SEQUENCER_GRACE_PERIOD
            )
        );
    }

    /// @notice Sums member balances multiplied by their prices, with token and feed decimal normalization.
    /// @param balances Native token balances before normalization.
    /// @param rounding Round each member up for input reserves and down for output reserves.
    function groupValueWad(
        address[] memory tokens,
        uint256[] memory balances,
        PriceFeed[] memory feeds,
        Rounding rounding
    ) internal view returns (uint256 totalValueWad) {
        require(
            tokens.length == balances.length && tokens.length == feeds.length, OracleAdapterTokensFeedsLengthMismatch()
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            uint8 tokenDecimals = IERC20Metadata(tokens[i]).decimals();
            uint256 price = priceWad(feeds[i], rounding);
            uint256 unit = FixedPointMath.scaleDown(1, 0, tokenDecimals);
            totalValueWad += rounding == Rounding.Up
                ? FixedPointMath.mulDivUp(balances[i], price, unit)
                : FixedPointMath.mulDivDown(balances[i], price, unit);
        }
    }
}
