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

    function _callParse(bytes calldata args) external pure returns (PortfolioManagerArgsCodec.Group[] memory, uint32) {
        return PortfolioManagerArgsCodec.parse(args);
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

    function test_BuildThenParseRoundTripsSingleToken() public view {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](1);
        groups[0] = _singleMemberGroup(WAD, TOKEN_A, FEED_A);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 2e5); // 2bps, ADR-0008 default
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps) = this._callParse(args);

        assertEq(parsed.length, 1);
        assertEq(parsed[0].weight, WAD);
        assertEq(parsed[0].members.length, 1);
        assertEq(parsed[0].members[0].token, TOKEN_A);
        assertEq(parsed[0].members[0].feed, FEED_A);
        assertEq(parsed[0].members[0].maxStaleness, STALENESS);
        assertEq(parsedFeeBps, 2e5);
    }

    function test_BuildThenParseRoundTripsUnequalWeights() public view {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](3);
        groups[0] = _singleMemberGroup(0.5e18, TOKEN_A, FEED_A);
        groups[1] = _singleMemberGroup(0.3e18, TOKEN_B, FEED_B);
        groups[2] = _singleMemberGroup(0.2e18, TOKEN_C, FEED_C);

        bytes memory args = PortfolioManagerArgsCodec.build(groups, 0);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps) = this._callParse(args);

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
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps) = this._callParse(args);

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
        uint256 n = bound(seed, 1, 10);

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](n);
        uint256 remaining = WAD;
        for (uint256 i = 0; i < n; i++) {
            // Last weight soaks up the remainder so the set always sums to exactly WAD.
            uint256 weight = i == n - 1 ? remaining : remaining / (n - i);
            remaining -= weight;
            groups[i] = _singleMemberGroup(weight, address(uint160(0x1000 + i)), address(uint160(0x2000 + i)));
        }

        bytes memory args = PortfolioManagerArgsCodec.build(groups, feeBps);
        (PortfolioManagerArgsCodec.Group[] memory parsed, uint32 parsedFeeBps) = this._callParse(args);

        assertEq(parsed.length, n);
        for (uint256 i = 0; i < n; i++) {
            assertEq(parsed[i].members[0].token, groups[i].members[0].token);
            assertEq(parsed[i].weight, groups[i].weight);
        }
        assertEq(parsedFeeBps, feeBps);
    }

    // ---- build: validation ----

    function test_BuildRevertsOnEmptyUniverse() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](0);

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerEmptyUniverse.selector);
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnEmptyGroup() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](1);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: WAD, members: new PortfolioManagerArgsCodec.Member[](0)});

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

    function test_BuildRevertsOnTooManyGroups() public {
        uint256 n = uint256(type(uint8).max) + 1; // 256, one past the packed uint8 group-count field
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](n);
        // Values don't need to sum to WAD -- the length check reverts before the weights loop.

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooManyGroups.selector, n));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnTooManyMembers() public {
        uint256 n = uint256(type(uint8).max) + 1; // 256, one past the packed uint8 member-count field
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](n);
        for (uint256 i = 0; i < n; i++) {
            members[i] = PortfolioManagerArgsCodec.Member({
                token: address(uint160(0x1000 + i)), feed: address(uint160(0x2000 + i)), maxStaleness: STALENESS
            });
        }
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](1);
        groups[0] = PortfolioManagerArgsCodec.Group({weight: WAD, members: members});

        vm.expectRevert(abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerTooManyMembers.selector, n));
        this._callBuild(groups, 0);
    }

    function test_BuildRevertsOnZeroFeedAddress() public {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](1);
        groups[0] = _singleMemberGroup(WAD, TOKEN_A, address(0));

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
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](1);
        groups[0] = _singleMemberGroup(WAD, TOKEN_A, FEED_A);

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
        // 1 group, 1 member, weight 0.5e18 (not WAD), feeBps 0 -- crafted directly, bypassing build().
        bytes memory malformed =
            abi.encodePacked(uint8(1), uint128(0.5e18), uint8(1), TOKEN_A, FEED_A, uint16(STALENESS), uint32(0));

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerWeightsMustSumToWad.selector, 0.5e18)
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

    function test_ParseRevertsOnTruncatedGroupHeader() public {
        // Declares 1 group but only supplies 10 of the required 17 header bytes.
        bytes memory malformed = abi.encodePacked(uint8(1), uint80(0));

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingGroupHeader.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnTruncatedMemberEntry() public {
        // Valid group header (1 member) but only 10 of the required 44 bytes for it.
        bytes memory malformed = abi.encodePacked(uint8(1), uint128(WAD), uint8(1), uint80(0));

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingMemberEntry.selector);
        this._callParse(malformed);
    }

    function test_ParseRevertsOnZeroFeedAddress() public {
        bytes memory malformed =
            abi.encodePacked(uint8(1), uint128(WAD), uint8(1), TOKEN_A, address(0), uint16(STALENESS));

        vm.expectRevert(
            abi.encodeWithSelector(PortfolioManagerArgsCodec.PortfolioManagerZeroFeedAddress.selector, TOKEN_A)
        );
        this._callParse(malformed);
    }

    function test_ParseRevertsOnMissingFeeBps() public {
        // Valid single-token universe (sums to WAD) but no trailing feeBps bytes.
        bytes memory malformed = abi.encodePacked(uint8(1), uint128(WAD), uint8(1), TOKEN_A, FEED_A, uint16(STALENESS));

        vm.expectRevert(PortfolioManagerArgsCodec.PortfolioManagerMissingFeeBps.selector);
        this._callParse(malformed);
    }
}
