// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Calldata} from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";
import {FixedPointMath} from "./FixedPointMath.sol";

/// @dev Matches swap-vm's own `Fee.sol` BPS convention (1e9 = 100%) so `feeBps` here reads the
///      same way as everywhere else in this codebase, not a project-specific scale.
uint256 constant PM_BPS = 1e9;

/// @title PortfolioManagerArgsCodec — packed-bytes encoding of the Portfolio Manager's
///        declared token groups, per-group target weight, oracle feeds, and protocol fee
/// @notice Real multi-token oracle-valued groups (ADR-0003): each group has 1+ members, and
///         every member is priced through its own Chainlink-style feed via `OracleAdapter` --
///         no single-token "skip the oracle" special case, so decimal normalization and price
///         conversion apply uniformly regardless of group size. Weights are per-group (shared
///         by every member), fully general (not required equal): `PRICING.md`'s formula
///         already reduces correctly at equal weights, so there is nothing to special-case
///         here for the common case.
/// @dev Lives entirely in the swapVM instruction's `args` — part of the immutable `strategy`
///      payload hashed into `strategyHash` (see `IAqua.ship`), not contract storage.
library PortfolioManagerArgsCodec {
    using Calldata for bytes;

    uint256 private constant WAD = FixedPointMath.WAD;
    /// @dev 16-byte weight + 1-byte member count precedes each group's members.
    uint256 private constant GROUP_HEADER_SIZE = 17;
    /// @dev 20-byte token + 20-byte feed + 2-byte uint16 maxStaleness (seconds) per member.
    ///      uint16 caps at ~18.2 hours -- swap-vm's own wire format (`VM.sol`'s `runLoop`)
    ///      packs a program instruction's args length into a single `uint8`, hard-capping any
    ///      one instruction's args at 255 bytes; a real multi-group, multi-member universe (e.g.
    ///      5 members across 2 groups) can only fit under that cap with the narrower field. Still
    ///      comfortably wider than any real Chainlink heartbeat.
    uint256 private constant MEMBER_ENTRY_SIZE = 42;

    struct Member {
        address token;
        address feed;
        uint256 maxStaleness;
    }

    struct Group {
        uint256 weight;
        Member[] members;
    }

    error PortfolioManagerEmptyUniverse();
    error PortfolioManagerTooManyGroups(uint256 count);
    error PortfolioManagerTooManyMembers(uint256 count);
    error PortfolioManagerEmptyGroup(uint256 groupIndex);
    error PortfolioManagerFeeBpsOutOfRange(uint32 feeBps);
    error PortfolioManagerZeroWeight(uint256 groupIndex);
    error PortfolioManagerWeightsMustSumToWad(uint256 sum);
    error PortfolioManagerZeroFeedAddress(address token);
    error PortfolioManagerMaxStalenessOutOfRange(uint256 maxStaleness);
    error PortfolioManagerDuplicateToken(address token);
    error PortfolioManagerMissingGroupCount();
    error PortfolioManagerMissingGroupHeader();
    error PortfolioManagerMissingMemberEntry();
    error PortfolioManagerMissingFeeBps();

    /// @param groups  Declared groups: each a target weight (WAD-scaled; must sum to WAD across
    ///                all groups) plus 1+ members, each priced through its own feed.
    /// @param feeBps  Protocol fee, BPS-scaled per `PM_BPS` (2bps default per ADR-0008)
    function build(Group[] memory groups, uint32 feeBps) internal pure returns (bytes memory args) {
        require(groups.length > 0, PortfolioManagerEmptyUniverse());
        require(groups.length <= type(uint8).max, PortfolioManagerTooManyGroups(groups.length));
        require(feeBps <= PM_BPS, PortfolioManagerFeeBpsOutOfRange(feeBps));

        args = abi.encodePacked(uint8(groups.length));

        uint256 sum;
        for (uint256 i = 0; i < groups.length; i++) {
            Group memory g = groups[i];
            require(g.weight > 0, PortfolioManagerZeroWeight(i));
            require(g.members.length > 0, PortfolioManagerEmptyGroup(i));
            require(g.members.length <= type(uint8).max, PortfolioManagerTooManyMembers(g.members.length));
            sum += g.weight;

            args = abi.encodePacked(args, uint128(g.weight), uint8(g.members.length));
            for (uint256 j = 0; j < g.members.length; j++) {
                Member memory m = g.members[j];
                require(m.feed != address(0), PortfolioManagerZeroFeedAddress(m.token));
                require(m.maxStaleness <= type(uint16).max, PortfolioManagerMaxStalenessOutOfRange(m.maxStaleness));
                args = abi.encodePacked(args, m.token, m.feed, uint16(m.maxStaleness));
            }
        }
        require(sum == WAD, PortfolioManagerWeightsMustSumToWad(sum));
        _requireNoDuplicateTokens(groups);

        args = abi.encodePacked(args, feeBps);
    }

    /// @dev Independently re-validates every invariant `build()` checks (weights sum to WAD,
    ///      no zero weight, no empty group, no duplicate token, no zero feed) on every parse,
    ///      not just at `build()` time — `args` is maker-supplied strategy calldata and can be
    ///      hand-crafted to bypass `build()` entirely.
    function parse(bytes calldata args) internal pure returns (Group[] memory groups, uint32 feeBps) {
        uint8 groupCount = uint8(bytes1(args.slice(0, 1, PortfolioManagerMissingGroupCount.selector)));
        require(groupCount > 0, PortfolioManagerEmptyUniverse());

        groups = new Group[](groupCount);
        uint256 offset = 1;
        uint256 sum;

        for (uint256 i = 0; i < groupCount; i++) {
            args.slice(offset, offset + GROUP_HEADER_SIZE, PortfolioManagerMissingGroupHeader.selector);
            uint256 weight = uint256(uint128(bytes16(args.slice(offset, offset + 16))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 16, offset + GROUP_HEADER_SIZE)));
            require(weight > 0, PortfolioManagerZeroWeight(i));
            require(memberCount > 0, PortfolioManagerEmptyGroup(i));
            sum += weight;
            offset += GROUP_HEADER_SIZE;

            Member[] memory members = new Member[](memberCount);
            for (uint256 j = 0; j < memberCount; j++) {
                args.slice(offset, offset + MEMBER_ENTRY_SIZE, PortfolioManagerMissingMemberEntry.selector);
                address token = address(bytes20(args.slice(offset, offset + 20)));
                address feed = address(bytes20(args.slice(offset + 20, offset + 40)));
                uint256 maxStaleness = uint256(uint16(bytes2(args.slice(offset + 40, offset + MEMBER_ENTRY_SIZE))));
                require(feed != address(0), PortfolioManagerZeroFeedAddress(token));
                members[j] = Member({token: token, feed: feed, maxStaleness: maxStaleness});
                offset += MEMBER_ENTRY_SIZE;
            }
            groups[i] = Group({weight: weight, members: members});
        }
        require(sum == WAD, PortfolioManagerWeightsMustSumToWad(sum));
        _requireNoDuplicateTokens(groups);

        feeBps = uint32(bytes4(args.slice(offset, offset + 4, PortfolioManagerMissingFeeBps.selector)));
        require(feeBps <= PM_BPS, PortfolioManagerFeeBpsOutOfRange(feeBps));
    }

    /// @notice Every member token across every group, in group/member order — the flat
    ///         "declared universe" `PortfolioManagerStrategyFactory` cross-checks against
    ///         `ship()`'s own `tokens` array, and `PortfolioManagerSwap`'s group lookup scans.
    function flattenTokens(Group[] memory groups) internal pure returns (address[] memory tokens) {
        uint256 total;
        for (uint256 i = 0; i < groups.length; i++) {
            total += groups[i].members.length;
        }
        tokens = new address[](total);
        uint256 k;
        for (uint256 i = 0; i < groups.length; i++) {
            for (uint256 j = 0; j < groups[i].members.length; j++) {
                tokens[k++] = groups[i].members[j].token;
            }
        }
    }

    /// @dev A token declared in two groups would make `PortfolioManagerSwap`'s group lookup
    ///      ambiguous (which group's weight applies?) — rejected outright rather than defined
    ///      as "first match wins."
    function _requireNoDuplicateTokens(Group[] memory groups) private pure {
        address[] memory tokens = flattenTokens(groups);
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                if (tokens[i] == tokens[j]) revert PortfolioManagerDuplicateToken(tokens[i]);
            }
        }
    }
}
