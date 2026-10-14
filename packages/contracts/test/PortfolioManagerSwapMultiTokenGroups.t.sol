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
import {PortfolioManagerPricing} from "../src/utils/PortfolioManagerPricing.sol";
import {PortfolioManagerSwap} from "../src/PortfolioManagerSwap.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {IPortfolioManagerSwap} from "../src/interfaces/IPortfolioManagerSwap.sol";
import {OracleAdapter} from "../src/utils/OracleAdapter.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice Tests group valuation, member liquidity, and feed freshness through SwapVM swaps.
contract PortfolioManagerSwapMultiTokenGroupsTest is Test {
    uint256 internal constant INITIAL_BALANCE = 100_000e18;

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    PortfolioManagerStrategyValidator internal strategyValidator;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    TokenMock internal tokenC;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;
    MockAggregatorV3 internal feedC;
    MockAggregatorV3 internal sequencerFeed;
    MockTaker internal taker;

    address internal maker;

    /// @dev Mix a two-member group with a single-member group to test uniform valuation.
    PortfolioManagerArgsCodec.Group[] internal groups;

    function setUp() public {
        vm.warp(1_000_000);
        // answer 0 == sequencer up (Chainlink's uptime-feed convention); started long enough ago
        // that OracleAdapter's post-recovery grace period has already elapsed.
        sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 2 hours);

        aqua = new Aqua();
        strategyValidator = new PortfolioManagerStrategyValidator(address(sequencerFeed));
        router = new PortfolioManagerRouter(
            address(aqua), address(0), address(this), "PM", "1", address(strategyValidator), address(sequencerFeed)
        );

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");
        tokenC = new TokenMock("Token C", "TKC");

        // Unit prices make the group value equal the sum of native balances.
        feedA = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedB = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedC = new MockAggregatorV3(18, 1e18, block.timestamp);

        maker = vm.addr(0x1234);
        taker = new MockTaker(aqua, router, address(this));

        PortfolioManagerArgsCodec.Member[] memory group0Members = new PortfolioManagerArgsCodec.Member[](2);
        group0Members[0] =
            PortfolioManagerArgsCodec.Member({token: address(tokenA), feed: address(feedA), maxStaleness: 1 hours});
        group0Members[1] =
            PortfolioManagerArgsCodec.Member({token: address(tokenB), feed: address(feedB), maxStaleness: 1 hours});
        groups.push(PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: group0Members}));

        PortfolioManagerArgsCodec.Member[] memory group1Members = new PortfolioManagerArgsCodec.Member[](1);
        group1Members[0] =
            PortfolioManagerArgsCodec.Member({token: address(tokenC), feed: address(feedC), maxStaleness: 1 hours});
        groups.push(PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: group1Members}));
    }

    // ===== Helpers =====

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        return _buildOrder(lpFeeBps, 0);
    }

    function _buildOrder(uint32 lpFeeBps, uint32 maxDeviationBps) internal view returns (ISwapVM.Order memory) {
        return _buildOrderWithGroups(groups, lpFeeBps, maxDeviationBps);
    }

    /// @dev Lets a test use a custom group set (e.g. a numeraire member) instead of the fixture's
    ///      own `groups`.
    function _buildOrderWithGroups(
        PortfolioManagerArgsCodec.Group[] memory customGroups,
        uint32 lpFeeBps,
        uint32 maxDeviationBps
    ) internal view returns (ISwapVM.Order memory) {
        bytes memory program = PortfolioManagerProgramBuilder.build(customGroups, lpFeeBps, maxDeviationBps);
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

    /// @param balA/balB/balC Real wallet balances, also used as Aqua ledger amounts.
    function _shipOrder(ISwapVM.Order memory order, uint256 balA, uint256 balB, uint256 balC) internal {
        tokenA.mint(maker, balA);
        tokenB.mint(maker, balB);
        tokenC.mint(maker, balC);

        vm.startPrank(maker);
        tokenA.approve(address(aqua), type(uint256).max);
        tokenB.approve(address(aqua), type(uint256).max);
        tokenC.approve(address(aqua), type(uint256).max);
        vm.stopPrank();

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = balA;
        amounts[1] = balB;
        amounts[2] = balC;

        strategyValidator.attestBuildParameters(order, tokens);

        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
    }

    function _swapExactIn(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount)
        internal
        returns (uint256, uint256)
    {
        return _swap(order, tokenIn, tokenOut, amount, true);
    }

    function _swap(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        internal
        returns (uint256, uint256)
    {
        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: exactIn,
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

        TokenMock(tokenIn).mint(address(taker), amount * (exactIn ? 2 : 10));
        return taker.swap(order, tokenIn, tokenOut, amount, takerData);
    }

    function _exactInTakerData() internal view returns (bytes memory) {
        return TakerTraitsLib.build(
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
    }

    function _exactOutTakerData() internal view returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: false,
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
    }

    // ===== Tests =====

    function test_ExactInBoundsHighDecimalInputPrice() public {
        _checkHighDecimalPriceSettlement(true, true);
    }

    function test_ExactOutBoundsHighDecimalInputPrice() public {
        _checkHighDecimalPriceSettlement(true, false);
    }

    function test_ExactInBoundsHighDecimalOutputPrice() public {
        _checkHighDecimalPriceSettlement(false, true);
    }

    function test_ExactOutBoundsHighDecimalOutputPrice() public {
        _checkHighDecimalPriceSettlement(false, false);
    }

    function _checkHighDecimalPriceSettlement(bool fractionalInput, bool exactIn) internal {
        feedA = new MockAggregatorV3(24, 1_500_000, block.timestamp);
        groups[0].members[0].feed = address(feedA);
        feedB.setAnswer(1, block.timestamp);
        feedC.setAnswer(1, block.timestamp);
        ISwapVM.Order memory order = _buildOrder(0);
        uint256 balanceA = fractionalInput ? 100e18 : 1000e18;
        _shipOrder(order, balanceA, 1000e18, 1000e18);

        address tokenIn = fractionalInput ? address(tokenA) : address(tokenC);
        address tokenOut = fractionalInput ? address(tokenC) : address(tokenA);
        uint256 amount = exactIn ? 1000e18 : (fractionalInput ? 625e18 : 800e18);
        _swap(order, tokenIn, tokenOut, amount, exactIn);

        // Raw prices are in the ratio 3:2:2. Cancel their common denominator;
        // neither rounded WAD prices nor production quote helpers enter this invariant.
        uint256 beforeInvariant = (3 * balanceA + 2 * 1000e18) * 1000e18;
        uint256 afterInvariant = (3 * tokenA.balanceOf(maker) + 2 * tokenB.balanceOf(maker)) * tokenC.balanceOf(maker);
        assertGe(afterInvariant, beforeInvariant);
    }

    function test_FractionalMemberValuesPreserveSettledGroupInvariant() public {
        feedA.setAnswer(0.5e18, block.timestamp);
        feedB.setAnswer(0.5e18, block.timestamp);
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, 3, 1, 100e18);

        _swapExactIn(order, address(tokenA), address(tokenC), 2);

        // A and B have the same fixed price: multiply by two to cancel it exactly.
        uint256 afterInvariant = (tokenA.balanceOf(maker) + tokenB.balanceOf(maker)) * tokenC.balanceOf(maker);
        assertGe(afterInvariant, 4 * 100e18);
    }

    function test_SameGroupSwapReverts() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE, INITIAL_BALANCE, INITIAL_BALANCE);

        bytes memory takerData = _exactInTakerData();
        tokenA.mint(address(taker), 1_000e18);

        vm.expectRevert(
            abi.encodeWithSelector(IPortfolioManagerSwap.PortfolioManagerSwapSameGroupSwap.selector, uint256(0))
        );
        taker.swap(order, address(tokenA), address(tokenB), 500e18, takerData);
    }

    function test_MultiMemberGroupPricesOffFullGroupValueNotJustTheTradedToken() public {
        // Equal group values despite uneven funding within group0.
        uint256 balA = 1_000e18;
        uint256 balB = 99_000e18;
        uint256 balC = 100_000e18;

        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, balA, balB, balC);

        uint256 amountIn = 500e18;
        (, uint256 actualAmountOut) = _swapExactIn(order, address(tokenC), address(tokenA), amountIn);

        // Correct expectation: balanceOut is group0's FULL oracle-valued sum (balA + balB).
        PortfolioManagerPricing.PoolState memory correctPoolState = PortfolioManagerPricing.PoolState({
            balanceIn: balC, balanceOut: balA + balB, weightIn: groups[1].weight, weightOut: groups[0].weight, feeWad: 0
        });
        uint256 expectedAmountOut = PortfolioManagerPricing.exactIn(correctPoolState, amountIn);
        assertEq(actualAmountOut, expectedAmountOut, "must price off group0's full 2-member sum");

        // Omitting tokenB understates the output reserve and therefore the quote.
        PortfolioManagerPricing.PoolState memory wrongPoolState = PortfolioManagerPricing.PoolState({
            balanceIn: balC, balanceOut: balA, weightIn: groups[1].weight, weightOut: groups[0].weight, feeWad: 0
        });
        uint256 wrongAmountOut = PortfolioManagerPricing.exactIn(wrongPoolState, amountIn);
        assertGt(
            actualAmountOut, wrongAmountOut, "must clearly differ from a single-token-only (tokenA-balance-only) quote"
        );
    }

    function test_StaleFeedOnNonTradedGroupMemberBlocksTrade() public {
        // Advance time to avoid subtraction underflow, then make only feedB stale.
        vm.warp(365 days);
        feedA.setAnswer(1e18, block.timestamp);
        feedC.setAnswer(1e18, block.timestamp);

        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE, INITIAL_BALANCE, INITIAL_BALANCE);

        // A stale non-traded member must still block the group's trade.
        uint256 staleUpdatedAt = block.timestamp - 2 hours;
        feedB.setAnswer(1e18, staleUpdatedAt);

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleAdapter.OracleAdapterStalePrice.selector, address(feedB), staleUpdatedAt, uint256(1 hours)
            )
        );
        taker.swap(order, address(tokenC), address(tokenA), 500e18, takerData);
    }

    /// @dev Proves the swap path actually asks the sequencer feed, not just that wiring a
    ///      constructor param compiles -- flips the same mock setUp wired in, to "down".
    function test_RevertsWhenSequencerIsDown() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE, INITIAL_BALANCE, INITIAL_BALANCE);
        sequencerFeed.setAnswer(1, block.timestamp); // answer 1 == down

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000e18);

        vm.expectRevert(
            abi.encodeWithSelector(OracleAdapter.OracleAdapterSequencerDown.selector, address(sequencerFeed))
        );
        taker.swap(order, address(tokenC), address(tokenA), 500e18, takerData);
    }

    /// @notice Group value can support a quote while tokenA has only one wei available.
    function test_RevertsOnInsufficientMemberBalanceFromRawBalanceImbalance() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, 1, 1_000_000e18, 1_000_000e18);

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000_000e18);

        // Unit prices make the expected group value balA + balB, with a 1:1 conversion to tokenA units.
        PortfolioManagerPricing.PoolState memory quote = PortfolioManagerPricing.PoolState({
            balanceIn: 1_000_000e18,
            balanceOut: 1 + 1_000_000e18,
            weightIn: groups[1].weight,
            weightOut: groups[0].weight,
            feeWad: 0
        });
        uint256 expectedRequested = PortfolioManagerPricing.exactIn(quote, 500_000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerSwap.PortfolioManagerSwapInsufficientMemberBalance.selector,
                address(tokenA),
                expectedRequested,
                1
            )
        );
        taker.swap(order, address(tokenC), address(tokenA), 500_000e18, takerData);
    }

    function test_RevertsOnInsufficientMemberBalanceFromRawBalanceImbalanceExactOut() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, 1, 1_000_000e18, 1_000_000e18);

        bytes memory takerData = _exactOutTakerData();
        tokenC.mint(address(taker), 1_000_000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerSwap.PortfolioManagerSwapInsufficientMemberBalance.selector,
                address(tokenA),
                500_000e18,
                1
            )
        );
        taker.swap(order, address(tokenC), address(tokenA), 500_000e18, takerData);
    }

    /// @notice A computed output can fit the maker's real wallet balance yet still exceed what
    ///         this strategy is actually authorized to pull from Aqua's own ledger -- the wallet
    ///         balance and the Aqua ledger amount are independent, not the same number.
    function test_RevertsOnInsufficientLedgerAuthorizationEvenWhenWalletBalanceIsAmple() public {
        ISwapVM.Order memory order = _buildOrder(0);

        // Wallet holds plenty of every token -- the OLD wallet-only check would pass.
        tokenA.mint(maker, 1_000_000e18);
        tokenB.mint(maker, 1_000_000e18);
        tokenC.mint(maker, 1_000_000e18);
        vm.startPrank(maker);
        tokenA.approve(address(aqua), type(uint256).max);
        tokenB.approve(address(aqua), type(uint256).max);
        tokenC.approve(address(aqua), type(uint256).max);
        vm.stopPrank();

        // Aqua's own ledger authorizes only 1 wei of tokenA for this strategy -- independent of
        // the real wallet balance above.
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1;
        amounts[1] = 1_000_000e18;
        amounts[2] = 1_000_000e18;

        strategyValidator.attestBuildParameters(order, tokens);
        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000_000e18);

        // Unit prices make the expected group value balA + balB, with a 1:1 conversion to tokenA units.
        PortfolioManagerPricing.PoolState memory quote = PortfolioManagerPricing.PoolState({
            balanceIn: 1_000_000e18,
            balanceOut: 2_000_000e18,
            weightIn: groups[1].weight,
            weightOut: groups[0].weight,
            feeWad: 0
        });
        uint256 expectedRequested = PortfolioManagerPricing.exactIn(quote, 500_000e18);

        // `available` reflects the ledger's 1 wei, not the wallet's ample balance -- confirms
        // the ledger check actually bound the result, not just the pre-existing wallet one.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerSwap.PortfolioManagerSwapInsufficientMemberBalance.selector,
                address(tokenA),
                expectedRequested,
                1
            )
        );
        taker.swap(order, address(tokenC), address(tokenA), 500_000e18, takerData);
    }

    /// @notice A pair can pass the deviation step cap but lack enough units of the output member.
    /// @dev The trade must stay small relative to the pool (ADR-0016 bounds the step this trade
    ///      itself causes, not the pool's starting balance) -- a trade large enough to drain a
    ///      meaningful fraction of the pool would trip the deviation check first, as it does in
    ///      test_ExcessivePriceDeviationBlocksTrade below.
    function test_InsufficientMemberBalanceStillFiresWithDeviationCheckArmedAndWithinTolerance() public {
        ISwapVM.Order memory order = _buildOrder(0, 0.1e9); // maxDeviationBps = 10%
        _shipOrder(order, 1, 1_000_000e18, 1_000_000e18); // group0 ~= group1 in value -> ~0% deviation

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000e18);

        PortfolioManagerPricing.PoolState memory quote = PortfolioManagerPricing.PoolState({
            balanceIn: 1_000_000e18,
            balanceOut: 1 + 1_000_000e18,
            weightIn: groups[1].weight,
            weightOut: groups[0].weight,
            feeWad: 0
        });
        uint256 expectedRequested = PortfolioManagerPricing.exactIn(quote, 1_000e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerSwap.PortfolioManagerSwapInsufficientMemberBalance.selector,
                address(tokenA),
                expectedRequested,
                1
            )
        );
        taker.swap(order, address(tokenC), address(tokenA), 1_000e18, takerData);
    }

    // ===== Price-deviation step cap (ADR-0012, superseded by ADR-0016) =====

    /// @dev ADR-0016: the cap bounds how far THIS trade moves the pair, not the pool's starting
    ///      deviation -- so this now starts perfectly balanced and uses one large trade to trip
    ///      the cap, instead of starting already-skewed with a small trade (which the new check
    ///      would let through, since its own step would be tiny).
    function test_ExcessivePriceDeviationBlocksTrade() public {
        ISwapVM.Order memory order = _buildOrder(0, 0.1e9); // maxDeviationBps = 10%
        _shipOrder(order, 50_000e18, 50_000e18, 100_000e18); // group0 = group1 = 100,000e18, balanced

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 50_000e18);

        // Equal weights reduce exactIn to xy=k: trading half the pool (50,000 of 100,000) moves
        // spotPrice(tokenC->tokenA) from 1.0 (balanced) to ~150,000/66,666.67 ~= 2.25 (2 wei under
        // from fixed-point rounding) -- a ~125% step in one trade, far past the 10% per-trade cap.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerSwap.PortfolioManagerSwapExcessivePriceDeviation.selector, 2.25e18 - 2, uint256(0.1e9)
            )
        );
        taker.swap(order, address(tokenC), address(tokenA), 50_000e18, takerData);
    }

    /// @dev The actual BLEUDEV-403 bug this ADR fixes: under the old pre-trade check (ADR-0012),
    ///      ANY trade against this 90%-deviated pair would have reverted outright, including this
    ///      corrective one -- freezing the pair until an external balance or price change. The
    ///      ADR-0016 step cap only bounds what THIS trade itself does, so a corrective trade whose
    ///      own step stays under the 10% cap now succeeds even though the pool started far outside
    ///      the band. (The trade stays small enough to also clear BLEUDEV-406's ledger-authorization
    ///      cap: `_shipOrder` only authorized 50,000e18 of tokenA, not the post-ship mint below.)
    function test_CorrectiveTradeSucceedsEvenWhenPoolStartedBeyondTheDeviationBand() public {
        ISwapVM.Order memory order = _buildOrder(0, 0.1e9); // maxDeviationBps = 10%
        _shipOrder(order, 50_000e18, 50_000e18, 100_000e18); // group0 = group1 = 100,000e18, at target

        // An external balance change pushes group0 to 90% deviation -- spotPrice(tokenC->tokenA)
        // = 100,000/1,000,000 = 0.1, far outside the 10% band.
        tokenA.mint(maker, 900_000e18);

        uint256 amountIn = 4_000e18;
        (, uint256 actualAmountOut) = _swapExactIn(order, address(tokenC), address(tokenA), amountIn);

        // This trade's own step (0.1 -> ~0.108, under 1%) stays well under the 10% cap, so it
        // prices and settles exactly like any other within-tolerance trade.
        PortfolioManagerPricing.PoolState memory expectedQuote = PortfolioManagerPricing.PoolState({
            balanceIn: 100_000e18,
            balanceOut: 1_000_000e18,
            weightIn: groups[1].weight,
            weightOut: groups[0].weight,
            feeWad: 0
        });
        uint256 expectedAmountOut = PortfolioManagerPricing.exactIn(expectedQuote, amountIn);
        assertEq(actualAmountOut, expectedAmountOut, "a corrective trade within its own step cap must succeed");
    }

    function test_PriceDeviationWithinToleranceStillPricesNormally() public {
        ISwapVM.Order memory order = _buildOrder(0, 0.1e9); // maxDeviationBps = 10%
        _shipOrder(order, 50_000e18, 50_000e18, 100_000e18); // group0 = group1 = 100,000e18

        // A 5% skew stays within the 10% limit.
        tokenA.mint(maker, 5_000e18);

        uint256 amountIn = 500e18;
        (, uint256 actualAmountOut) = _swapExactIn(order, address(tokenC), address(tokenA), amountIn);

        PortfolioManagerPricing.PoolState memory expectedQuote = PortfolioManagerPricing.PoolState({
            balanceIn: 100_000e18,
            balanceOut: 105_000e18,
            weightIn: groups[1].weight,
            weightOut: groups[0].weight,
            feeWad: 0
        });
        uint256 expectedAmountOut = PortfolioManagerPricing.exactIn(expectedQuote, amountIn);
        assertEq(actualAmountOut, expectedAmountOut, "within-tolerance trade must price exactly as without the check");
    }

    function test_ZeroMaxDeviationBpsDisablesTheCheckEvenUnderExtremeSkew() public {
        ISwapVM.Order memory order = _buildOrder(0, 0); // disabled
        _shipOrder(order, 50_000e18, 50_000e18, 100_000e18);

        // Same extreme 90%-deviation skew as test_ExcessivePriceDeviationBlocksTrade -- with the
        // breaker off, this must still price and settle, unchanged from before ADR-0012 existed.
        tokenA.mint(maker, 900_000e18);

        uint256 amountIn = 500e18;
        (, uint256 actualAmountOut) = _swapExactIn(order, address(tokenC), address(tokenA), amountIn);

        PortfolioManagerPricing.PoolState memory expectedQuote = PortfolioManagerPricing.PoolState({
            balanceIn: 100_000e18,
            balanceOut: 1_000_000e18,
            weightIn: groups[1].weight,
            weightOut: groups[0].weight,
            feeWad: 0
        });
        uint256 expectedAmountOut = PortfolioManagerPricing.exactIn(expectedQuote, amountIn);
        assertEq(actualAmountOut, expectedAmountOut, "maxDeviationBps == 0 must be a true no-op");
    }

    // ===== Fuzz: depeg divergence inside a multi-token group =====

    /// @notice Narrow-bound counterpart to the wide-bound test below. Balances stay large and
    /// even, and the depeg stays modest, so both legs always complete -- this is what actually
    /// proves round-trip non-profitability (ADR-0007). The wide-bound test only proves the check
    /// does not panic.
    /// @dev No try/catch: a revert here is a real finding, not an accepted outcome.
    function testFuzz_DepegDivergenceWithinGroupGuaranteedRoundTripNeverProfits(
        uint256 balA,
        uint256 balB,
        uint256 balC,
        uint256 priceA,
        uint256 priceB,
        uint256 amountIn
    ) public {
        balA = bound(balA, 100_000e18, 1_000_000e18);
        balB = bound(balB, 100_000e18, 1_000_000e18);
        balC = bound(balC, 100_000e18, 1_000_000e18);
        // Modest depeg -- still genuine price divergence, tight enough that a member's raw-
        // balance share can't fall far enough behind its group-value share to trip
        // InsufficientMemberBalance at these balance ranges.
        priceA = bound(priceA, 0.5e18, 2e18);
        priceB = bound(priceB, 0.5e18, 2e18);
        feedA.setAnswer(int256(priceA), block.timestamp);
        feedB.setAnswer(int256(priceB), block.timestamp);

        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, balA, balB, balC);

        // A real fraction of balC, not near-dust -- large enough that neither leg rounds to zero.
        amountIn = bound(amountIn, balC / 1000, balC / 100);

        (, uint256 amountOutA) = _swapExactIn(order, address(tokenC), address(tokenA), amountIn);
        (, uint256 amountBackC) = _swapExactIn(order, address(tokenA), address(tokenC), amountOutA);

        assertLe(
            amountBackC, amountIn, "round-tripping through a depegged multi-token group must not profit the trader"
        );
    }

    /// @notice Wide-bound stress test: group0 prices diverge up to a 90% haircut or 10x blowup.
    /// Extreme skew makes `InsufficientMemberBalance` and zero-amount reverts common, so this
    /// mainly checks the guard does not panic, not the round-trip invariant itself (see the
    /// narrow-bound test above for that).
    /// @dev Accepts `PortfolioManagerSwapInsufficientMemberBalance` or a zero-amount second leg
    ///      as non-violating reverts, asserted by selector, not caught blindly.
    function testFuzz_DepegDivergenceWithinGroupNeverPanicsAcrossExtremeSkew(
        uint256 balA,
        uint256 balB,
        uint256 balC,
        uint256 priceA,
        uint256 priceB,
        uint256 amountIn
    ) public {
        balA = bound(balA, 1e18, 1_000_000e18);
        balB = bound(balB, 1e18, 1_000_000e18);
        balC = bound(balC, 1e18, 1_000_000e18);
        // Vary member prices independently from $0.10 to $10.
        priceA = bound(priceA, 0.1e18, 10e18);
        priceB = bound(priceB, 0.1e18, 10e18);
        feedA.setAnswer(int256(priceA), block.timestamp);
        feedB.setAnswer(int256(priceB), block.timestamp);

        ISwapVM.Order memory order = _buildOrder(0); // feeBps = 0 isolates the curve's own invariant from the fee's own additional slack
        _shipOrder(order, balA, balB, balC);

        amountIn = bound(amountIn, 1e6, balC / 10);

        try this._externalSwapExactIn(order, address(tokenC), address(tokenA), amountIn) returns (
            uint256, uint256 amountOutA
        ) {
            if (amountOutA == 0) return;

            try this._externalSwapExactIn(order, address(tokenA), address(tokenC), amountOutA) returns (
                uint256, uint256 amountBackC
            ) {
                assertLe(
                    amountBackC,
                    amountIn,
                    "round-tripping through a depegged multi-token group must not profit the trader"
                );
            } catch (bytes memory reason) {
                _assertAcceptableRoundTripRevert(reason);
            }
        } catch (bytes memory reason) {
            _assertAcceptableRoundTripRevert(reason);
        }
    }

    /// @dev External entrypoint required by the fuzz test's try/catch.
    function _externalSwapExactIn(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount)
        external
        returns (uint256, uint256)
    {
        return _swapExactIn(order, tokenIn, tokenOut, amount);
    }

    function _assertAcceptableRoundTripRevert(bytes memory reason) private pure {
        bytes4 selector = bytes4(reason);
        assertTrue(
            selector == IPortfolioManagerSwap.PortfolioManagerSwapInsufficientMemberBalance.selector
                || selector == TakerTraitsLib.TakerTraitsAmountOutMustBeGreaterThanZero.selector,
            "unexpected revert reason during round trip"
        );
    }

    // ===== Gas optimization: oracle call dedup and numeraire members (BLEUDEV-412/ADR-0017) =====

    /// @dev Proves the actual BLEUDEV-412 fix: before it, the traded-out token's feed
    ///      (`feedA`, group0's member) was read once for group valuation and again for
    ///      native-unit conversion -- two `latestRoundData()` calls for one swap. Now exactly
    ///      one, for every traded or non-traded member alike.
    function test_EachFeedIsReadAtMostOncePerSwap() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE, INITIAL_BALANCE, INITIAL_BALANCE);

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000e18);

        bytes memory latestRoundDataCall = abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector);
        vm.expectCall(address(feedA), latestRoundDataCall, 1); // traded out, group0
        vm.expectCall(address(feedB), latestRoundDataCall, 1); // non-traded member, group0
        vm.expectCall(address(feedC), latestRoundDataCall, 1); // traded in, group1

        taker.swap(order, address(tokenC), address(tokenA), 500e18, takerData);
    }

    /// @dev Builds and ships a 2-group, single-member-per-side strategy with tokenA as the
    ///      numeraire (feed == address(0)) and tokenC priced via feedC -- shared by the numeraire
    ///      tests below.
    function _shipNumeraireOrder(uint32 maxDeviationBps, uint256 balA, uint256 balC)
        private
        returns (ISwapVM.Order memory order)
    {
        PortfolioManagerArgsCodec.Member[] memory numeraireMembers = new PortfolioManagerArgsCodec.Member[](1);
        numeraireMembers[0] =
            PortfolioManagerArgsCodec.Member({token: address(tokenA), feed: address(0), maxStaleness: 0});
        PortfolioManagerArgsCodec.Group[] memory customGroups = new PortfolioManagerArgsCodec.Group[](2);
        customGroups[0] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: numeraireMembers});

        PortfolioManagerArgsCodec.Member[] memory pricedMembers = new PortfolioManagerArgsCodec.Member[](1);
        pricedMembers[0] =
            PortfolioManagerArgsCodec.Member({token: address(tokenC), feed: address(feedC), maxStaleness: 1 hours});
        customGroups[1] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: pricedMembers});

        order = _buildOrderWithGroups(customGroups, 0, maxDeviationBps);

        address[] memory shipTokens = new address[](2);
        shipTokens[0] = address(tokenA);
        shipTokens[1] = address(tokenC);
        uint256[] memory shipAmounts = new uint256[](2);
        shipAmounts[0] = balA;
        shipAmounts[1] = balC;
        tokenA.mint(maker, balA);
        tokenC.mint(maker, balC);
        vm.startPrank(maker);
        tokenA.approve(address(aqua), type(uint256).max);
        tokenC.approve(address(aqua), type(uint256).max);
        vm.stopPrank();
        strategyValidator.attestBuildParameters(order, shipTokens);
        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), shipTokens, shipAmounts);
    }

    /// @dev A numeraire member (feed == address(0)) costs no oracle call at all, in either the
    ///      group-valuation or native-conversion step, and prices correctly: its native balance
    ///      is its value, exactly like plain Balancer-style weighted pools need no oracle when
    ///      both sides are already in one unit.
    function test_SwapAgainstANumeraireMemberNeedsNoOracleCallForIt() public {
        ISwapVM.Order memory order = _shipNumeraireOrder(0, 100_000e18, 100_000e18);

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000e18);

        // tokenA is the numeraire -- its own feed address is the zero address, so there is
        // nothing to call. Only feedC (tokenC, the priced member) should ever be read.
        vm.expectCall(address(feedC), abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector), 1);

        uint256 amountIn = 1_000e18;
        (, uint256 actualAmountOut) = _swapExactIn(order, address(tokenC), address(tokenA), amountIn);

        // Equal weights, both groups worth 100,000 WAD units (tokenA's numeraire balance;
        // tokenC's balance * $1 feed price) -- same xy=k math as any other balanced single-member
        // pair, just denominated in tokenA instead of USD.
        PortfolioManagerPricing.PoolState memory expectedQuote = PortfolioManagerPricing.PoolState({
            balanceIn: 100_000e18, balanceOut: 100_000e18, weightIn: 0.5e18, weightOut: 0.5e18, feeWad: 0
        });
        uint256 expectedAmountOut = PortfolioManagerPricing.exactIn(expectedQuote, amountIn);
        assertEq(actualAmountOut, expectedAmountOut, "numeraire member must price off its native balance directly");
    }

    /// @dev ADR-0016's per-trade deviation step cap is unit-agnostic by construction -- it only
    ///      ever compares quote.balanceIn/balanceOut ratios, never an absolute USD value -- so it
    ///      must keep working unchanged when the pair's shared unit is a numeraire token instead
    ///      of USD. A trade within the cap settles normally.
    function test_DeviationStepCapStillPricesNormallyWithinToleranceAgainstANumeraireMember() public {
        ISwapVM.Order memory order = _shipNumeraireOrder(0.1e9, 100_000e18, 100_000e18); // 10% cap

        // A small trade keeps the step well under 10%.
        uint256 amountIn = 1_000e18;
        (, uint256 actualAmountOut) = _swapExactIn(order, address(tokenC), address(tokenA), amountIn);

        PortfolioManagerPricing.PoolState memory expectedQuote = PortfolioManagerPricing.PoolState({
            balanceIn: 100_000e18, balanceOut: 100_000e18, weightIn: 0.5e18, weightOut: 0.5e18, feeWad: 0
        });
        uint256 expectedAmountOut = PortfolioManagerPricing.exactIn(expectedQuote, amountIn);
        assertEq(actualAmountOut, expectedAmountOut, "a within-cap trade against a numeraire pair must price normally");
    }

    /// @dev Same guarantee as the test above, from the other side: a trade whose step would
    ///      exceed the cap must still revert, computed from the numeraire-denominated quote.
    function test_DeviationStepCapStillBlocksExcessiveStepAgainstANumeraireMember() public {
        ISwapVM.Order memory order = _shipNumeraireOrder(0.1e9, 100_000e18, 100_000e18); // 10% cap

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 100_000e18);

        // Equal weights reduce exactIn to xy=k: trading half the pool (50,000 of 100,000) moves
        // spotPrice(tokenC->tokenA) from 1.0 to ~2.25 -- a ~125% step, same math (and same
        // expected revert value) as the non-numeraire version of this scenario.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerSwap.PortfolioManagerSwapExcessivePriceDeviation.selector, 2.25e18 - 2, uint256(0.1e9)
            )
        );
        taker.swap(order, address(tokenC), address(tokenA), 50_000e18, takerData);
    }
}
