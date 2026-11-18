// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerFeedRegistry} from "../src/utils/PortfolioManagerFeedRegistry.sol";

contract PortfolioManagerFeedRegistryTest is Test {
    PortfolioManagerFeedRegistry internal registry;
    address internal feedA = address(0xFEED1);

    function setUp() public {
        registry = new PortfolioManagerFeedRegistry(address(this));
    }

    /// @dev The reserved numeraire sentinel -- always valid, must never revert.
    function test_FeedAtReturnsZeroEntryForIndex0() public view {
        (address feed, uint32 maxStaleness) = registry.feedAt(0);
        assertEq(feed, address(0));
        assertEq(maxStaleness, 0);
    }

    function test_FeedAtReturnsTheRegisteredFeed() public {
        uint16 index = registry.register(feedA, 1 hours);
        (address feed, uint32 maxStaleness) = registry.feedAt(index);
        assertEq(feed, feedA);
        assertEq(maxStaleness, 1 hours);
    }

    /// @dev The actual fix: an index that was never registered used to silently resolve to
    ///      `(address(0), 0)`, identical to index 0's legitimate numeraire entry -- letting an
    ///      unvetted feedIndex pass as a numeraire undetected. It must revert instead.
    function test_FeedAtRevertsForNeverRegisteredIndex() public {
        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerFeedRegistry.PortfolioManagerFeedRegistryIndexOutOfRange.selector, 1)
        );
        registry.feedAt(1);
    }

    /// @dev Same bug, the more realistic shape: an index just past the last real registration
    ///      (e.g. a strategy encoded against a feed count that later shrank, or simply a typo)
    ///      must revert exactly the same way a far-out-of-range index does.
    function test_FeedAtRevertsForIndexOneOutOfRange() public {
        uint16 lastValidIndex = registry.register(feedA, 1 hours);
        uint16 outOfRange = lastValidIndex + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerFeedRegistry.PortfolioManagerFeedRegistryIndexOutOfRange.selector, outOfRange
            )
        );
        registry.feedAt(outOfRange);
    }

    function test_FeedAtRevertsForMaxUint16Index() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerFeedRegistry.PortfolioManagerFeedRegistryIndexOutOfRange.selector, type(uint16).max
            )
        );
        registry.feedAt(type(uint16).max);
    }
}
