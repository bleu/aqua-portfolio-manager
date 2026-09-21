// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";

contract PortfolioManagerArgsCodecTest is Test {
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
    function _callBuild(PortfolioManagerArgsCodec.Group[] memory groups, uint32 feeBps)
        external
        pure
        returns (bytes memory)
    {
        return PortfolioManagerArgsCodec.build(groups, feeBps);
    }

    function _callParse(bytes calldata args)
        external
        pure
        returns (PortfolioManagerArgsCodec.Group[] memory, uint32, uint32)
    {
        return PortfolioManagerArgsCodec.parse(args);
    }

    function _callDecodeTrusted(bytes calldata args)
        external
        pure
        returns (PortfolioManagerArgsCodec.Group[] memory, uint32, uint32)
    {
        return PortfolioManagerArgsCodec.decodeTrusted(args);
    }

    function _singleMemberGroup(uint256 weight, address token, address feed)
        private
        pure
        returns (PortfolioManagerArgsCodec.Group memory)
    {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](1);
        members[0] = PortfolioManagerArgsCodec.Member({token: token, feed: feed, maxStaleness: STALENESS});
        return PortfolioManagerArgsCodec.Group({weight: weight, members: members});
    }

    // ---- round trip ----

    function test_BuildThenParseRoundTripsMinimalTwoGroupUniverse() public view {
        // MIN_GROUPS floor -- the smallest valid universe is 2 single-member groups.
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 2e5); // 2bps, ADR-0008 default
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps, uint32 parsedMaxDeviationBps) =
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
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 2e5, 5e7); // 5% circuit breaker
        (,, uint32 parsedMaxDeviationBps) = this._callParse(args);

        assertEq(parsedMaxDeviationBps, 5e7);
    }

    function test_BuildThenParseRoundTripsUnequalWeights() public view {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](3);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.3e18, TOKEN_B, FEED_B);
        groups[2] = _singleMemberGroup(0.2e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 0);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps,) = this._callParse(args);

        assertEq(parsed.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(parsed[i].members[0].token, groups[i].members[0].token);
            assertEq(parsed[i].weight, groups[i].weight);
        }
        assertEq(parsedFeeBps, 0);
    }

    function test_BuildThenParseRoundTripsMultiTokenGroup() public view {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({token: TOKEN_A, feed: FEED_A, maxStaleness: STALENESS});
        members[1] = PortfolioManagerArgsCodec.Member({token: TOKEN_B, feed: FEED_B, maxStaleness: STALENESS * 2});

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.6e18, members: members});
        groups[1] = _singleMemberGroup(0.4e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 1e5);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps,) = this._callParse(args);

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
        feeBps = uint32(bound(feeBps, 0, PortfolioManagerArgsCodec.PM_BPS));
        uint256 n = bound(seed, PortfolioManagerArgsCodec.MIN_GROUPS, PortfolioManagerArgsCodec.MAX_GROUPS);

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](n);
        uint256 remaining = WAD;
        for (uint256 i = 0; i < n; i++) {
            // Last weight soaks up the remainder so the set always sums to exactly WAD.
            uint256 weight = i == n - 1 ? remaining : remaining / (n - i);
            remaining -= weight;
            groups[i] = _singleMemberGroup(weight, address(uint160(0x1000 + i)), address(uint160(0x2000 + i)));
        }

        bytes memory args = PortfolioManagerArgsCodec.build(groups, feeBps);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps,) = this._callParse(args);

        assertEq(parsed.length, n);
        for (uint256 i = 0; i < n; i++) {
            assertEq(parsed[i].members[0].token, groups[i].members[0].token);
            assertEq(parsed[i].weight, groups[i].weight);
        }
        assertEq(parsedFeeBps, feeBps);
    }

    // ---- decodeTrusted: agrees with parse() on valid args, skips no data ----

    function test_BuildThenDecodeTrustedMatchesParseOnMultiTokenGroup() public view {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({token: TOKEN_A, feed: FEED_A, maxStaleness: STALENESS});
        members[1] = PortfolioManagerArgsCodec.Member({token: TOKEN_B, feed: FEED_B, maxStaleness: STALENESS * 2});

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.6e18, members: members});
        groups[1] = _singleMemberGroup(0.4e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 1e5, 5e7);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps, uint32 parsedMaxDeviationBps) =
            this._callParse(args);
        (PortfolioManagerArgsCodec.Group[] memory decoded, uint32 decodedFeeBps, uint32 decodedMaxDeviationBps) =
            this._callDecodeTrusted(args);

        assertEq(decoded.length, parsed.length);
        for (uint256 i = 0; i < parsed.length; i++) {
            assertEq(decoded[i].weight, parsed[i].weight);
            assertEq(decoded[i].members.length, parsed[i].members.length);
            for (uint256 j = 0; j < parsed[i].members.length; j++) {
                assertEq(decoded[i].members[j].token, parsed[i].members[j].token);
                assertEq(decoded[i].members[j].feed, parsed[i].members[j].feed);
                assertEq(decoded[i].members[j].maxStaleness, parsed[i].members[j].maxStaleness);
            }
        }
        assertEq(decodedFeeBps, parsedFeeBps);
        assertEq(decodedMaxDeviationBps, parsedMaxDeviationBps);
    }

    function testFuzz_DecodeTrustedMatchesParse(uint8 seed, uint32 feeBps, uint32 maxDeviationBps) public view {
        feeBps = uint32(bound(feeBps, 0, PortfolioManagerArgsCodec.PM_BPS));
        uint256 n = bound(seed, PortfolioManagerArgsCodec.MIN_GROUPS, PortfolioManagerArgsCodec.MAX_GROUPS);

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](n);
        uint256 remaining = WAD;
        for (uint256 i = 0; i < n; i++) {
            uint256 weight = i == n - 1 ? remaining : remaining / (n - i);
            remaining -= weight;
            groups[i] = _singleMemberGroup(weight, address(uint160(0x1000 + i)), address(uint160(0x2000 + i)));
        }

        bytes memory args = PortfolioManagerArgsCodec.build(groups, feeBps, maxDeviationBps);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps, uint32 parsedMaxDeviationBps) =
            this._callParse(args);
        (PortfolioManagerArgsCodec.Group[] memory decoded, uint32 decodedFeeBps, uint32 decodedMaxDeviationBps) =
            this._callDecodeTrusted(args);

        assertEq(decoded.length, parsed.length);
        for (uint256 i = 0; i < n; i++) {
            assertEq(decoded[i].weight, parsed[i].weight);
            assertEq(decoded[i].members[0].token, parsed[i].members[0].token);
        }
        assertEq(decodedFeeBps, parsedFeeBps);
        assertEq(decodedMaxDeviationBps, parsedMaxDeviationBps);
    }

    // ---- build: validation ----

    function test_BuildRevertsOnEmptyUniverse() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](0);

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerEmptyUniverse.selector);
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnEmptyGroup() public {
        // group[1] is never reached -- group[0]'s own empty-members check reverts first --
        // it's here only so the array itself satisfies MIN_GROUPS.
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: WAD, members: new PortfolioManagerArgsCodec.Member[](0)});
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerEmptyGroup.selector, 0));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsWhenWeightsDoNotSumToWad() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.4e18, TOKEN_B, FEED_B); // sums to 0.9e18, not WAD

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerWeightsMustSumToWad.selector, 0.9e18)
        );
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnZeroWeight() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerZeroWeight.selector, 0));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnTooFewGroups() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](1);
        groups[0] = _singleMemberGroup(WAD, TOKEN_A, FEED_A);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooFewGroups.selector, 1));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnTooManyGroups() public {
        uint256 n = PortfolioManagerArgsCodec.MAX_GROUPS + 1;
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](n);
        // Values don't need to sum to WAD -- the length check reverts before the weights loop.

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooManyGroups.selector, n));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnTooManyMembers() public {
        uint256 n = PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP + 1;
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](n);
        for (uint256 i = 0; i < n; i++) {
            members[i] = PortfolioManagerArgsCodec.Member({
                token: address(uint160(0x1000 + i)), feed: address(uint160(0x2000 + i)), maxStaleness: STALENESS
            });
        }
        // group[1] is never reached -- group[0]'s own too-many-members check reverts first --
        // it's here only so the array itself satisfies MIN_GROUPS.
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: WAD, members: members});
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooManyMembers.selector, n));
        this._callBuild(groups, 0);
    }

    /// @notice Two groups, each at exactly MAX_MEMBERS_PER_GROUP members (5) -- passes every
    /// per-axis check individually (group count and each group's own member count are both
    /// within bounds) but the joint encoding is 463 bytes, over the wire format's 255-byte
    /// capacity. Without build()'s own explicit length check, this would sail through here and
    /// only fail one layer up in PortfolioManagerProgramBuilder with an opaque SafeCast overflow
    /// instead of this descriptive error.
    function test_BuildRevertsOnArgsTooLargeEvenWhenEachAxisIsWithinBounds() public {
        PortfolioManagerArgsCodec.Member[] memory members0 =
            new PortfolioManagerArgsCodec.Member[](PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP);
        PortfolioManagerArgsCodec.Member[] memory members1 =
            new PortfolioManagerArgsCodec.Member[](PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP);
        for (uint256 i = 0; i < PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP; i++) {
            members0[i] = PortfolioManagerArgsCodec.Member({
                token: address(uint160(0x1000 + i)), feed: address(uint160(0x2000 + i)), maxStaleness: STALENESS
            });
            members1[i] = PortfolioManagerArgsCodec.Member({
                token: address(uint160(0x3000 + i)), feed: address(uint160(0x4000 + i)), maxStaleness: STALENESS
            });
        }
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: members0});
        groups[1] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: members1});

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerArgsTooLarge.selector, 463));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnZeroFeedAddress() public {
        // group[1] is never reached -- group[0]'s own zero-feed check reverts first -- it's here
        // only so the array itself satisfies MIN_GROUPS.
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(WAD, TOKEN_A, address(0));
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerZeroFeedAddress.selector, TOKEN_A)
        );
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnDuplicateTokenAcrossGroups() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_B); // TOKEN_A declared twice

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerDuplicateToken.selector, TOKEN_A)
        );
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnFeeBpsAboveHundredPercent() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerArgsCodec.PortfolioManagerFeeBpsOutOfRange.selector,
                PortfolioManagerArgsCodec.PM_BPS + 1
            )
        );
        this._callBuild(groups, uint32(PortfolioManagerArgsCodec.PM_BPS + 1));
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
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerWeightsMustSumToWad.selector, 0.8e18)
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

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerZeroWeight.selector, 0));
        this._callParse(malformed);
    }

    function test_ParseRevertsOnEmptyUniverse() public {
        bytes memory malformed = abi.encodePacked(uint8(0));

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerEmptyUniverse.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTooFewGroups() public {
        // The group-count check fires right after reading the leading byte, before any group
        // body is parsed -- no further bytes needed.
        bytes memory malformed = abi.encodePacked(uint8(1));

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooFewGroups.selector, 1));
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTooManyGroups() public {
        bytes memory malformed = abi.encodePacked(uint8(PortfolioManagerArgsCodec.MAX_GROUPS + 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerArgsCodec.PortfolioManagerTooManyGroups.selector,
                PortfolioManagerArgsCodec.MAX_GROUPS + 1
            )
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTooManyMembers() public {
        // 2 groups (satisfies MIN_GROUPS) -- group[0]'s member count alone is enough to revert,
        // no member entries or a real group[1] needed.
        bytes memory malformed =
            abi.encodePacked(uint8(2), uint128(WAD), uint8(PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP + 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerArgsCodec.PortfolioManagerTooManyMembers.selector,
                PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP + 1
            )
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTruncatedGroupHeader() public {
        // Declares 2 groups (satisfies MIN_GROUPS) but only supplies 10 of the required 17
        // header bytes for the first one.
        bytes memory malformed = abi.encodePacked(uint8(2), uint80(0));

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingGroupHeader.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTruncatedMemberEntry() public {
        // Valid group header (1 member), 2 groups declared, but only 10 of the required 44
        // bytes supplied for the first member.
        bytes memory malformed = abi.encodePacked(uint8(2), uint128(WAD), uint8(1), uint80(0));

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingMemberEntry.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnZeroFeedAddress() public {
        // group[0]'s own zero-feed check reverts before group[1] would ever need to be
        // present -- 2 groups declared only to satisfy MIN_GROUPS.
        bytes memory malformed =
            abi.encodePacked(uint8(2), uint128(WAD), uint8(1), TOKEN_A, address(0), uint16(STALENESS));

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerZeroFeedAddress.selector, TOKEN_A)
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

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingFeeBps.selector);
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

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingMaxDeviationBps.selector);
        this._callParse(malformed);
    }
}
