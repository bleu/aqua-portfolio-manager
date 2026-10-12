// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {IPortfolioManagerStrategyValidator} from "./interfaces/IPortfolioManagerStrategyValidator.sol";
import {PortfolioManagerArgsCodec} from "./utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "./utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerPricing} from "./utils/PortfolioManagerPricing.sol";
import {PortfolioManagerTokenRegistry} from "./utils/PortfolioManagerTokenRegistry.sol";
import {PortfolioManagerFeedRegistry} from "./utils/PortfolioManagerFeedRegistry.sol";
import {OracleAdapter} from "./utils/OracleAdapter.sol";
import {FixedPointMath} from "./utils/FixedPointMath.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @title PortfolioManagerStrategyValidator
/// @notice Validates the declared universe and initial composition, then records attestation.
/// @dev Aqua does not compare ship() tokens with the encoded PM universe.
///      Batch attestation and shipping from the maker with identical tokens.
///      This contract must not forward ship(): Aqua uses msg.sender as the maker.
///      Members reference a token and a feed by registry index (BLEUDEV-412/ADR-0018) --
///      TOKEN_REGISTRY/FEED_REGISTRY are immutables so every helper below can resolve one
///      directly instead of carrying it as a parameter through the whole call chain.
contract PortfolioManagerStrategyValidator is IPortfolioManagerStrategyValidator {
    uint256 private constant WAD = 1e18;

    /// @dev Chainlink's L2 sequencer-uptime feed for this chain. See OracleAdapter.requireSequencerUp.
    AggregatorV3Interface private immutable SEQUENCER_UPTIME_FEED;
    PortfolioManagerTokenRegistry private immutable TOKEN_REGISTRY;
    PortfolioManagerFeedRegistry private immutable FEED_REGISTRY;

    /// @inheritdoc IPortfolioManagerStrategyValidator
    mapping(bytes32 => bool) public buildParamsAttested;

    constructor(address sequencerUptimeFeed, address tokenRegistry, address feedRegistry) {
        SEQUENCER_UPTIME_FEED = AggregatorV3Interface(sequencerUptimeFeed);
        TOKEN_REGISTRY = PortfolioManagerTokenRegistry(tokenRegistry);
        FEED_REGISTRY = PortfolioManagerFeedRegistry(feedRegistry);
    }

    /// @inheritdoc IPortfolioManagerStrategyValidator
    function requireUniverseMatches(ISwapVM.Order calldata order, address[] calldata tokens) external view {
        (PortfolioManagerArgsCodec.Group[] memory groups,,,) = PortfolioManagerArgsCodec.parse(_args(order));
        _requireUniverseMatches(groups, tokens);
    }

    /// @inheritdoc IPortfolioManagerStrategyValidator
    function requireBalancedWithinTolerance(ISwapVM.Order calldata order, address maker) external view {
        bytes calldata args = _args(order);
        (
            PortfolioManagerArgsCodec.Group[] memory groups,,
            uint32 maxDeviationBps,
            PortfolioManagerArgsCodec.Bridge[] memory bridges
        ) = PortfolioManagerArgsCodec.parse(args);
        _requireBalancedWithinTolerance(groups, maxDeviationBps, args, bridges.length, maker);
    }

    /// @inheritdoc IPortfolioManagerStrategyValidator
    function attestBuildParameters(ISwapVM.Order calldata order, address[] calldata tokens) external {
        bytes calldata args = _args(order);
        (
            PortfolioManagerArgsCodec.Group[] memory groups,,
            uint32 maxDeviationBps,
            PortfolioManagerArgsCodec.Bridge[] memory bridges
        ) = PortfolioManagerArgsCodec.parse(args);
        _requireUniverseMatches(groups, tokens);
        _requireBalancedWithinTolerance(groups, maxDeviationBps, args, bridges.length, order.maker);

        bytes32 strategyHash = keccak256(abi.encode(order));
        buildParamsAttested[strategyHash] = true;
        emit BuildParametersAttested(strategyHash);
    }

    /// @dev Resolves every declared member's token index through TOKEN_REGISTRY -- the only
    ///      reason this is `view` and not `pure` anymore.
    function _requireUniverseMatches(PortfolioManagerArgsCodec.Group[] memory groups, address[] calldata tokens)
        private
        view
    {
        address[] memory declared = PortfolioManagerArgsCodec.flattenTokens(groups, TOKEN_REGISTRY);

        for (uint256 i = 0; i < declared.length; i++) {
            bool shipped = false;
            for (uint256 j = 0; j < tokens.length; j++) {
                if (declared[i] == tokens[j]) {
                    shipped = true;
                    break;
                }
            }
            require(shipped, PortfolioManagerStrategyValidatorDeclaredTokenNotShipped(declared[i]));
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            bool isDeclared = false;
            for (uint256 j = 0; j < declared.length; j++) {
                if (tokens[i] == declared[j]) {
                    isDeclared = true;
                    break;
                }
            }
            require(isDeclared, PortfolioManagerStrategyValidatorShippedTokenNotDeclared(tokens[i]));
        }
    }

    function _requireBalancedWithinTolerance(
        PortfolioManagerArgsCodec.Group[] memory groups,
        uint32 maxDeviationBps,
        bytes calldata args,
        uint256 bridgeCount,
        address maker
    ) private view {
        if (maxDeviationBps == 0) return;
        OracleAdapter.requireSequencerUp(SEQUENCER_UPTIME_FEED);
        uint256[] memory groupValuesWad = _valueEveryGroup(groups, maker);
        _requireEveryPairWithinTolerance(groups, groupValuesWad, args, bridgeCount, maxDeviationBps);
    }

    /// @dev Split out of _requireBalancedWithinTolerance to keep that function under the
    ///      stack-depth limit.
    function _valueEveryGroup(PortfolioManagerArgsCodec.Group[] memory groups, address maker)
        private
        view
        returns (uint256[] memory groupValuesWad)
    {
        uint256 n = groups.length;
        groupValuesWad = new uint256[](n);
        uint256 totalValueWad;
        for (uint256 i = 0; i < n; i++) {
            groupValuesWad[i] = PortfolioManagerArgsCodec.groupValueWad(
                groups[i], maker, TOKEN_REGISTRY, FEED_REGISTRY, OracleAdapter.Rounding.Down
            );
            totalValueWad += groupValuesWad[i];
        }
        require(totalValueWad > 0, PortfolioManagerStrategyValidatorEmptyPortfolio());
    }

    /// @dev Checks every cross-group pair with PortfolioManagerSwap's own pairwise spot-price
    ///      formula, not each group's share of the total -- the two metrics diverge once a
    ///      strategy has more than two groups, and only the pairwise one guarantees every
    ///      direction a swap could actually trade is still within tolerance right after shipping.
    ///      When a pair's two groups use different units, their live bridge feed (ADR-0017)
    ///      converts group i's value into group j's unit first, so the same parity-against-WAD
    ///      comparison below still applies -- the target is never anything other than WAD, only
    ///      the value being compared against it changes. Split out of
    ///      _requireBalancedWithinTolerance to keep that function under the stack-depth limit.
    function _requireEveryPairWithinTolerance(
        PortfolioManagerArgsCodec.Group[] memory groups,
        uint256[] memory groupValuesWad,
        bytes calldata args,
        uint256 bridgeCount,
        uint32 maxDeviationBps
    ) private view {
        uint256 n = groups.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                // The common case (no Bridge registered anywhere) skips the external call
                // entirely -- it costs nothing beyond the pre-ADR-0017 check. Only a strategy
                // that actually registers a Bridge pays for the lookup, and only then: routed
                // through `this.` (a real CALL, in its own frame, not inlined here) --
                // resolveBridgeAdjustedValueWad re-parses args and resolves the bridge rate
                // independently. Threading a decoded Bridge[] through this loop instead (even via
                // `this.`) kept exceeding Solidity's stack-depth limit under via-IR; passing the
                // raw calldata slice through and re-parsing inside the external call's own frame
                // is what actually keeps this loop's frame under the limit.
                uint256 balanceIn = bridgeCount == 0
                    ? groupValuesWad[i]
                    : this.resolveBridgeAdjustedValueWad(groupValuesWad[i], args, i, j);
                PortfolioManagerPricing.PoolState memory quote = PortfolioManagerPricing.PoolState({
                    balanceIn: balanceIn,
                    balanceOut: groupValuesWad[j],
                    weightIn: groups[i].weight,
                    weightOut: groups[j].weight,
                    feeWad: 0
                });
                uint256 sp = PortfolioManagerPricing.spotPrice(quote);
                uint256 deviationBps = (sp > WAD ? sp - WAD : WAD - sp) * PortfolioManagerArgsCodec.PM_BPS / WAD;
                require(
                    deviationBps <= maxDeviationBps,
                    PortfolioManagerStrategyValidatorExcessivePriceDeviation(i, j, sp, maxDeviationBps)
                );
            }
        }
    }

    /// @notice Converts group i's value into group j's unit using group i/j's registered bridge
    ///         feed (ADR-0017), if any -- a no-op when the pair has none, meaning the strategy
    ///         builder has declared the two groups already share a unit.
    /// @dev `external` (called via `this.` from _requireEveryPairWithinTolerance), re-parsing
    ///      `args` itself rather than taking an already-decoded `Bridge[]` -- see the call site's
    ///      comment for why. A `feed` quotes group i's unit in terms of group j's unit, whichever
    ///      side of the entry's groupA/groupB matches; this never needs the groups' own units
    ///      named, only whether a bridge exists for this pair. Rounding direction is not
    ///      safety-critical here -- unlike swap pricing, this only gates whether a trade is
    ///      currently allowed, it never moves funds on its own.
    function resolveBridgeAdjustedValueWad(uint256 valueWad, bytes calldata args, uint256 groupI, uint256 groupJ)
        external
        view
        returns (uint256)
    {
        (,,, PortfolioManagerArgsCodec.Bridge[] memory bridges) = PortfolioManagerArgsCodec.parse(args);
        for (uint256 k = 0; k < bridges.length; k++) {
            PortfolioManagerArgsCodec.Bridge memory b = bridges[k];
            if (uint256(b.groupA) == groupI && uint256(b.groupB) == groupJ) {
                uint256 rate = OracleAdapter.priceWad(
                    OracleAdapter.PriceFeed({feed: AggregatorV3Interface(b.feed), maxStaleness: b.maxStaleness}),
                    OracleAdapter.Rounding.Down
                );
                return FixedPointMath.mulDivDown(valueWad, rate, WAD);
            }
            if (uint256(b.groupA) == groupJ && uint256(b.groupB) == groupI) {
                uint256 rate = OracleAdapter.priceWad(
                    OracleAdapter.PriceFeed({feed: AggregatorV3Interface(b.feed), maxStaleness: b.maxStaleness}),
                    OracleAdapter.Rounding.Down
                );
                return FixedPointMath.mulDivDown(valueWad, WAD, rate);
            }
        }
        return valueWad;
    }

    /// @dev Extracts arguments from the required leading PM opcode.
    function _args(ISwapVM.Order calldata order) private pure returns (bytes calldata args) {
        bytes calldata program = MakerTraitsLib.program(order.traits, order.data);
        require(
            program.length >= 2 && uint8(program[0]) == PortfolioManagerProgramBuilder.CURVE_OPCODE,
            PortfolioManagerStrategyValidatorNotAPortfolioManagerStrategy()
        );

        uint256 argsLength = uint8(program[1]);
        args = program[2:2 + argsLength];

        // Walks every instruction after the leading curve and rejects a second one -- its args
        // would never be checked or bound to this validated curve. A non-curve trailing
        // instruction (e.g. GatedPortfolioManagerProgramBuilder's resolver KYC gate) is fine:
        // it can't touch pricing, only gate who's allowed to trade at all.
        uint256 pc = 2 + argsLength;
        while (pc < program.length) {
            uint8 opcode = uint8(program[pc]);
            require(
                opcode != PortfolioManagerProgramBuilder.CURVE_OPCODE,
                PortfolioManagerStrategyValidatorTrailingCurveInstruction()
            );
            uint256 trailingArgsLength = uint8(program[pc + 1]);
            pc += 2 + trailingArgsLength;
        }
    }
}
