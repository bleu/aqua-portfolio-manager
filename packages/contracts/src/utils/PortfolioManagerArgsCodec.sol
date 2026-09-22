// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Calldata} from "@1inch/solidity-utils/contracts/libraries/Calldata.sol";
import {FixedPointMath} from "./FixedPointMath.sol";
import {OracleAdapter} from "./OracleAdapter.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title PortfolioManagerArgsCodec
/// @notice Encodes token groups, target weights, feeds, the LP fee, and the deviation limit.
/// @dev Configuration lives in immutable instruction arguments committed by the strategy hash.
///      Every group member requires a feed. Group weights may differ.
library PortfolioManagerArgsCodec {
    using Calldata for bytes;

    /// @dev Matches SwapVM's fee scale: 1e9 = 100%. One conventional basis point is 100_000.
    uint256 internal constant PM_BPS = 1e9;

    uint256 private constant WAD = FixedPointMath.WAD;
    /// @dev 16-byte weight + 1-byte member count precedes each group's members.
    uint256 private constant GROUP_HEADER_SIZE = 17;
    /// @dev Each member uses 20 token bytes, 20 feed bytes, and 2 maxStaleness bytes (seconds).
    ///      The uint16 age limit is 65,535 seconds. Compact entries help fit the 255-byte argument budget.
    uint256 private constant MEMBER_ENTRY_SIZE = 42;

    /// @dev At least two groups are needed for cross-group pricing.
    ///      Shape bounds do not guarantee the 255-byte argument limit. build() checks encoded length separately.
    uint256 internal constant MIN_GROUPS = 2;
    uint256 internal constant MAX_GROUPS = 4;
    uint256 internal constant MAX_MEMBERS_PER_GROUP = 5;

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
    error PortfolioManagerTooFewGroups(uint256 count);
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
    /// @dev The complete encoding exceeds SwapVM's 255-byte instruction argument limit.
    error PortfolioManagerArgsTooLarge(uint256 length);
    error PortfolioManagerMissingMaxDeviationBps();

    /// @notice Builds arguments with the deviation breaker disabled.
    function build(Group[] memory groups, uint32 feeBps) internal pure returns (bytes memory args) {
        return build(groups, feeBps, 0);
    }

    /// @param groups Groups with WAD-scaled weights summing to WAD and per-member feeds.
    /// @param feeBps LP curve fee, scaled by PM_BPS.
    /// @param maxDeviationBps Deviation limit, scaled by PM_BPS. Zero disables both deviation checks.
    function build(Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps)
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

        args = abi.encodePacked(args, feeBps, maxDeviationBps);
        require(args.length <= type(uint8).max, PortfolioManagerArgsTooLarge(args.length));
    }

    /// @dev Validates group structure, weights, token uniqueness, feeds, and fees in caller-supplied arguments.
    function parse(bytes calldata args)
        internal
        pure
        returns (Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps)
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
            uint256 weight = uint256(uint128(bytes16(args.slice(offset, offset + 16))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 16, offset + GROUP_HEADER_SIZE)));
            require(weight > 0, PortfolioManagerZeroWeight(i));
            require(memberCount > 0, PortfolioManagerEmptyGroup(i));
            require(memberCount <= MAX_MEMBERS_PER_GROUP, PortfolioManagerTooManyMembers(memberCount));
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
        offset += 4;

        maxDeviationBps =
            uint32(bytes4(args.slice(offset, offset + 4, PortfolioManagerMissingMaxDeviationBps.selector)));
    }

    /// @notice Decodes arguments without structural validation.
    /// @dev Call only after these exact bytes pass parse(). PM requires validator attestation before this call.
    ///      Never use for untrusted or unattested arguments.
    function decodeTrusted(bytes calldata args)
        internal
        pure
        returns (Group[] memory groups, uint32 feeBps, uint32 maxDeviationBps)
    {
        uint8 groupCount = uint8(bytes1(args.slice(0, 1)));
        groups = new Group[](groupCount);
        uint256 offset = 1;

        for (uint256 i = 0; i < groupCount; i++) {
            uint256 weight = uint256(uint128(bytes16(args.slice(offset, offset + 16))));
            uint8 memberCount = uint8(bytes1(args.slice(offset + 16, offset + GROUP_HEADER_SIZE)));
            offset += GROUP_HEADER_SIZE;

            Member[] memory members = new Member[](memberCount);
            for (uint256 j = 0; j < memberCount; j++) {
                address token = address(bytes20(args.slice(offset, offset + 20)));
                address feed = address(bytes20(args.slice(offset + 20, offset + 40)));
                uint256 maxStaleness = uint256(uint16(bytes2(args.slice(offset + 40, offset + MEMBER_ENTRY_SIZE))));
                members[j] = Member({token: token, feed: feed, maxStaleness: maxStaleness});
                offset += MEMBER_ENTRY_SIZE;
            }
            groups[i] = Group({weight: weight, members: members});
        }

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
}
