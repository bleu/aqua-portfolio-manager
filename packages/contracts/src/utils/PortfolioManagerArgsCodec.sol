// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Calldata} from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";
import {FixedPointMath} from "./FixedPointMath.sol";
import {OracleAdapter} from "./OracleAdapter.sol";
import {PortfolioManagerTokenRegistry} from "./PortfolioManagerTokenRegistry.sol";
import {PortfolioManagerFeedRegistry} from "./PortfolioManagerFeedRegistry.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title PortfolioManagerArgsCodec
/// @notice Encodes token groups, target weights, feeds, bridge feeds, the LP fee, and the
///         deviation limit.
/// @dev Configuration lives in immutable instruction arguments committed by the strategy hash.
///      Group weights may differ. Every member requires a feed except at most one per group,
///      which may use feed index 0 to designate it that group's own numeraire
///      (BLEUDEV-412/ADR-0017) -- see OracleAdapter.PriceFeed's doc comment. Different groups may
///      use different numeraires (or none); `Bridge` entries (ADR-0017) let the ship-time
///      deviation check compare groups whose units differ.
///      Members reference a token and a feed by a 2-byte index into
///      PortfolioManagerTokenRegistry/PortfolioManagerFeedRegistry instead of carrying the full
///      20-byte address of each (BLEUDEV-412/ADR-0018) -- `build`/`parse`/`decodeTrusted` never
///      touch either registry (indices decode for free); only `groupValueWad` and
///      `flattenTokens` resolve an index to an address, and only because they already need
///      external calls (`balanceOf`, the oracle feed) to do their job.
library PortfolioManagerArgsCodec {
    using Calldata for bytes;

    /// @dev Matches SwapVM's fee scale: 1e9 = 100%. One conventional basis point is 100_000.
    uint256 internal constant PM_BPS = 1e9;

    /// @dev Floor on the LP-configured curve fee, PM_BPS-scaled: 0.5% = 5_000_000. Previously
    ///      feeBps = 0 was deliberately allowed (BLEUDEV-327: "genuinely LP-optional"); this
    ///      reverses that ahead of mainnet deployment.
    uint256 internal constant MIN_FEE_BPS = 5_000_000;

    uint256 private constant WAD = FixedPointMath.WAD;
    /// @dev WAD/PM_BPS -- exact (1e18 / 1e9 = 1e9), so expanding an encoded weight back to WAD
    ///      never rounds. Only narrowing WAD down to PM_BPS at build() time can lose precision.
    uint256 private constant WEIGHT_WAD_PER_PM_BPS = WAD / PM_BPS;
    /// @dev 4-byte weight + 1-byte member count precedes each group's members. Weights are
    ///      encoded at PM_BPS scale (1e9 = 100%, same scale as feeBps/maxDeviationBps), not WAD --
    ///      no LP target allocation needs more than 9 significant digits of its own percentage.
    ///      The in-memory `Group.weight` this decodes to is still a full WAD uint256; only the
    ///      wire encoding is coarser, so PortfolioManagerPricing's curve math runs at its usual
    ///      full precision -- see build()'s and parse()'s own comments for how the sum-to-100%
    ///      check and the WAD<->PM_BPS conversion interact.
    uint256 private constant GROUP_HEADER_SIZE = 5;
    /// @dev Each member is a 2-byte token-registry index and a 2-byte feed-registry index --
    ///      down from 43 bytes (two full addresses plus a per-member maxStaleness) now that both
    ///      the address and its maxStaleness bound resolve through PortfolioManagerFeedRegistry
    ///      instead of being carried in the encoding itself (BLEUDEV-412/ADR-0018).
    uint256 private constant MEMBER_ENTRY_SIZE = 4;
    /// @dev Each bridge entry uses 1 groupA byte, 1 groupB byte, 20 feed bytes, and 3
    ///      maxStaleness bytes. Bridges stay raw addresses, not registry indices -- a strategy
    ///      registers at most a handful, nowhere near the per-member budget pressure that
    ///      motivated compressing Member.
    uint256 private constant BRIDGE_ENTRY_SIZE = 25;

    /// @dev At least two groups are needed for cross-group pricing.
    ///      Shape bounds do not guarantee the 255-byte argument limit. build() checks encoded length separately.
    uint256 internal constant MIN_GROUPS = 2;
    uint256 internal constant MAX_GROUPS = 4;
    uint256 internal constant MAX_MEMBERS_PER_GROUP = 5;
    /// @dev MAX_GROUPS pairwise combinations: 4 choose 2.
    uint256 internal constant MAX_BRIDGES = 6;

    /// @param tokenIndex Index into PortfolioManagerTokenRegistry. Never 0 -- that index is
    ///        reserved and always resolves to the zero address.
    /// @param feedIndex Index into PortfolioManagerFeedRegistry. Index 0 designates this member
    ///        its group's own numeraire (BLEUDEV-412/ADR-0017): its balance is already in that
    ///        group's unit of account, so it needs no feed and no external call at all.
    struct Member {
        uint16 tokenIndex;
        uint16 feedIndex;
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
    /// @dev A member's feed index may be 0, designating it its group's own numeraire
    ///      (BLEUDEV-412/ADR-0017) -- but only one per group. A second one would leave that
    ///      group's unit of account ambiguous between two different tokens.
    error PortfolioManagerMultipleNumeraireMembers(uint256 groupIndex);
    error PortfolioManagerZeroTokenIndex(uint256 groupIndex, uint256 memberIndex);
    error PortfolioManagerDuplicateToken(uint16 tokenIndex);
    error PortfolioManagerMissingGroupCount();
    error PortfolioManagerMissingGroupHeader();
    error PortfolioManagerMissingMemberEntry();
    error PortfolioManagerMissingFeeBps();
    /// @dev The complete encoding exceeds SwapVM's 255-byte instruction argument limit.
    error PortfolioManagerArgsTooLarge(uint256 length);
    error PortfolioManagerMissingMaxDeviationBps();
    error PortfolioManagerMaxStalenessOutOfRange(uint256 maxStaleness);
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

    /// @param groups Groups with WAD-scaled weights summing to WAD and per-member registry indices.
    /// @param feeBps LP curve fee, scaled by PM_BPS.
    /// @param maxDeviationBps Deviation limit, scaled by PM_BPS. Zero disables both deviation checks.
    /// @param bridges Live feeds bridging groups whose units differ, for the ship-time deviation
    ///        check only (ADR-0017). Omit a pair that already shares a unit.
    /// @dev Does not read either registry -- a tokenIndex/feedIndex that was never registered
    ///      still encodes; it resolves to the zero address wherever it's later used, and the
    ///      external call that follows (balanceOf, latestRoundData) reverts naturally on that.
    function build(Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps, Bridge[] memory bridges)
        internal
        pure
        returns (bytes memory args)
    {
        require(groups.length > 0, PortfolioManagerEmptyUniverse());
        require(groups.length >= MIN_GROUPS, PortfolioManagerTooFewGroups(groups.length));
        require(groups.length <= MAX_GROUPS, PortfolioManagerTooManyGroups(groups.length));
        require(feeBps >= MIN_FEE_BPS && feeBps <= PM_BPS, PortfolioManagerFeeBpsOutOfRange(feeBps));

        args = abi.encodePacked(uint8(groups.length));

        // Encodes each group's weight at PM_BPS scale (4 bytes) instead of WAD (would need 8) --
        // see GROUP_HEADER_SIZE's doc comment. The last group's compact weight soaks whatever
        // floor-rounding lost on the earlier ones, so the compact values sum to exactly PM_BPS
        // whenever the real WAD weights sum to exactly WAD (checked below, same as before this
        // encoding existed). The `compactSum >= PM_BPS` guard only matters for an already-invalid
        // input (weights that don't sum to WAD) -- it keeps this loop from underflowing instead
        // of reaching the real error below with a clear revert reason.
        uint256 sum;
        uint256 compactSum;
        for (uint256 i = 0; i < groups.length; i++) {
            Group memory g = groups[i];
            require(g.weight > 0, PortfolioManagerZeroWeight(i));
            require(g.members.length > 0, PortfolioManagerEmptyGroup(i));
            require(g.members.length <= MAX_MEMBERS_PER_GROUP, PortfolioManagerTooManyMembers(g.members.length));
            sum += g.weight;

            uint256 compactWeight = i == groups.length - 1
                ? (compactSum >= PM_BPS ? 0 : PM_BPS - compactSum)
                : FixedPointMath.mulDivDown(g.weight, PM_BPS, WAD);
            compactSum += compactWeight;

            args = abi.encodePacked(args, uint32(compactWeight), uint8(g.members.length));
            uint256 numeraireCount;
            for (uint256 j = 0; j < g.members.length; j++) {
                Member memory m = g.members[j];
                require(m.tokenIndex != 0, PortfolioManagerZeroTokenIndex(i, j));
                if (m.feedIndex == 0) numeraireCount++;
                args = abi.encodePacked(args, m.tokenIndex, m.feedIndex);
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

    /// @dev Validates group structure, weights, index uniqueness, bridges, and fees in
    ///      caller-supplied arguments. Does not read either registry -- see build()'s comment.
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
            // Weight is encoded at PM_BPS scale (4 bytes), not WAD -- see GROUP_HEADER_SIZE's doc
            // comment. Expanding back to WAD (x WEIGHT_WAD_PER_PM_BPS) is exact, so the in-memory
            // Group.weight below is still a full WAD value for PortfolioManagerPricing's math.
            uint256 compactWeight = uint256(uint32(bytes4(args.slice(offset, offset + 4))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 4, offset + GROUP_HEADER_SIZE)));
            require(compactWeight > 0, PortfolioManagerZeroWeight(i));
            require(memberCount > 0, PortfolioManagerEmptyGroup(i));
            require(memberCount <= MAX_MEMBERS_PER_GROUP, PortfolioManagerTooManyMembers(memberCount));
            sum += compactWeight;
            offset += GROUP_HEADER_SIZE;

            Member[] memory members = new Member[](memberCount);
            uint256 numeraireCount;
            for (uint256 j = 0; j < memberCount; j++) {
                args.slice(offset, offset + MEMBER_ENTRY_SIZE, PortfolioManagerMissingMemberEntry.selector);
                uint16 tokenIndex = uint16(bytes2(args.slice(offset, offset + 2)));
                uint16 feedIndex = uint16(bytes2(args.slice(offset + 2, offset + MEMBER_ENTRY_SIZE)));
                require(tokenIndex != 0, PortfolioManagerZeroTokenIndex(i, j));
                if (feedIndex == 0) numeraireCount++;
                members[j] = Member({tokenIndex: tokenIndex, feedIndex: feedIndex});
                offset += MEMBER_ENTRY_SIZE;
            }
            require(numeraireCount <= 1, PortfolioManagerMultipleNumeraireMembers(i));
            groups[i] = Group({weight: compactWeight * WEIGHT_WAD_PER_PM_BPS, members: members});
        }
        require(sum == PM_BPS, PortfolioManagerWeightsMustSumToWad(sum * WEIGHT_WAD_PER_PM_BPS));
        _requireNoDuplicateTokens(groups);

        uint256 afterBridges;
        (bridges, afterBridges) = _parseBridges(args, offset, groups.length);
        offset = afterBridges;

        feeBps = uint32(bytes4(args.slice(offset, offset + 4, PortfolioManagerMissingFeeBps.selector)));
        require(feeBps >= MIN_FEE_BPS && feeBps <= PM_BPS, PortfolioManagerFeeBpsOutOfRange(feeBps));
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
            uint256 compactWeight = uint256(uint32(bytes4(args.slice(offset, offset + 4))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 4, offset + GROUP_HEADER_SIZE)));
            offset += GROUP_HEADER_SIZE;

            Member[] memory members = new Member[](memberCount);
            for (uint256 j = 0; j < memberCount; j++) {
                uint16 tokenIndex = uint16(bytes2(args.slice(offset, offset + 2)));
                uint16 feedIndex = uint16(bytes2(args.slice(offset + 2, offset + MEMBER_ENTRY_SIZE)));
                members[j] = Member({tokenIndex: tokenIndex, feedIndex: feedIndex});
                offset += MEMBER_ENTRY_SIZE;
            }
            groups[i] = Group({weight: compactWeight * WEIGHT_WAD_PER_PM_BPS, members: members});
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
            uint256 compactWeight = uint256(uint32(bytes4(args.slice(offset, offset + 4))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 4, offset + GROUP_HEADER_SIZE)));
            offset += GROUP_HEADER_SIZE;

            Member[] memory members = new Member[](memberCount);
            for (uint256 j = 0; j < memberCount; j++) {
                uint16 tokenIndex = uint16(bytes2(args.slice(offset, offset + 2)));
                uint16 feedIndex = uint16(bytes2(args.slice(offset + 2, offset + MEMBER_ENTRY_SIZE)));
                members[j] = Member({tokenIndex: tokenIndex, feedIndex: feedIndex});
                offset += MEMBER_ENTRY_SIZE;
            }
            groups[i] = Group({weight: compactWeight * WEIGHT_WAD_PER_PM_BPS, members: members});
        }

        uint8 bridgeCount = uint8(bytes1(args.slice(offset, offset + 1)));
        offset += 1 + bridgeCount * BRIDGE_ENTRY_SIZE;

        feeBps = uint32(bytes4(args.slice(offset, offset + 4)));
        offset += 4;
        maxDeviationBps = uint32(bytes4(args.slice(offset, offset + 4)));
    }

    /// @notice Every member's token index across every group, in group/member order -- the flat
    ///         "declared universe" used for the duplicate check below and, resolved to addresses
    ///         by the caller, cross-checked against `ship()`'s own `tokens` array.
    function flattenTokenIndices(Group[] memory groups) internal pure returns (uint16[] memory tokenIndices) {
        uint256 total;
        for (uint256 i = 0; i < groups.length; i++) {
            total += groups[i].members.length;
        }
        tokenIndices = new uint16[](total);
        uint256 k;
        for (uint256 i = 0; i < groups.length; i++) {
            for (uint256 j = 0; j < groups[i].members.length; j++) {
                tokenIndices[k++] = groups[i].members[j].tokenIndex;
            }
        }
    }

    /// @notice Resolves every member's token index to an address via `tokenRegistry`, in the same
    ///         group/member order as flattenTokenIndices.
    /// @dev `PortfolioManagerStrategyValidator` is the only caller -- it needs real addresses to
    ///      compare against `ship()`'s own `tokens` array, which `flattenTokenIndices` alone
    ///      can't do.
    function flattenTokens(Group[] memory groups, PortfolioManagerTokenRegistry tokenRegistry)
        internal
        view
        returns (address[] memory tokens)
    {
        uint16[] memory tokenIndices = flattenTokenIndices(groups);
        tokens = new address[](tokenIndices.length);
        for (uint256 i = 0; i < tokenIndices.length; i++) {
            tokens[i] = tokenRegistry.tokenAt(tokenIndices[i]);
        }
    }

    /// @notice Returns the oracle-valued group total with the requested rounding.
    /// @dev Portfolio-share checks round all groups alike. Swap pricing rounds input up and down.
    ///      Resolves each member's token and feed through the registries -- the only reason this
    ///      is `view` and not `pure`.
    function groupValueWad(
        Group memory group,
        address maker,
        PortfolioManagerTokenRegistry tokenRegistry,
        PortfolioManagerFeedRegistry feedRegistry,
        OracleAdapter.Rounding rounding
    ) internal view returns (uint256) {
        uint256 n = group.members.length;
        address[] memory tokens = new address[](n);
        uint256[] memory balances = new uint256[](n);
        OracleAdapter.PriceFeed[] memory feeds = new OracleAdapter.PriceFeed[](n);
        for (uint256 i = 0; i < n; i++) {
            Member memory m = group.members[i];
            address token = tokenRegistry.tokenAt(m.tokenIndex);
            tokens[i] = token;
            balances[i] = IERC20(token).balanceOf(maker);
            (address feed, uint32 maxStaleness) = feedRegistry.feedAt(m.feedIndex);
            feeds[i] = OracleAdapter.PriceFeed({feed: AggregatorV3Interface(feed), maxStaleness: maxStaleness});
        }
        return OracleAdapter.groupValueWad(tokens, balances, feeds, rounding);
    }

    /// @dev A token declared in two groups would make `PortfolioManagerSwap`'s group lookup
    ///      ambiguous (which group's weight applies?) — rejected outright rather than defined
    ///      as "first match wins." Compares raw indices -- cheap, and doesn't need a registry.
    function _requireNoDuplicateTokens(Group[] memory groups) private pure {
        uint16[] memory tokenIndices = flattenTokenIndices(groups);
        for (uint256 i = 0; i < tokenIndices.length; i++) {
            for (uint256 j = i + 1; j < tokenIndices.length; j++) {
                if (tokenIndices[i] == tokenIndices[j]) revert PortfolioManagerDuplicateToken(tokenIndices[i]);
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
