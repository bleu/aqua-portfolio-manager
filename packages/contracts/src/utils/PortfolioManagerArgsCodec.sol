// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Calldata} from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";
import {FixedPointMath} from "./FixedPointMath.sol";
import {OracleAdapter} from "./OracleAdapter.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title PortfolioManagerArgsCodec
/// @notice Encodes token groups, target weights, feeds, bridge feeds, the LP fee, and the
///         deviation limit.
/// @dev Configuration lives in immutable instruction arguments committed by the strategy hash.
///      Group weights may differ. Every member requires a feed except at most one per group,
///      which may use the zero address to designate it that group's own numeraire
///      (BLEUDEV-412/ADR-0017) -- see OracleAdapter.PriceFeed's doc comment. Different groups may
///      use different numeraires (or none); `Bridge` entries (ADR-0017) let the ship-time
///      deviation check compare groups whose units differ.
library PortfolioManagerArgsCodec {
    using Calldata for bytes;

    /// @dev Matches SwapVM's fee scale: 1e9 = 100%. One conventional basis point is 100_000.
    uint256 internal constant PM_BPS = 1e9;

    uint256 private constant WAD = FixedPointMath.WAD;
    /// @dev 8-byte weight + 1-byte member count precedes each group's members. A WAD-scaled
    ///      weight is always in (0, 1e18], and uint64's ~1.8e19 ceiling covers that with room to
    ///      spare -- the widest byte-aligned type that still leaves headroom under SwapVM's
    ///      255-byte argument budget once member entries need 3 bytes each for maxStaleness.
    uint256 private constant GROUP_HEADER_SIZE = 9;
    /// @dev Each member uses 20 token bytes, 20 feed bytes, and 3 maxStaleness bytes (seconds).
    ///      The uint24 age limit is 16,777,215 seconds (~194 days) -- comfortably covers the
    ///      86,400-second heartbeat of common stablecoin/LST Chainlink feeds on Base and Ethereum,
    ///      which a uint16 limit (65,535 seconds, ~18.2 hours) could not.
    uint256 private constant MEMBER_ENTRY_SIZE = 43;
    /// @dev Each bridge entry uses 1 groupA byte, 1 groupB byte, 20 feed bytes, and 3
    ///      maxStaleness bytes.
    uint256 private constant BRIDGE_ENTRY_SIZE = 25;

    /// @dev At least two groups are needed for cross-group pricing.
    ///      Shape bounds do not guarantee the 255-byte argument limit. build() checks encoded length separately.
    uint256 internal constant MIN_GROUPS = 2;
    uint256 internal constant MAX_GROUPS = 4;
    uint256 internal constant MAX_MEMBERS_PER_GROUP = 5;
    /// @dev MAX_GROUPS pairwise combinations: 4 choose 2.
    uint256 internal constant MAX_BRIDGES = 6;

    struct Member {
        address token;
        address feed;
        uint256 maxStaleness;
    }

    struct Group {
        uint256 weight;
        Member[] members;
    }

    /// @dev A live feed bridging two groups' units for the ship-time deviation check only
    ///      (ADR-0017/BLEUDEV-412) -- never consulted by swap pricing, which prices each group in
    ///      its own unit directly. `feed` quotes groupA's unit in terms of groupB's unit (how many
    ///      groupB-units equal one groupA-unit). Omit the entry entirely for a pair of groups that
    ///      already share a unit; nothing on-chain can verify that two groups actually do.
    struct Bridge {
        uint8 groupA;
        uint8 groupB;
        address feed;
        uint256 maxStaleness;
    }

    error PortfolioManagerEmptyUniverse();
    error PortfolioManagerTooFewGroups(uint256 count);
    error PortfolioManagerTooManyGroups(uint256 count);
    error PortfolioManagerTooManyMembers(uint256 count);
    error PortfolioManagerEmptyGroup(uint256 groupIndex);
    error PortfolioManagerFeeBpsOutOfRange(uint32 feeBps);
    error PortfolioManagerZeroWeight(uint256 groupIndex);
    error PortfolioManagerWeightsMustSumToWad(uint256 sum);
    /// @dev A member's feed may be the zero address, designating it its group's own numeraire
    ///      (BLEUDEV-412/ADR-0017) -- but only one per group. A second one would leave that
    ///      group's unit of account ambiguous between two different tokens.
    error PortfolioManagerMultipleNumeraireMembers(uint256 groupIndex);
    error PortfolioManagerMaxStalenessOutOfRange(uint256 maxStaleness);
    error PortfolioManagerDuplicateToken(address token);
    error PortfolioManagerMissingGroupCount();
    error PortfolioManagerMissingGroupHeader();
    error PortfolioManagerMissingMemberEntry();
    error PortfolioManagerMissingFeeBps();
    /// @dev The complete encoding exceeds SwapVM's 255-byte instruction argument limit.
    error PortfolioManagerArgsTooLarge(uint256 length);
    error PortfolioManagerMissingMaxDeviationBps();
    error PortfolioManagerTooManyBridges(uint256 count);
    error PortfolioManagerBridgeInvalidGroupIndex(uint256 groupIndex);
    error PortfolioManagerBridgeSameGroup(uint256 groupIndex);
    error PortfolioManagerBridgeZeroFeedAddress();
    /// @dev Two bridge entries for the same unordered pair of groups would leave which rate to
    ///      use ambiguous.
    error PortfolioManagerDuplicateBridge(uint256 groupA, uint256 groupB);
    error PortfolioManagerMissingBridgeCount();
    error PortfolioManagerMissingBridgeEntry();

    /// @notice Builds arguments with the deviation breaker disabled and no bridge feeds.
    function build(Group[] memory groups, uint32 feeBps) internal pure returns (bytes memory args) {
        return build(groups, feeBps, 0, new Bridge[](0));
    }

    /// @notice Builds arguments with no bridge feeds -- every group must already share a unit.
    function build(Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps)
        internal
        pure
        returns (bytes memory args)
    {
        return build(groups, feeBps, maxDeviationBps, new Bridge[](0));
    }

    /// @param groups Groups with WAD-scaled weights summing to WAD and per-member feeds.
    /// @param feeBps LP curve fee, scaled by PM_BPS.
    /// @param maxDeviationBps Deviation limit, scaled by PM_BPS. Zero disables both deviation checks.
    /// @param bridges Live feeds bridging groups whose units differ, for the ship-time deviation
    ///        check only (ADR-0017). Omit a pair that already shares a unit.
    function build(Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps, Bridge[] memory bridges)
        internal
        pure
        returns (bytes memory args)
    {
        require(groups.length > 0, PortfolioManagerEmptyUniverse());
        require(groups.length >= MIN_GROUPS, PortfolioManagerTooFewGroups(groups.length));
        require(groups.length <= MAX_GROUPS, PortfolioManagerTooManyGroups(groups.length));
        require(feeBps <= PM_BPS, PortfolioManagerFeeBpsOutOfRange(feeBps));

        args = abi.encodePacked(uint8(groups.length));

        uint256 sum;
        for (uint256 i = 0; i < groups.length; i++) {
            Group memory g = groups[i];
            require(g.weight > 0, PortfolioManagerZeroWeight(i));
            require(g.members.length > 0, PortfolioManagerEmptyGroup(i));
            require(g.members.length <= MAX_MEMBERS_PER_GROUP, PortfolioManagerTooManyMembers(g.members.length));
            sum += g.weight;

            args = abi.encodePacked(args, uint64(g.weight), uint8(g.members.length));
            uint256 numeraireCount;
            for (uint256 j = 0; j < g.members.length; j++) {
                Member memory m = g.members[j];
                if (m.feed == address(0)) numeraireCount++;
                require(m.maxStaleness <= type(uint24).max, PortfolioManagerMaxStalenessOutOfRange(m.maxStaleness));
                args = abi.encodePacked(args, m.token, m.feed, uint24(m.maxStaleness));
            }
            require(numeraireCount <= 1, PortfolioManagerMultipleNumeraireMembers(i));
        }
        require(sum == WAD, PortfolioManagerWeightsMustSumToWad(sum));
        _requireNoDuplicateTokens(groups);

        require(bridges.length <= MAX_BRIDGES, PortfolioManagerTooManyBridges(bridges.length));
        args = abi.encodePacked(args, uint8(bridges.length));
        for (uint256 i = 0; i < bridges.length; i++) {
            Bridge memory b = bridges[i];
            require(b.groupA < groups.length, PortfolioManagerBridgeInvalidGroupIndex(b.groupA));
            require(b.groupB < groups.length, PortfolioManagerBridgeInvalidGroupIndex(b.groupB));
            require(b.groupA != b.groupB, PortfolioManagerBridgeSameGroup(b.groupA));
            require(b.feed != address(0), PortfolioManagerBridgeZeroFeedAddress());
            require(b.maxStaleness <= type(uint24).max, PortfolioManagerMaxStalenessOutOfRange(b.maxStaleness));
            _requireNoDuplicateBridge(bridges, i);
            args = abi.encodePacked(args, b.groupA, b.groupB, b.feed, uint24(b.maxStaleness));
        }

        args = abi.encodePacked(args, feeBps, maxDeviationBps);
        require(args.length <= type(uint8).max, PortfolioManagerArgsTooLarge(args.length));
    }

    /// @dev Validates group structure, weights, token uniqueness, feeds, bridges, and fees in
    ///      caller-supplied arguments.
    function parse(bytes calldata args)
        internal
        pure
        returns (Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps, Bridge[] memory bridges)
    {
        uint8 groupCount = uint8(bytes1(args.slice(0, 1, PortfolioManagerMissingGroupCount.selector)));
        require(groupCount > 0, PortfolioManagerEmptyUniverse());
        require(groupCount >= MIN_GROUPS, PortfolioManagerTooFewGroups(groupCount));
        require(groupCount <= MAX_GROUPS, PortfolioManagerTooManyGroups(groupCount));

        groups = new Group[](groupCount);
        uint256 offset = 1;
        uint256 sum;

        for (uint256 i = 0; i < groupCount; i++) {
            args.slice(offset, offset + GROUP_HEADER_SIZE, PortfolioManagerMissingGroupHeader.selector);
            uint256 weight = uint256(uint64(bytes8(args.slice(offset, offset + 8))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 8, offset + GROUP_HEADER_SIZE)));
            require(weight > 0, PortfolioManagerZeroWeight(i));
            require(memberCount > 0, PortfolioManagerEmptyGroup(i));
            require(memberCount <= MAX_MEMBERS_PER_GROUP, PortfolioManagerTooManyMembers(memberCount));
            sum += weight;
            offset += GROUP_HEADER_SIZE;

            Member[] memory members = new Member[](memberCount);
            uint256 numeraireCount;
            for (uint256 j = 0; j < memberCount; j++) {
                args.slice(offset, offset + MEMBER_ENTRY_SIZE, PortfolioManagerMissingMemberEntry.selector);
                address token = address(bytes20(args.slice(offset, offset + 20)));
                address feed = address(bytes20(args.slice(offset + 20, offset + 40)));
                uint256 maxStaleness = uint256(uint24(bytes3(args.slice(offset + 40, offset + MEMBER_ENTRY_SIZE))));
                if (feed == address(0)) numeraireCount++;
                members[j] = Member({token: token, feed: feed, maxStaleness: maxStaleness});
                offset += MEMBER_ENTRY_SIZE;
            }
            require(numeraireCount <= 1, PortfolioManagerMultipleNumeraireMembers(i));
            groups[i] = Group({weight: weight, members: members});
        }
        require(sum == WAD, PortfolioManagerWeightsMustSumToWad(sum));
        _requireNoDuplicateTokens(groups);

        uint256 afterBridges;
        (bridges, afterBridges) = _parseBridges(args, offset, groups.length);
        offset = afterBridges;

        feeBps = uint32(bytes4(args.slice(offset, offset + 4, PortfolioManagerMissingFeeBps.selector)));
        require(feeBps <= PM_BPS, PortfolioManagerFeeBpsOutOfRange(feeBps));
        offset += 4;

        maxDeviationBps =
            uint32(bytes4(args.slice(offset, offset + 4, PortfolioManagerMissingMaxDeviationBps.selector)));
    }

    /// @dev Split out of parse() -- keeping the bridge section's own calldata-slicing locals out
    ///      of parse()'s frame is what keeps parse() (and its callers, under via-IR) under
    ///      Solidity's stack-depth limit once a fourth decoded section was added.
    function _parseBridges(bytes calldata args, uint256 offset, uint256 groupCount)
        private
        pure
        returns (Bridge[] memory bridges, uint256 newOffset)
    {
        uint8 bridgeCount = uint8(bytes1(args.slice(offset, offset + 1, PortfolioManagerMissingBridgeCount.selector)));
        require(bridgeCount <= MAX_BRIDGES, PortfolioManagerTooManyBridges(bridgeCount));
        offset += 1;
        bridges = new Bridge[](bridgeCount);
        for (uint256 i = 0; i < bridgeCount; i++) {
            args.slice(offset, offset + BRIDGE_ENTRY_SIZE, PortfolioManagerMissingBridgeEntry.selector);
            uint8 groupA = uint8(bytes1(args.slice(offset, offset + 1)));
            uint8 groupB = uint8(bytes1(args.slice(offset + 1, offset + 2)));
            address feed = address(bytes20(args.slice(offset + 2, offset + 22)));
            uint256 maxStaleness = uint256(uint24(bytes3(args.slice(offset + 22, offset + BRIDGE_ENTRY_SIZE))));
            require(groupA < groupCount, PortfolioManagerBridgeInvalidGroupIndex(groupA));
            require(groupB < groupCount, PortfolioManagerBridgeInvalidGroupIndex(groupB));
            require(groupA != groupB, PortfolioManagerBridgeSameGroup(groupA));
            require(feed != address(0), PortfolioManagerBridgeZeroFeedAddress());
            bridges[i] = Bridge({groupA: groupA, groupB: groupB, feed: feed, maxStaleness: maxStaleness});
            _requireNoDuplicateBridge(bridges, i);
            offset += BRIDGE_ENTRY_SIZE;
        }
        newOffset = offset;
    }

    /// @notice Decodes arguments without structural validation.
    /// @dev Call only after these exact bytes pass parse(). PM requires validator attestation before this call.
    ///      Never use for untrusted or unattested arguments.
    function decodeTrusted(bytes calldata args)
        internal
        pure
        returns (Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps, Bridge[] memory bridges)
    {
        uint8 groupCount = uint8(bytes1(args.slice(0, 1)));
        groups = new Group[](groupCount);
        uint256 offset = 1;

        for (uint256 i = 0; i < groupCount; i++) {
            uint256 weight = uint256(uint64(bytes8(args.slice(offset, offset + 8))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 8, offset + GROUP_HEADER_SIZE)));
            offset += GROUP_HEADER_SIZE;

            Member[] memory members = new Member[](memberCount);
            for (uint256 j = 0; j < memberCount; j++) {
                address token = address(bytes20(args.slice(offset, offset + 20)));
                address feed = address(bytes20(args.slice(offset + 20, offset + 40)));
                uint256 maxStaleness = uint256(uint24(bytes3(args.slice(offset + 40, offset + MEMBER_ENTRY_SIZE))));
                members[j] = Member({token: token, feed: feed, maxStaleness: maxStaleness});
                offset += MEMBER_ENTRY_SIZE;
            }
            groups[i] = Group({weight: weight, members: members});
        }

        uint8 bridgeCount = uint8(bytes1(args.slice(offset, offset + 1)));
        offset += 1;
        bridges = new Bridge[](bridgeCount);
        for (uint256 i = 0; i < bridgeCount; i++) {
            uint8 groupA = uint8(bytes1(args.slice(offset, offset + 1)));
            uint8 groupB = uint8(bytes1(args.slice(offset + 1, offset + 2)));
            address feed = address(bytes20(args.slice(offset + 2, offset + 22)));
            uint256 maxStaleness = uint256(uint24(bytes3(args.slice(offset + 22, offset + BRIDGE_ENTRY_SIZE))));
            bridges[i] = Bridge({groupA: groupA, groupB: groupB, feed: feed, maxStaleness: maxStaleness});
            offset += BRIDGE_ENTRY_SIZE;
        }

        feeBps = uint32(bytes4(args.slice(offset, offset + 4)));
        offset += 4;
        maxDeviationBps = uint32(bytes4(args.slice(offset, offset + 4)));
    }

    /// @notice Decodes arguments for swap pricing only -- skips the bridge section entirely
    ///         instead of materializing a `Bridge[]`, since swap pricing never consults one
    ///         (ADR-0017: a Bridge only adjusts the ship-time deviation check). Call only after
    ///         these exact bytes pass parse().
    function decodeTrustedForSwap(bytes calldata args)
        internal
        pure
        returns (Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps)
    {
        uint8 groupCount = uint8(bytes1(args.slice(0, 1)));
        groups = new Group[](groupCount);
        uint256 offset = 1;

        for (uint256 i = 0; i < groupCount; i++) {
            uint256 weight = uint256(uint64(bytes8(args.slice(offset, offset + 8))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 8, offset + GROUP_HEADER_SIZE)));
            offset += GROUP_HEADER_SIZE;

            Member[] memory members = new Member[](memberCount);
            for (uint256 j = 0; j < memberCount; j++) {
                address token = address(bytes20(args.slice(offset, offset + 20)));
                address feed = address(bytes20(args.slice(offset + 20, offset + 40)));
                uint256 maxStaleness = uint256(uint24(bytes3(args.slice(offset + 40, offset + MEMBER_ENTRY_SIZE))));
                members[j] = Member({token: token, feed: feed, maxStaleness: maxStaleness});
                offset += MEMBER_ENTRY_SIZE;
            }
            groups[i] = Group({weight: weight, members: members});
        }

        uint8 bridgeCount = uint8(bytes1(args.slice(offset, offset + 1)));
        offset += 1 + bridgeCount * BRIDGE_ENTRY_SIZE;

        feeBps = uint32(bytes4(args.slice(offset, offset + 4)));
        offset += 4;
        maxDeviationBps = uint32(bytes4(args.slice(offset, offset + 4)));
    }

    /// @notice Every member token across every group, in group/member order — the flat
    ///         "declared universe" `PortfolioManagerStrategyValidator` cross-checks against
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

    /// @notice Returns the oracle-valued group total with the requested rounding.
    /// @dev Portfolio-share checks round all groups alike. Swap pricing rounds input up and output down.
    function groupValueWad(Group memory group, address maker, OracleAdapter.Rounding rounding)
        internal
        view
        returns (uint256)
    {
        uint256 n = group.members.length;
        address[] memory tokens = new address[](n);
        uint256[] memory balances = new uint256[](n);
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](n);
        for (uint256 i = 0; i < n; i++) {
            Member memory m = group.members[i];
            tokens[i] = m.token;
            balances[i] = IERC20(m.token).balanceOf(maker);
            feeds[i] = OracleAdapter.PriceFeed({feed: AggregatorV3Interface(m.feed), maxStaleness: m.maxStaleness});
        }
        return OracleAdapter.groupValueWad(tokens, balances, feeds, rounding);
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

    /// @dev Checks `bridges[upTo]` against every earlier entry for the same unordered group
    ///      pair, regardless of which side is groupA/groupB in each entry.
    function _requireNoDuplicateBridge(Bridge[] memory bridges, uint256 upTo) private pure {
        Bridge memory candidate = bridges[upTo];
        for (uint256 k = 0; k < upTo; k++) {
            bool samePair = (bridges[k].groupA == candidate.groupA && bridges[k].groupB == candidate.groupB)
                || (bridges[k].groupA == candidate.groupB && bridges[k].groupB == candidate.groupA);
            require(!samePair, PortfolioManagerDuplicateBridge(candidate.groupA, candidate.groupB));
        }
    }
}
