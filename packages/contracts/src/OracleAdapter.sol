// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @title OracleAdapter — Chainlink-style push-feed pricing, per ADR-0005
/// @notice Two jobs, both per-feed, matching ADR-0005's decision exactly: reject a stale read
///         outright (no fallback price, no degraded execution), and convert each declared
///         group member's own-decimal balance through its own feed's price into one common
///         WAD-scaled value, per ADR-0003 (`Σ balance_j × oracle_price_j`) — the `B_i`/`B_o`
///         PRICING.md's formula actually consumes for a multi-token group. The reference PoC
///         (`BasketXYCSwap.sol`) adds a basket token's raw balance with no price applied,
///         correct only by coincidence when every group member is worth the same
///         (see `docs/ARCHITECTURE.md`'s Oracle Adapter component note) — this is the corrected
///         version.
library OracleAdapter {
    uint256 internal constant WAD = 1e18;

    error OracleAdapterStalePrice(address feed, uint256 updatedAt, uint256 maxStaleness);
    error OracleAdapterInvalidPrice(address feed, int256 answer);
    error OracleAdapterTokensFeedsLengthMismatch();

    /// @param feed         The Chainlink-style aggregator for one declared token.
    /// @param maxStaleness Per-feed threshold (ADR-0005: "coverage quality varies by token, so
    ///                     one global threshold isn't appropriate") — a config value, not a
    ///                     constant here.
    struct PriceFeed {
        AggregatorV3Interface feed;
        uint256 maxStaleness;
    }

    /// @notice WAD-scaled price of one whole unit of the feed's underlying token.
    /// @dev Reverts on a stale or non-positive read — ADR-0005's Decision is explicit that a
    ///      stale read reverts the whole trade, never falls back to a last-known-good price.
    function priceWad(PriceFeed memory config) internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = config.feed.latestRoundData();
        require(answer > 0, OracleAdapterInvalidPrice(address(config.feed), answer));
        require(
            updatedAt <= block.timestamp, OracleAdapterStalePrice(address(config.feed), updatedAt, config.maxStaleness)
        );
        require(
            block.timestamp - updatedAt <= config.maxStaleness,
            OracleAdapterStalePrice(address(config.feed), updatedAt, config.maxStaleness)
        );

        uint8 feedDecimals = config.feed.decimals();
        uint256 rawPrice = uint256(answer);
        if (feedDecimals < 18) {
            return rawPrice * 10 ** (18 - feedDecimals);
        } else if (feedDecimals > 18) {
            return rawPrice / 10 ** (feedDecimals - 18);
        }
        return rawPrice;
    }

    /// @notice `Σ (token_balance_j × oracle_price_j)` over a group's declared members
    ///         (ADR-0003), converted to one comparable WAD-scaled value — PRICING.md's `B_i`/
    ///         `B_o` for a multi-token group. `balances` are each token's own real, native-
    ///         decimal balance (e.g. from `ExposureReader`), not yet normalized for either the
    ///         token's own decimals or the feed's — both normalizations happen here.
    function groupValueWad(address[] memory tokens, uint256[] memory balances, PriceFeed[] memory feeds)
        internal
        view
        returns (uint256 totalValueWad)
    {
        require(
            tokens.length == balances.length && tokens.length == feeds.length, OracleAdapterTokensFeedsLengthMismatch()
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            uint8 tokenDecimals = IERC20Metadata(tokens[i]).decimals();
            uint256 price = priceWad(feeds[i]);
            totalValueWad += balances[i] * price / 10 ** tokenDecimals;
        }
    }
}
