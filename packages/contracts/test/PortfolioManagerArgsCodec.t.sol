// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";

/// @notice Tests the encoding layer only (build/parse/decodeTrusted) -- indices are plain
///         uint16s here, never resolved through a real registry. Resolution (tokenIndex/
///         feedIndex -> address) is tested where it actually happens: PortfolioManagerSwap.t.sol
///         and PortfolioManagerStrategyValidator.t.sol, both of which need real deployed
///         registries.
contract PortfolioManagerArgsCodecTest is Test {
    uint256 constant WAD = 1e18;

    // Index 0 is reserved (PortfolioManagerZeroTokenIndex / numeraire) -- every token index here
    // starts at 1, every feed index at 1 unless a test specifically wants the numeraire sentinel.
    uint16 constant TOKEN_A = 1;
    uint16 constant TOKEN_B = 2;
    uint16 constant TOKEN_C = 3;
    uint16 constant FEED_A = 10;
    uint16 constant FEED_B = 11;
    uint16 constant FEED_C = 12;
    uint16 constant NUMERAIRE = 0;

    // See FixedPointMath.t.sol for why internal pure library calls need an external wrapper
    // for `vm.expectRevert` to intercept the revert at the right call depth.
    function _callBuild(PortfolioManagerArgsCodec.Group[] memory groups, uint32 feeBps)
        external
        pure
        returns (bytes memory)
    {
        return PortfolioManagerArgsCodec.build(groups, feeBps);
    }

    function _callBuildWithBridges(
        PortfolioManagerArgsCodec.Group[] memory groups,
        uint32 feeBps,
        uint32 maxDeviationBps,
        PortfolioManagerArgsCodec.Bridge[] memory bridges
    ) external pure returns (bytes memory) {
        return PortfolioManagerArgsCodec.build(groups, feeBps, maxDeviationBps, bridges);
    }

    function _callParse(bytes calldata args)
        external
        pure
        returns (PortfolioManagerArgsCodec.Group[] memory, uint32, uint32, PortfolioManagerArgsCodec.Bridge[] memory)
    {
        return PortfolioManagerArgsCodec.parse(args);
    }

    function _callDecodeTrusted(bytes calldata args)
        external
        pure
        returns (PortfolioManagerArgsCodec.Group[] memory, uint32, uint32, PortfolioManagerArgsCodec.Bridge[] memory)
    {
        return PortfolioManagerArgsCodec.decodeTrusted(args);
    }

    function _singleMemberGroup(uint256 weight, uint16 tokenIndex, uint16 feedIndex)
        private
        pure
        returns (PortfolioManagerArgsCodec.Group memory)
    {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](1);
        members[0] = PortfolioManagerArgsCodec.Member({tokenIndex: tokenIndex, feedIndex: feedIndex});
        return PortfolioManagerArgsCodec.Group({weight: weight, members: members});
    }

    // ---- round trip ----

    function test_BuildThenParseRoundTripsMinimalTwoGroupUniverse() public view {
        // MIN_GROUPS floor -- the smallest valid universe is 2 single-member groups.
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 5e6); // 0.5%, MIN_FEE_BPS
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps, uint32 parsedMaxDeviationBps,) =
            this._callParse(args);

        assertEq(parsed.length, 2);
        assertEq(parsed[0].weight, 0.5e18);
        assertEq(parsed[0].members.length, 1);
        assertEq(parsed[0].members[0].tokenIndex, TOKEN_A);
        assertEq(parsed[0].members[0].feedIndex, FEED_A);
        assertEq(parsed[1].weight, 0.5e18);
        assertEq(parsedFeeBps, 5e6);
        assertEq(parsedMaxDeviationBps, 0);
    }

    function test_BuildThenParseRoundTripsMaxDeviationBps() public view {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 5e6, 5e7); // 5% circuit breaker
        (,, uint32 parsedMaxDeviationBps,) = this._callParse(args);

        assertEq(parsedMaxDeviationBps, 5e7);
    }

    function test_BuildThenParseRoundTripsUnequalWeights() public view {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](3);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.3e18, TOKEN_B, FEED_B);
        groups[2] = _singleMemberGroup(0.2e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 5e6);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps,,) = this._callParse(args);

        assertEq(parsed.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(parsed[i].members[0].tokenIndex, groups[i].members[0].tokenIndex);
            assertEq(parsed[i].weight, groups[i].weight);
        }
        assertEq(parsedFeeBps, 5e6);
    }

    function test_BuildThenParseRoundTripsMultiTokenGroup() public view {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({tokenIndex: TOKEN_A, feedIndex: FEED_A});
        members[1] = PortfolioManagerArgsCodec.Member({tokenIndex: TOKEN_B, feedIndex: FEED_B});

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.6e18, members: members});
        groups[1] = _singleMemberGroup(0.4e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 5e6);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps,,) = this._callParse(args);

        assertEq(parsed.length, 2);
        assertEq(parsed[0].weight, 0.6e18);
        assertEq(parsed[0].members.length, 2);
        assertEq(parsed[0].members[0].tokenIndex, TOKEN_A);
        assertEq(parsed[0].members[0].feedIndex, FEED_A);
        assertEq(parsed[0].members[1].tokenIndex, TOKEN_B);
        assertEq(parsed[0].members[1].feedIndex, FEED_B);
        assertEq(parsed[1].weight, 0.4e18);
        assertEq(parsedFeeBps, 5e6);
    }

    function testFuzz_BuildThenParseRoundTrips(uint8 seed, uint32 feeBps) public view {
        feeBps = uint32(bound(feeBps, PortfolioManagerArgsCodec.MIN_FEE_BPS, PortfolioManagerArgsCodec.PM_BPS));
        uint256 n = bound(seed, PortfolioManagerArgsCodec.MIN_GROUPS, PortfolioManagerArgsCodec.MAX_GROUPS);

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](n);
        uint256 remaining = WAD;
        for (uint256 i = 0; i < n; i++) {
            // Last weight soaks up the remainder so the set always sums to exactly WAD.
            uint256 weight = i == n - 1 ? remaining : remaining / (n - i);
            remaining -= weight;
            // casting to 'uint16' is safe because n is bounded by MAX_GROUPS, far under 2**16
            // forge-lint: disable-next-line(unsafe-typecast)
            groups[i] = _singleMemberGroup(weight, uint16(1 + i), uint16(10 + i));
        }

        bytes memory args = PortfolioManagerArgsCodec.build(groups, feeBps);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps,,) = this._callParse(args);

        assertEq(parsed.length, n);
        for (uint256 i = 0; i < n; i++) {
            assertEq(parsed[i].members[0].tokenIndex, groups[i].members[0].tokenIndex);
            // Weight round-trips through PM_BPS scale (1e9), not WAD -- exact for a weight
            // that's already a multiple of 1e9, off by up to n * 1e9 (worst case, all of it
            // landing on the last group) otherwise. That's ~1e-9 relative error, far inside any
            // real allocation's precision needs.
            assertApproxEqAbs(parsed[i].weight, groups[i].weight, n * 1e9);
        }
        assertEq(parsedFeeBps, feeBps);
    }

    // ---- decodeTrusted: agrees with parse() on valid args, skips no data ----

    function test_BuildThenDecodeTrustedMatchesParseOnMultiTokenGroup() public view {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({tokenIndex: TOKEN_A, feedIndex: FEED_A});
        members[1] = PortfolioManagerArgsCodec.Member({tokenIndex: TOKEN_B, feedIndex: FEED_B});

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.6e18, members: members});
        groups[1] = _singleMemberGroup(0.4e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 5e6, 5e7);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps, uint32 parsedMaxDeviationBps,) =
            this._callParse(args);
        (PortfolioManagerArgsCodec.Group[] memory decoded, uint32 decodedFeeBps, uint32 decodedMaxDeviationBps,) =
            this._callDecodeTrusted(args);

        assertEq(decoded.length, parsed.length);
        for (uint256 i = 0; i < parsed.length; i++) {
            assertEq(decoded[i].weight, parsed[i].weight);
            assertEq(decoded[i].members.length, parsed[i].members.length);
            for (uint256 j = 0; j < parsed[i].members.length; j++) {
                assertEq(decoded[i].members[j].tokenIndex, parsed[i].members[j].tokenIndex);
                assertEq(decoded[i].members[j].feedIndex, parsed[i].members[j].feedIndex);
            }
        }
        assertEq(decodedFeeBps, parsedFeeBps);
        assertEq(decodedMaxDeviationBps, parsedMaxDeviationBps);
    }

    function testFuzz_DecodeTrustedMatchesParse(uint8 seed, uint32 feeBps, uint32 maxDeviationBps) public view {
        feeBps = uint32(bound(feeBps, PortfolioManagerArgsCodec.MIN_FEE_BPS, PortfolioManagerArgsCodec.PM_BPS));
        uint256 n = bound(seed, PortfolioManagerArgsCodec.MIN_GROUPS, PortfolioManagerArgsCodec.MAX_GROUPS);

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](n);
        uint256 remaining = WAD;
        for (uint256 i = 0; i < n; i++) {
            uint256 weight = i == n - 1 ? remaining : remaining / (n - i);
            remaining -= weight;
            // casting to 'uint16' is safe because n is bounded by MAX_GROUPS, far under 2**16
            // forge-lint: disable-next-line(unsafe-typecast)
            groups[i] = _singleMemberGroup(weight, uint16(1 + i), uint16(10 + i));
        }

        bytes memory args = PortfolioManagerArgsCodec.build(groups, feeBps, maxDeviationBps);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps, uint32 parsedMaxDeviationBps,) =
            this._callParse(args);
        (PortfolioManagerArgsCodec.Group[] memory decoded, uint32 decodedFeeBps, uint32 decodedMaxDeviationBps,) =
            this._callDecodeTrusted(args);

        assertEq(decoded.length, parsed.length);
        for (uint256 i = 0; i < n; i++) {
            assertEq(decoded[i].weight, parsed[i].weight);
            assertEq(decoded[i].members[0].tokenIndex, parsed[i].members[0].tokenIndex);
        }
        assertEq(decodedFeeBps, parsedFeeBps);
        assertEq(decodedMaxDeviationBps, parsedMaxDeviationBps);
    }

    // ---- build: validation ----

    function test_BuildRevertsOnEmptyUniverse() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](0);

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerEmptyUniverse.selector);
        this._callBuild(groups, 5e6);
    }

    function test_BuildRevertsOnEmptyGroup() public {
        // group[1] is never reached -- group[0]'s own empty-members check reverts first --
        // it's here only so the array itself satisfies MIN_GROUPS.
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: WAD, members: new PortfolioManagerArgsCodec.Member[](0)});
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerEmptyGroup.selector, 0));
        this._callBuild(groups, 5e6);
    }

    function test_BuildRevertsWhenWeightsDoNotSumToWad() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.4e18, TOKEN_B, FEED_B); // sums to 0.9e18, not WAD

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerWeightsMustSumToWad.selector, 0.9e18)
        );
        this._callBuild(groups, 5e6);
    }

    function test_BuildRevertsOnZeroWeight() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerZeroWeight.selector, 0));
        this._callBuild(groups, 5e6);
    }

    function test_BuildRevertsOnTooFewGroups() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](1);
        groups[0] = _singleMemberGroup(WAD, TOKEN_A, FEED_A);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooFewGroups.selector, 1));
        this._callBuild(groups, 5e6);
    }

    function test_BuildRevertsOnTooManyGroups() public {
        uint256 n = PortfolioManagerArgsCodec.MAX_GROUPS + 1;
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](n);
        // Values don't need to sum to WAD -- the length check reverts before the weights loop.

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooManyGroups.selector, n));
        this._callBuild(groups, 5e6);
    }

    function test_BuildRevertsOnTooManyMembers() public {
        uint256 n = PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP + 1;
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](n);
        for (uint256 i = 0; i < n; i++) {
            // casting to 'uint16' is safe because n is MAX_MEMBERS_PER_GROUP + 1, far under 2**16
            // forge-lint: disable-next-line(unsafe-typecast)
            members[i] = PortfolioManagerArgsCodec.Member({tokenIndex: uint16(1 + i), feedIndex: uint16(10 + i)});
        }
        // group[1] is never reached -- group[0]'s own too-many-members check reverts first --
        // it's here only so the array itself satisfies MIN_GROUPS.
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: WAD, members: members});
        groups[1] = _singleMemberGroup(WAD, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooManyMembers.selector, n));
        this._callBuild(groups, 5e6);
    }

    /// @notice Valid group/member counts can still exceed the 255-byte encoding limit --
    ///         though with the 4-byte member entry (BLEUDEV-412/ADR-0018) this now needs far
    ///         more groups/members than it used to to actually hit the ceiling.
    function test_BuildRevertsOnArgsTooLargeEvenWhenEachAxisIsWithinBounds() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](4);
        for (uint256 i = 0; i < 4; i++) {
            PortfolioManagerArgsCodec.Member[] memory members =
                new PortfolioManagerArgsCodec.Member[](PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP);
            for (uint256 j = 0; j < PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP; j++) {
                members[j] = PortfolioManagerArgsCodec.Member({
                    // casting to 'uint16' is safe -- i < 4 and j < MAX_MEMBERS_PER_GROUP, far under 2**16
                    // forge-lint: disable-next-line(unsafe-typecast)
                    tokenIndex: uint16(1 + i * 10 + j),
                    feedIndex: uint16(100 + i * 10 + j)
                });
            }
            groups[i] = PortfolioManagerArgsCodec.Group({weight: 0.25e18, members: members});
        }

        // 1 (count) + 4 * (5 header + 5*4 members) + 1 (bridgeCount) + 8 (fee+dev) = 1+4*25+1+8=110.
        // Bump bridges to push it over: all 6 distinct pairs among 4 groups, 25 bytes each = 150 more.
        PortfolioManagerArgsCodec.Bridge[] memory bridges =
            new PortfolioManagerArgsCodec.Bridge[](PortfolioManagerArgsCodec.MAX_BRIDGES);
        uint8[2][6] memory pairs = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]];
        for (uint256 i = 0; i < PortfolioManagerArgsCodec.MAX_BRIDGES; i++) {
            bridges[i] = PortfolioManagerArgsCodec.Bridge({
                // casting to 'uint160' is safe because i is bounded by MAX_BRIDGES, far under 2**160
                // forge-lint: disable-next-line(unsafe-typecast)
                groupA: pairs[i][0],
                groupB: pairs[i][1],
                feed: address(uint160(0x9000 + i)),
                maxStaleness: 3600
            });
        }

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerArgsTooLarge.selector, 260));
        this._callBuildWithBridges(groups, 5e6, 0, bridges);
    }

    /// @dev Feed index 0 designates its own group's numeraire (BLEUDEV-412/ADR-0017) -- it no
    ///      longer rejects outright, it just round-trips with feedIndex == 0.
    function test_BuildThenParseRoundTripsOneNumeraireMember() public view {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, NUMERAIRE);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 5e6);
        (PortfolioManagerArgsCodec.Group[] memory parsed,,,) = this._callParse(args);

        assertEq(parsed[0].members[0].feedIndex, NUMERAIRE);
        assertEq(parsed[1].members[0].feedIndex, FEED_B);
    }

    /// @dev The numeraire check is scoped per group (BLEUDEV-412/ADR-0017) -- two different
    ///      groups each picking their own zero-feed member is not ambiguous, since every
    ///      group's own value is still well-defined. Each group ends up denominated in a
    ///      different unit; nothing here requires them to match.
    function test_BuildThenParseRoundTripsOneNumeraireMemberPerGroup() public view {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, NUMERAIRE);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, NUMERAIRE);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 5e6);
        (PortfolioManagerArgsCodec.Group[] memory parsed,,,) = this._callParse(args);

        assertEq(parsed[0].members[0].feedIndex, NUMERAIRE);
        assertEq(parsed[1].members[0].feedIndex, NUMERAIRE);
    }

    function test_BuildRevertsOnMultipleNumeraireMembersInSameGroup() public {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({tokenIndex: TOKEN_A, feedIndex: NUMERAIRE});
        members[1] = PortfolioManagerArgsCodec.Member({tokenIndex: TOKEN_B, feedIndex: NUMERAIRE});

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: members});
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_C, FEED_C);

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerMultipleNumeraireMembers.selector, 0)
        );
        this._callBuild(groups, 5e6);
    }

    function test_BuildRevertsOnZeroTokenIndex() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, 0, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerZeroTokenIndex.selector, 0, 0));
        this._callBuild(groups, 5e6);
    }

    // ---- bridges (ADR-0017): feeds between groups whose units differ, for the ship-time
    // deviation check only. Bridge entries still carry raw addresses, not registry indices --
    // a strategy registers at most a handful, nowhere near the per-member budget pressure. ----

    address constant BRIDGE_FEED = address(0xFEEDC);

    function _twoGroupUniverse() private pure returns (PortfolioManagerArgsCodec.Group[] memory groups) {
        groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_B, FEED_B);
    }

    function test_BuildThenParseRoundTripsOneBridge() public view {
        PortfolioManagerArgsCodec.Group[] memory groups = _twoGroupUniverse();
        PortfolioManagerArgsCodec.Bridge[] memory bridges = new PortfolioManagerArgsCodec.Bridge[](1);
        bridges[0] = PortfolioManagerArgsCodec.Bridge({groupA: 0, groupB: 1, feed: BRIDGE_FEED, maxStaleness: 3600});

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 5e6, 0, bridges);
        (,,, PortfolioManagerArgsCodec.Bridge[] memory parsed) = this._callParse(args);

        assertEq(parsed.length, 1);
        assertEq(parsed[0].groupA, 0);
        assertEq(parsed[0].groupB, 1);
        assertEq(parsed[0].feed, BRIDGE_FEED);
        assertEq(parsed[0].maxStaleness, 3600);
    }

    /// @dev A 2-group universe with no bridges round-trips exactly as before -- the new section
    ///      is an empty, 1-byte count, not a required-but-unused field.
    function test_BuildThenParseRoundTripsNoBridges() public view {
        bytes memory args = PortfolioManagerArgsCodec.build(_twoGroupUniverse(), 5e6);
        (,,, PortfolioManagerArgsCodec.Bridge[] memory parsed) = this._callParse(args);
        assertEq(parsed.length, 0);
    }

    function test_BuildRevertsOnBridgeGroupIndexOutOfRange() public {
        PortfolioManagerArgsCodec.Bridge[] memory bridges = new PortfolioManagerArgsCodec.Bridge[](1);
        bridges[0] = PortfolioManagerArgsCodec.Bridge({groupA: 0, groupB: 2, feed: BRIDGE_FEED, maxStaleness: 3600});

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerBridgeInvalidGroupIndex.selector, 2)
        );
        this._callBuildWithBridges(_twoGroupUniverse(), 5e6, 0, bridges);
    }

    function test_BuildRevertsOnBridgeSameGroup() public {
        PortfolioManagerArgsCodec.Bridge[] memory bridges = new PortfolioManagerArgsCodec.Bridge[](1);
        bridges[0] = PortfolioManagerArgsCodec.Bridge({groupA: 0, groupB: 0, feed: BRIDGE_FEED, maxStaleness: 3600});

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerBridgeSameGroup.selector, 0));
        this._callBuildWithBridges(_twoGroupUniverse(), 5e6, 0, bridges);
    }

    function test_BuildRevertsOnBridgeZeroFeedAddress() public {
        PortfolioManagerArgsCodec.Bridge[] memory bridges = new PortfolioManagerArgsCodec.Bridge[](1);
        bridges[0] = PortfolioManagerArgsCodec.Bridge({groupA: 0, groupB: 1, feed: address(0), maxStaleness: 3600});

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerBridgeZeroFeedAddress.selector);
        this._callBuildWithBridges(_twoGroupUniverse(), 5e6, 0, bridges);
    }

    /// @dev Registering a pair twice is ambiguous regardless of which side is groupA/groupB in
    ///      each entry.
    function test_BuildRevertsOnDuplicateBridgeRegardlessOfSide() public {
        PortfolioManagerArgsCodec.Bridge[] memory bridges = new PortfolioManagerArgsCodec.Bridge[](2);
        bridges[0] = PortfolioManagerArgsCodec.Bridge({groupA: 0, groupB: 1, feed: BRIDGE_FEED, maxStaleness: 3600});
        bridges[1] = PortfolioManagerArgsCodec.Bridge({groupA: 1, groupB: 0, feed: BRIDGE_FEED, maxStaleness: 3600});

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerDuplicateBridge.selector, 1, 0)
        );
        this._callBuildWithBridges(_twoGroupUniverse(), 5e6, 0, bridges);
    }

    function test_BuildRevertsOnTooManyBridges() public {
        uint256 n = PortfolioManagerArgsCodec.MAX_BRIDGES + 1;
        PortfolioManagerArgsCodec.Bridge[] memory bridges = new PortfolioManagerArgsCodec.Bridge[](n);
        for (uint256 i = 0; i < n; i++) {
            bridges[i] = PortfolioManagerArgsCodec.Bridge({groupA: 0, groupB: 1, feed: BRIDGE_FEED, maxStaleness: 3600});
        }

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooManyBridges.selector, n));
        this._callBuildWithBridges(_twoGroupUniverse(), 5e6, 0, bridges);
    }

    function test_ParseRevertsOnMissingBridgeCount() public {
        // Valid 2-group universe (sums to WAD), but no trailing bridge-count byte.
        bytes memory malformed = abi.encodePacked(
            uint8(2), uint32(0.5e9), uint8(1), TOKEN_A, FEED_A, uint32(0.5e9), uint8(1), TOKEN_B, FEED_B
        );

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingBridgeCount.selector);
        this._callParse(malformed);
    }

    function test_BuildRevertsOnDuplicateTokenAcrossGroups() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_B); // TOKEN_A declared twice

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerDuplicateToken.selector, TOKEN_A)
        );
        this._callBuild(groups, 5e6);
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
            uint32(0.5e9),
            uint8(1),
            TOKEN_A,
            FEED_A,
            uint32(0.3e9),
            uint8(1),
            TOKEN_B,
            FEED_B,
            uint8(0) // bridgeCount
        );

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerWeightsMustSumToWad.selector, 0.8e18)
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnHandCraftedZeroWeight() public {
        // Weights [0, WAD] pass the sum check but must fail the nonzero-weight check.
        bytes memory malformed = abi.encodePacked(
            uint8(2),
            uint32(0),
            uint8(1),
            TOKEN_A,
            FEED_A,
            uint32(1e9),
            uint8(1),
            TOKEN_B,
            FEED_B,
            uint8(0) // bridgeCount
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
            abi.encodePacked(uint8(2), uint32(1e9), uint8(PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP + 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerArgsCodec.PortfolioManagerTooManyMembers.selector,
                PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP + 1
            )
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTruncatedGroupHeader() public {
        // Declares 2 groups (satisfies MIN_GROUPS) but only supplies 4 of the required 5
        // header bytes for the first one.
        bytes memory malformed = abi.encodePacked(uint8(2), uint32(0));

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingGroupHeader.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTruncatedMemberEntry() public {
        // Valid group header (1 member), 2 groups declared, but only 2 of the required 4 bytes
        // supplied for the first member.
        bytes memory malformed = abi.encodePacked(uint8(2), uint32(1e9), uint8(1), uint16(0));

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingMemberEntry.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnMultipleNumeraireMembers() public {
        // One group with two zero-feed members (weights sum to WAD) -- parse() must
        // independently reject this, not just build().
        bytes memory args = abi.encodePacked(
            uint8(2),
            uint32(0.5e9),
            uint8(2),
            TOKEN_A,
            NUMERAIRE,
            TOKEN_B,
            NUMERAIRE,
            uint32(0.5e9),
            uint8(1),
            TOKEN_C,
            FEED_C,
            uint8(0), // bridgeCount
            uint32(0),
            uint32(0)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerMultipleNumeraireMembers.selector, 0)
        );
        this._callParse(args);
    }

    function test_ParseRevertsOnMissingFeeBps() public {
        // Valid 2-group universe (sums to WAD) and an empty bridge list, but no trailing feeBps bytes.
        bytes memory malformed = abi.encodePacked(
            uint8(2),
            uint32(0.5e9),
            uint8(1),
            TOKEN_A,
            FEED_A,
            uint32(0.5e9),
            uint8(1),
            TOKEN_B,
            FEED_B,
            uint8(0) // bridgeCount
        );

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingFeeBps.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnMissingMaxDeviationBps() public {
        // Valid 2-group universe, an empty bridge list, plus feeBps, but no trailing
        // maxDeviationBps bytes.
        bytes memory malformed = abi.encodePacked(
            uint8(2),
            uint32(0.5e9),
            uint8(1),
            TOKEN_A,
            FEED_A,
            uint32(0.5e9),
            uint8(1),
            TOKEN_B,
            FEED_B,
            uint8(0), // bridgeCount
            uint32(5e6)
        );

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingMaxDeviationBps.selector);
        this._callParse(malformed);
    }
}
