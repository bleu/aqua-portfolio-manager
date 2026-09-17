// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerArgsBuilder, PM_BPS} from "../src/PortfolioManagerArgsBuilder.sol";

contract PortfolioManagerArgsBuilderTest is Test {
    uint256 constant WAD = 1e18;

    address constant TOKEN_A = address(0xA11CE);
    address constant TOKEN_B = address(0xB0B);
    address constant TOKEN_C = address(0xC0FFEE);
    address constant FEED_A = address(0xFEEDA);
    address constant FEED_B = address(0xFEEDB);
    address constant FEED_C = address(0xFEEDC);

    uint256 constant STALENESS = 3600;

    // See FixedPointMath.t.sol for why internal pure library calls need an external wrapper
    // for `vm.expectRevert` to intercept the revert at the right call depth.
    function _callBuild(PortfolioManagerArgsBuilder.Group[] memory groups, uint32 feeBps)
        external
        pure
        returns (bytes memory)
    {
        return PortfolioManagerArgsBuilder.build(groups, feeBps);
    }

    function _callParse(bytes calldata args)
        external
        pure
        returns (PortfolioManagerArgsBuilder.Group[] memory, uint32, uint32)
    {
        return PortfolioManagerArgsBuilder.parse(args);
    }

    function _singleMemberGroup(uint256 weight, address token, address feed)
        private
        pure
        returns (PortfolioManagerArgsBuilder.Group memory)
    {
        PortfolioManagerArgsBuilder.Member[] memory members = new PortfolioManagerArgsBuilder.Member[](1);
        members[0] = PortfolioManagerArgsBuilder.Member({token: token, feed: feed, maxStaleness: STALENESS});
        return PortfolioManagerArgsBuilder.Group({weight: weight, members: members});
    }

    // ---- round trip ----

    function test_BuildThenParseRoundTripsMinimalTwoGroupUniverse() public view {
        // MIN_GROUPS floor -- the smallest valid universe is 2 single-member groups.
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        bytes memory args = PortfolioManagerArgsBuilder.build(groups, 2e5); // 2bps, ADR-0008 default
        (PortfolioManagerArgsBuilder.Group[] memory parsed, uint32 parsedFeeBps, uint32 parsedMaxDeviationBps) =
            this._callParse(args);

        assertEq(parsed.length, 2);
        assertEq(parsed[0].weight, 0.5e18);
        assertEq(parsed[0].members.length, 1);
        assertEq(parsed[0].members[0].token, TOKEN_A);
        assertEq(parsed[0].members[0].feed, FEED_A);
        assertEq(parsed[0].members[0].maxStaleness, STALENESS);
        assertEq(parsed[1].weight, 0.5e18);
        assertEq(parsedFeeBps, 2e5);
        assertEq(parsedMaxDeviationBps, 0);
    }

    function test_BuildThenParseRoundTripsMaxDeviationBps() public view {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        bytes memory args = PortfolioManagerArgsBuilder.build(groups, 2e5, 5e7); // 5% circuit breaker
        (,, uint32 parsedMaxDeviationBps) = this._callParse(args);

        assertEq(parsedMaxDeviationBps, 5e7);
    }

    function test_BuildThenParseRoundTripsUnequalWeights() public view {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](3);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.3e18, TOKEN_B, FEED_B);
        groups[2] = _singleMemberGroup(0.2e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsBuilder.build(groups, 0);
        (PortfolioManagerArgsBuilder.Group[] memory parsed, uint32 parsedFeeBps,) = this._callParse(args);

        assertEq(parsed.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(parsed[i].members[0].token, groups[i].members[0].token);
            assertEq(parsed[i].weight, groups[i].weight);
        }
        assertEq(parsedFeeBps, 0);
    }

    function test_BuildThenParseRoundTripsMultiTokenGroup() public view {
        PortfolioManagerArgsBuilder.Member[] memory members = new PortfolioManagerArgsBuilder.Member[](2);
        members[0] = PortfolioManagerArgsBuilder.Member({token: TOKEN_A, feed: FEED_A, maxStaleness: STALENESS});
        members[1] = PortfolioManagerArgsBuilder.Member({token: TOKEN_B, feed: FEED_B, maxStaleness: STALENESS * 2});

        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = PortfolioManagerArgsBuilder.Group({weight: 0.6e18, members: members});
        groups[1] = _singleMemberGroup(0.4e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsBuilder.build(groups, 1e5);
        (PortfolioManagerArgsBuilder.Group[] memory parsed, uint32 parsedFeeBps,) = this._callParse(args);

        assertEq(parsed.length, 2);
        assertEq(parsed[0].weight, 0.6e18);
        assertEq(parsed[0].members.length, 2);
        assertEq(parsed[0].members[0].token, TOKEN_A);
        assertEq(parsed[0].members[0].feed, FEED_A);
        assertEq(parsed[0].members[0].maxStaleness, STALENESS);
        assertEq(parsed[0].members[1].token, TOKEN_B);
        assertEq(parsed[0].members[1].maxStaleness, STALENESS * 2);
        assertEq(parsed[1].weight, 0.4e18);
        assertEq(parsedFeeBps, 1e5);
    }

    function testFuzz_BuildThenParseRoundTrips(uint8 seed, uint32 feeBps) public view {
        feeBps = uint32(bound(feeBps, 0, PM_BPS));
        uint256 n = bound(seed, PortfolioManagerArgsBuilder.MIN_GROUPS, PortfolioManagerArgsBuilder.MAX_GROUPS);

        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](n);
        uint256 remaining = WAD;
        for (uint256 i = 0; i < n; i++) {
            // Last weight soaks up the remainder so the set always sums to exactly WAD.
            uint256 weight = i == n - 1 ? remaining : remaining / (n - i);
            remaining -= weight;
            groups[i] = _singleMemberGroup(weight, address(uint160(0x1000 + i)), address(uint160(0x2000 + i)));
        }

        bytes memory args = PortfolioManagerArgsBuilder.build(groups, feeBps);
        (PortfolioManagerArgsBuilder.Group[] memory parsed, uint32 parsedFeeBps,) = this._callParse(args);

        assertEq(parsed.length, n);
        for (uint256 i = 0; i < n; i++) {
            assertEq(parsed[i].members[0].token, groups[i].members[0].token);
            assertEq(parsed[i].weight, groups[i].weight);
        }
        assertEq(parsedFeeBps, feeBps);
    }

    // ---- build: validation ----

    function test_BuildRevertsOnEmptyUniverse() public {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](0);

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerEmptyUniverse.selector);
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnEmptyGroup() public {
        // group[1] is never reached -- group[0]'s own empty-members check reverts first --
        // it's here only so the array itself satisfies MIN_GROUPS.
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] =
            PortfolioManagerArgsBuilder.Group({weight: WAD, members: new PortfolioManagerArgsBuilder.Member[](0)});
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerEmptyGroup.selector, 0));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsWhenWeightsDoNotSumToWad() public {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.4e18, TOKEN_B, FEED_B); // sums to 0.9e18, not WAD

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerWeightsMustSumToWad.selector, 0.9e18)
        );
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnZeroWeight() public {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = _singleMemberGroup(0, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerZeroWeight.selector, 0));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnTooFewGroups() public {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](1);
        groups[0] = _singleMemberGroup(WAD, TOKEN_A, FEED_A);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerTooFewGroups.selector, 1));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnTooManyGroups() public {
        uint256 n = PortfolioManagerArgsBuilder.MAX_GROUPS + 1;
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](n);
        // Values don't need to sum to WAD -- the length check reverts before the weights loop.

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerTooManyGroups.selector, n));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnTooManyMembers() public {
        uint256 n = PortfolioManagerArgsBuilder.MAX_MEMBERS_PER_GROUP + 1;
        PortfolioManagerArgsBuilder.Member[] memory members = new PortfolioManagerArgsBuilder.Member[](n);
        for (uint256 i = 0; i < n; i++) {
            members[i] = PortfolioManagerArgsBuilder.Member({
                token: address(uint160(0x1000 + i)), feed: address(uint160(0x2000 + i)), maxStaleness: STALENESS
            });
        }
        // group[1] is never reached -- group[0]'s own too-many-members check reverts first --
        // it's here only so the array itself satisfies MIN_GROUPS.
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = PortfolioManagerArgsBuilder.Group({weight: WAD, members: members});
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerTooManyMembers.selector, n));
        this._callBuild(groups, 0);
    }

    /// @notice Two groups, each at exactly MAX_MEMBERS_PER_GROUP members (5) -- passes every
    /// per-axis check individually (group count and each group's own member count are both
    /// within bounds) but the joint encoding is 463 bytes, over the wire format's 255-byte
    /// capacity. Without build()'s own explicit length check, this would sail through here and
    /// only fail one layer up in PortfolioManagerProgramBuilder with an opaque SafeCast overflow
    /// instead of this descriptive error.
    function test_BuildRevertsOnArgsTooLargeEvenWhenEachAxisIsWithinBounds() public {
        PortfolioManagerArgsBuilder.Member[] memory members0 =
            new PortfolioManagerArgsBuilder.Member[](PortfolioManagerArgsBuilder.MAX_MEMBERS_PER_GROUP);
        PortfolioManagerArgsBuilder.Member[] memory members1 =
            new PortfolioManagerArgsBuilder.Member[](PortfolioManagerArgsBuilder.MAX_MEMBERS_PER_GROUP);
        for (uint256 i = 0; i < PortfolioManagerArgsBuilder.MAX_MEMBERS_PER_GROUP; i++) {
            members0[i] = PortfolioManagerArgsBuilder.Member({
                token: address(uint160(0x1000 + i)), feed: address(uint160(0x2000 + i)), maxStaleness: STALENESS
            });
            members1[i] = PortfolioManagerArgsBuilder.Member({
                token: address(uint160(0x3000 + i)), feed: address(uint160(0x4000 + i)), maxStaleness: STALENESS
            });
        }
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = PortfolioManagerArgsBuilder.Group({weight: 0.5e18, members: members0});
        groups[1] = PortfolioManagerArgsBuilder.Group({weight: 0.5e18, members: members1});

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerArgsTooLarge.selector, 463));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnZeroFeedAddress() public {
        // group[1] is never reached -- group[0]'s own zero-feed check reverts first -- it's here
        // only so the array itself satisfies MIN_GROUPS.
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = _singleMemberGroup(WAD, TOKEN_A, address(0));
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerZeroFeedAddress.selector, TOKEN_A)
        );
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnDuplicateTokenAcrossGroups() public {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_B); // TOKEN_A declared twice

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerDuplicateToken.selector, TOKEN_A)
        );
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnFeeBpsAboveHundredPercent() public {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerFeeBpsOutOfRange.selector, PM_BPS + 1)
        );
        this._callBuild(groups, uint32(PM_BPS + 1));
    }

    // ---- parse: hand-crafted args must be independently validated, not just trust build() ----

    function test_ParseRevertsWhenHandCraftedWeightsDoNotSumToWad() public {
        // 2 groups, weights 0.5e18 + 0.3e18 (sums to 0.8e18, not WAD) -- crafted directly,
        // bypassing build().
        bytes memory malformed = abi.encodePacked(
            uint8(2),
            uint128(0.5e18),
            uint8(1),
            TOKEN_A,
            FEED_A,
            uint16(STALENESS),
            uint128(0.3e18),
            uint8(1),
            TOKEN_B,
            FEED_B,
            uint16(STALENESS),
            uint32(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerWeightsMustSumToWad.selector, 0.8e18)
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnHandCraftedZeroWeight() public {
        // 2 groups, weights [0, WAD] -- sums to WAD, so only the per-weight check catches this,
        // not the sum check. A zero weight here would otherwise divide by zero on every trade
        // for TOKEN_A once PortfolioManagerPricing computes its weight ratio.
        bytes memory malformed = abi.encodePacked(
            uint8(2),
            uint128(0),
            uint8(1),
            TOKEN_A,
            FEED_A,
            uint16(STALENESS),
            uint128(WAD),
            uint8(1),
            TOKEN_B,
            FEED_B,
            uint16(STALENESS),
            uint32(0)
        );

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerZeroWeight.selector, 0));
        this._callParse(malformed);
    }

    function test_ParseRevertsOnEmptyUniverse() public {
        bytes memory malformed = abi.encodePacked(uint8(0));

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerEmptyUniverse.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTooFewGroups() public {
        // The group-count check fires right after reading the leading byte, before any group
        // body is parsed -- no further bytes needed.
        bytes memory malformed = abi.encodePacked(uint8(1));

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerTooFewGroups.selector, 1));
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTooManyGroups() public {
        bytes memory malformed = abi.encodePacked(uint8(PortfolioManagerArgsBuilder.MAX_GROUPS + 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerArgsBuilder.PortfolioManagerTooManyGroups.selector,
                PortfolioManagerArgsBuilder.MAX_GROUPS + 1
            )
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTooManyMembers() public {
        // 2 groups (satisfies MIN_GROUPS) -- group[0]'s member count alone is enough to revert,
        // no member entries or a real group[1] needed.
        bytes memory malformed =
            abi.encodePacked(uint8(2), uint128(WAD), uint8(PortfolioManagerArgsBuilder.MAX_MEMBERS_PER_GROUP + 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerArgsBuilder.PortfolioManagerTooManyMembers.selector,
                PortfolioManagerArgsBuilder.MAX_MEMBERS_PER_GROUP + 1
            )
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTruncatedGroupHeader() public {
        // Declares 2 groups (satisfies MIN_GROUPS) but only supplies 10 of the required 17
        // header bytes for the first one.
        bytes memory malformed = abi.encodePacked(uint8(2), uint80(0));

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerMissingGroupHeader.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTruncatedMemberEntry() public {
        // Valid group header (1 member), 2 groups declared, but only 10 of the required 44
        // bytes supplied for the first member.
        bytes memory malformed = abi.encodePacked(uint8(2), uint128(WAD), uint8(1), uint80(0));

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerMissingMemberEntry.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnZeroFeedAddress() public {
        // group[0]'s own zero-feed check reverts before group[1] would ever need to be
        // present -- 2 groups declared only to satisfy MIN_GROUPS.
        bytes memory malformed =
            abi.encodePacked(uint8(2), uint128(WAD), uint8(1), TOKEN_A, address(0), uint16(STALENESS));

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsBuilder.PortfolioManagerZeroFeedAddress.selector, TOKEN_A)
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnMissingFeeBps() public {
        // Valid 2-group universe (sums to WAD) but no trailing feeBps bytes.
        bytes memory malformed = abi.encodePacked(
            uint8(2),
            uint128(0.5e18),
            uint8(1),
            TOKEN_A,
            FEED_A,
            uint16(STALENESS),
            uint128(0.5e18),
            uint8(1),
            TOKEN_B,
            FEED_B,
            uint16(STALENESS)
        );

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerMissingFeeBps.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnMissingMaxDeviationBps() public {
        // Valid 2-group universe plus feeBps, but no trailing maxDeviationBps bytes.
        bytes memory malformed = abi.encodePacked(
            uint8(2),
            uint128(0.5e18),
            uint8(1),
            TOKEN_A,
            FEED_A,
            uint16(STALENESS),
            uint128(0.5e18),
            uint8(1),
            TOKEN_B,
            FEED_B,
            uint16(STALENESS),
            uint32(0)
        );

        vm.expectRevert(PortfolioManagerArgsBuilder.PortfolioManagerMissingMaxDeviationBps.selector);
        this._callParse(malformed);
    }
}
