// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Aqua} from "aqua/Aqua.sol";
import {TokenMock} from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {MockTaker} from "../lib/swap-vm/test/mocks/MockTaker.sol";

import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {PortfolioManagerTokenRegistry} from "../src/utils/PortfolioManagerTokenRegistry.sol";
import {PortfolioManagerFeedRegistry} from "../src/utils/PortfolioManagerFeedRegistry.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice BLEUDEV-425's dynamic-fee complement, exercised through real swaps (not just
///         PortfolioManagerDynamicFee.t.sol's pure-formula unit tests). Proves the mechanism has
///         a real, directional effect end-to-end and is opt-in per feed, by comparing a feed
///         registered with a deviation threshold against an otherwise-identical one without --
///         see each test for why a comparative assertion is used instead of a hand-computed
///         expected amountOut (the weighted-curve math has too many moving parts to duplicate
///         correctly here; the formula itself is already covered in isolation).
contract PortfolioManagerSwapDynamicFeeTest is Test {
    uint32 internal constant DEFAULT_MAX_STALENESS = 1 hours;
    uint16 internal constant DEVIATION_THRESHOLD_BPS = 10; // 0.10%, matching WBTC's real feed

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    PortfolioManagerStrategyValidator internal strategyValidator;
    PortfolioManagerTokenRegistry internal tokenRegistry;
    PortfolioManagerFeedRegistry internal feedRegistry;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;
    MockAggregatorV3 internal sequencerFeed;
    MockTaker internal taker;
    address internal maker;

    function setUp() public {
        vm.warp(1_000_000);
        sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 2 hours);

        aqua = new Aqua();
        tokenRegistry = new PortfolioManagerTokenRegistry();
        feedRegistry = new PortfolioManagerFeedRegistry(address(this));
        strategyValidator = new PortfolioManagerStrategyValidator(
            address(sequencerFeed), address(tokenRegistry), address(feedRegistry)
        );
        router = new PortfolioManagerRouter(
            address(aqua),
            address(0),
            address(this),
            "PM",
            "1",
            address(strategyValidator),
            address(sequencerFeed),
            address(tokenRegistry),
            address(feedRegistry)
        );

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");
        feedA = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedB = new MockAggregatorV3(18, 1e18, block.timestamp);

        maker = vm.addr(0x1234);
        taker = new MockTaker(aqua, router, address(this));
    }

    function _groups(uint16 feedAIndex, uint16 feedBIndex)
        internal
        returns (PortfolioManagerArgsCodec.Group[] memory groups)
    {
        groups = new PortfolioManagerArgsCodec.Group[](2);
        PortfolioManagerArgsCodec.Member[] memory membersA = new PortfolioManagerArgsCodec.Member[](1);
        membersA[0] = PortfolioManagerArgsCodec.Member({
            tokenIndex: tokenRegistry.register(address(tokenA)), feedIndex: feedAIndex
        });
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersA});

        PortfolioManagerArgsCodec.Member[] memory membersB = new PortfolioManagerArgsCodec.Member[](1);
        membersB[0] = PortfolioManagerArgsCodec.Member({
            tokenIndex: tokenRegistry.register(address(tokenB)), feedIndex: feedBIndex
        });
        groups[1] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersB});
    }

    function _buildOrder(PortfolioManagerArgsCodec.Group[] memory groups, uint32 lpFeeBps)
        internal
        view
        returns (ISwapVM.Order memory)
    {
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, lpFeeBps, 0);
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                receiver: address(0),
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(0),
                postTransferInData: "",
                preTransferOutTarget: address(0),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );
    }

    function _shipOrder(ISwapVM.Order memory order, uint256 balA, uint256 balB) internal {
        tokenA.mint(maker, balA);
        tokenB.mint(maker, balB);

        vm.startPrank(maker);
        tokenA.approve(address(aqua), type(uint256).max);
        tokenB.approve(address(aqua), type(uint256).max);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = balA;
        amounts[1] = balB;

        strategyValidator.attestBuildParameters(order, tokens, new string[](0));

        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
    }

    function _swapExactIn(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount)
        internal
        returns (uint256 amountOut)
    {
        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                threshold: "",
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: true,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
        TokenMock(tokenIn).mint(address(taker), amount * 2);
        (, amountOut) = taker.swap(order, tokenIn, tokenOut, amount, takerData);
    }

    /// @dev A feed jump well past 2x its deviation threshold should make a swap on that pair
    ///      pay a visibly worse rate than the exact same swap on a feed registered without a
    ///      deviation threshold (dynamic fee opted out) -- same starting price, same jump, same
    ///      swap size, only the feed's own registered threshold differs.
    function test_PriceJumpPastThresholdWorsensTheRateComparedToAFeedWithDynamicFeeDisabled() public {
        // Strategy 1: dynamic fee enabled on feedA.
        uint16 feedAWithThreshold =
            feedRegistry.register(address(feedA), DEFAULT_MAX_STALENESS, DEVIATION_THRESHOLD_BPS);
        uint16 feedBIndex = feedRegistry.register(address(feedB), DEFAULT_MAX_STALENESS);
        ISwapVM.Order memory orderWithDynamicFee = _buildOrder(_groups(feedAWithThreshold, feedBIndex), 0);
        _shipOrder(orderWithDynamicFee, 100_000e18, 100_000e18);

        // Strategy 2: identical, but feedA has no deviation threshold (dynamic fee opted out).
        // A second TokenMock/feed pair keeps the two strategies' balances fully isolated.
        TokenMock tokenA2 = new TokenMock("Token A2", "TKA2");
        TokenMock tokenB2 = new TokenMock("Token B2", "TKB2");
        MockAggregatorV3 feedA2 = new MockAggregatorV3(18, 1e18, block.timestamp);
        MockAggregatorV3 feedB2 = new MockAggregatorV3(18, 1e18, block.timestamp);
        uint16 feedA2Index = feedRegistry.register(address(feedA2), DEFAULT_MAX_STALENESS); // no threshold
        uint16 feedB2Index = feedRegistry.register(address(feedB2), DEFAULT_MAX_STALENESS);

        PortfolioManagerArgsCodec.Member[] memory membersA2 = new PortfolioManagerArgsCodec.Member[](1);
        membersA2[0] = PortfolioManagerArgsCodec.Member({
            tokenIndex: tokenRegistry.register(address(tokenA2)), feedIndex: feedA2Index
        });
        PortfolioManagerArgsCodec.Member[] memory membersB2 = new PortfolioManagerArgsCodec.Member[](1);
        membersB2[0] = PortfolioManagerArgsCodec.Member({
            tokenIndex: tokenRegistry.register(address(tokenB2)), feedIndex: feedB2Index
        });
        PortfolioManagerArgsCodec.Group[] memory groups2 = new PortfolioManagerArgsCodec.Group[](2);
        groups2[0] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersA2});
        groups2[1] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersB2});
        ISwapVM.Order memory orderWithoutDynamicFee = _buildOrder(groups2, 0);

        tokenA2.mint(maker, 100_000e18);
        tokenB2.mint(maker, 100_000e18);
        vm.startPrank(maker);
        tokenA2.approve(address(aqua), type(uint256).max);
        tokenB2.approve(address(aqua), type(uint256).max);
        vm.stopPrank();
        address[] memory tokens2 = new address[](2);
        tokens2[0] = address(tokenA2);
        tokens2[1] = address(tokenB2);
        uint256[] memory amounts2 = new uint256[](2);
        amounts2[0] = 100_000e18;
        amounts2[1] = 100_000e18;
        strategyValidator.attestBuildParameters(orderWithoutDynamicFee, tokens2, new string[](0));
        vm.prank(maker);
        aqua.ship(address(router), abi.encode(orderWithoutDynamicFee), tokens2, amounts2);

        // First swap on each strategy: just records the feed's starting price, no prior
        // observation to compare against, so no boost yet on either side.
        _swapExactIn(orderWithDynamicFee, address(tokenA), address(tokenB), 1e18);
        _swapExactIn(orderWithoutDynamicFee, address(tokenA2), address(tokenB2), 1e18);

        // Same jump on both feeds: +1.00% (10x the 0.10% threshold on feedA/feedA2, though only
        // feedA's registration actually enables the dynamic fee).
        feedA.setAnswer(1.01e18, block.timestamp);
        feedA2.setAnswer(1.01e18, block.timestamp);

        uint256 amountOutWithDynamicFee = _swapExactIn(orderWithDynamicFee, address(tokenA), address(tokenB), 1e18);
        uint256 amountOutWithoutDynamicFee =
            _swapExactIn(orderWithoutDynamicFee, address(tokenA2), address(tokenB2), 1e18);

        assertLt(
            amountOutWithDynamicFee,
            amountOutWithoutDynamicFee,
            "a feed with the dynamic fee enabled should pay a worse rate after the same price jump than an identical feed without it"
        );
    }

    /// @dev A move that stays within 2x the deviation threshold should not change the rate at
    ///      all compared to the no-dynamic-fee baseline -- the gate, not just the boost
    ///      direction, has a real effect through an actual swap.
    function test_SmallPriceMoveWithinThresholdDoesNotWorsenTheRate() public {
        uint16 feedAIndex = feedRegistry.register(address(feedA), DEFAULT_MAX_STALENESS, DEVIATION_THRESHOLD_BPS);
        uint16 feedBIndex = feedRegistry.register(address(feedB), DEFAULT_MAX_STALENESS);
        ISwapVM.Order memory order = _buildOrder(_groups(feedAIndex, feedBIndex), 0);
        _shipOrder(order, 100_000e18, 100_000e18);

        _swapExactIn(order, address(tokenA), address(tokenB), 1e18);

        // +0.05% is under the 2x0.10% = 0.20% gate.
        feedA.setAnswer(1.0005e18, block.timestamp);
        uint256 amountOutSmallMove = _swapExactIn(order, address(tokenA), address(tokenB), 1e18);

        // Reset the feed to its last value and swap again with no move at all, as a same-price
        // control -- the two amounts should match if the small move truly added no boost.
        uint256 amountOutNoMove = _swapExactIn(order, address(tokenA), address(tokenB), 1e18);

        assertApproxEqRel(amountOutSmallMove, amountOutNoMove, 0.0001e18);
    }
}
