// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title PortfolioManagerFeedRegistry
/// @notice Owner-vetted feed -> index registry, letting a PM strategy reference a feed by a
///         2-byte index instead of its full 20-byte address.
/// @dev Unlike PortfolioManagerTokenRegistry, this is not permissionless: a feed index carries a
///      safety claim (someone verified this feed quotes the right pair for its intended use, and
///      how stale a reading from it may be before it's rejected), so only the owner can add
///      entries. The owner is intended to be a `TimelockController`, so every addition gets a
///      public review delay before it takes effect -- not enforced by this contract itself, just
///      by who it's deployed with as owner.
///      Index 0 is reserved to mean "no feed -- this member is its group's own numeraire"
///      (ADR-0017); it is never assigned a real feed.
///      `maxStaleness` is set per feed at registration time rather than fixed protocol-wide,
///      because different feed categories update on different cadences on-chain (a stablecoin
///      feed may legitimately go several hours without a new round under calm market conditions,
///      while a volatile-asset feed should be held to a tighter bound).
contract PortfolioManagerFeedRegistry is Ownable2Step {
    struct FeedEntry {
        address feed;
        uint32 maxStaleness;
    }

    /// @dev feedsByIndex[0] stays the zero entry forever -- see this contract's doc comment.
    FeedEntry[] public feedsByIndex;

    error PortfolioManagerFeedRegistryZeroAddress();
    error PortfolioManagerFeedRegistryZeroMaxStaleness();
    error PortfolioManagerFeedRegistryFull();

    event FeedRegistered(address indexed feed, uint16 index, uint32 maxStaleness);

    constructor(address owner_) Ownable(owner_) {
        feedsByIndex.push(FeedEntry({feed: address(0), maxStaleness: 0}));
    }

    /// @notice Registers `feed` with its staleness bound, returning its new index. Owner-gated --
    ///         see this contract's doc comment for why a feed index needs vetting that a token
    ///         index doesn't.
    function register(address feed, uint32 maxStaleness) external onlyOwner returns (uint16 index) {
        require(feed != address(0), PortfolioManagerFeedRegistryZeroAddress());
        require(maxStaleness != 0, PortfolioManagerFeedRegistryZeroMaxStaleness());
        require(feedsByIndex.length <= type(uint16).max, PortfolioManagerFeedRegistryFull());
        index = uint16(feedsByIndex.length);
        feedsByIndex.push(FeedEntry({feed: feed, maxStaleness: maxStaleness}));
        emit FeedRegistered(feed, index, maxStaleness);
    }

    /// @notice Returns the feed and its staleness bound at `index` -- both zero for index 0
    ///         (numeraire) or an out-of-range index.
    function feedAt(uint16 index) external view returns (address feed, uint32 maxStaleness) {
        if (index < feedsByIndex.length) {
            FeedEntry storage entry = feedsByIndex[index];
            return (entry.feed, entry.maxStaleness);
        }
        return (address(0), 0);
    }

    function feedCount() external view returns (uint256) {
        return feedsByIndex.length;
    }
}
