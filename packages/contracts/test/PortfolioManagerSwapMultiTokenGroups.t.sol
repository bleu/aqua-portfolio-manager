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
import {IPortfolioManagerSwap} from "../src/interfaces/IPortfolioManagerSwap.sol";
import {OracleAdapter} from "../src/utils/OracleAdapter.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice Real multi-token oracle-valued groups (ADR-0003), exercised through a
/// real SwapVM.swap() call: behavior that's meaningless to test at a single-token-group scope --
/// same-group rejection, a 2-member group's price reflecting its FULL oracle-valued sum (not
/// just the token actually changing hands), and a stale feed on a non-traded group member still
/// blocking the trade (ADR-0005: "every member fresh, not just the two changing hands").
/// `PortfolioManagerOpcodes.t.sol` already covers the protocol-fee mechanics this file doesn't
/// repeat; `OracleAdapter.t.sol` already covers `groupValueWad`'s own math in isolation.
contract PortfolioManagerSwapMultiTokenGroupsTest is Test {
    uint256 internal constant INITIAL_BALANCE = 100_000e18;

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    TokenMock internal tokenC;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;
    MockAggregatorV3 internal feedC;
    MockTaker internal taker;

    address internal maker;

    /// @dev group0 = {tokenA, tokenB} (2 members), group1 = {tokenC} (1 member) -- deliberately
    ///      mixes a multi-member and a single-member group in the same universe, since both must
    ///      resolve through the same uniform oracle path.
    PortfolioManagerArgsCodec.Group[] internal groups;

    function setUp() public {
        aqua = new Aqua();
        router = new PortfolioManagerRouter(address(aqua), address(0), address(this), "PM", "1");

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");
        tokenC = new TokenMock("Token C", "TKC");

        // $1.00 per token (18-decimal feed) by default -- a group's oracle-valued sum then
        // equals the plain sum of its members' balances, keeping the arithmetic in each test
        // easy to reason about independently.
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
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, lpFeeBps, maxDeviationBps);
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

    /// @param balA/balB/balC Real wallet balances (ADR-0002) -- also shipped 1:1 as the Aqua
    ///        ledger amount for each token, since none of these tests exercise the ledger/wallet
    ///        divergence PortfolioManagerOpcodes.t.sol's fee-skip tests already cover.
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

        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
    }

    function _swapExactIn(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount)
        internal
        returns (uint256, uint256)
    {
        bytes memory takerData = _exactInTakerData();

        TokenMock(tokenIn).mint(address(taker), amount * 2);
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

    function test_SameGroupSwapReverts() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE, INITIAL_BALANCE, INITIAL_BALANCE);

        bytes memory takerData = _exactInTakerData();
        tokenA.mint(address(taker), 1_000e18);

        // tokenA and tokenB are both members of group0 -- the curve only prices cross-group
        // pairs (ADR-0003), so this must revert rather than silently degenerate to a spot price
        // of exactly 1.
        vm.expectRevert(
            abi.encodeWithSelector(IPortfolioManagerSwap.PortfolioManagerSwapSameGroupSwap.selector, uint256(0))
        );
        taker.swap(order, address(tokenA), address(tokenB), 500e18, takerData);
    }

    function test_MultiMemberGroupPricesOffFullGroupValueNotJustTheTradedToken() public {
        // group0's members are funded unevenly (1,000 / 99,000) but sum to the same 100,000 as
        // group1's single member -- a perfectly balanced 50/50 universe by GROUP value, even
        // though tokenA alone holds only 1% of group0's real value.
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

        // Wrong expectation (what a regression to single-token-only pricing would compute):
        // balanceOut = tokenA's own raw balance alone, ignoring tokenB entirely. With balA this
        // small relative to amountIn, that pool looks far more skewed/thin, so it would yield a
        // strictly worse (smaller) output than the correct group-valued quote above.
        PortfolioManagerPricing.PoolState memory wrongPoolState = PortfolioManagerPricing.PoolState({
            balanceIn: balC, balanceOut: balA, weightIn: groups[1].weight, weightOut: groups[0].weight, feeWad: 0
        });
        uint256 wrongAmountOut = PortfolioManagerPricing.exactIn(wrongPoolState, amountIn);
        assertGt(
            actualAmountOut, wrongAmountOut, "must clearly differ from a single-token-only (tokenA-balance-only) quote"
        );
    }

    function test_StaleFeedOnNonTradedGroupMemberBlocksTrade() public {
        // Default forge-std block.timestamp starts near 0 -- warp forward first so `- 2 hours`
        // below can't underflow, then refresh every feed except feedB (the one under test) so
        // only feedB's own staleness is what's actually being exercised here.
        vm.warp(365 days);
        feedA.setAnswer(1e18, block.timestamp);
        feedC.setAnswer(1e18, block.timestamp);

        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE, INITIAL_BALANCE, INITIAL_BALANCE);

        // tokenB's own feed goes stale -- tokenB is a member of group0 but is NOT one of the two
        // tokens actually changing hands in the trade below (tokenC -> tokenA). Per ADR-0005,
        // every declared member's feed must be fresh, not just the traded pair's.
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

    /// @notice Deterministic reproduction of PortfolioManagerSwapInsufficientMemberBalance,
    /// rather than relying on the fuzz test below to land on it by chance: tokenA holds 1 wei
    /// while tokenB (same group, same $1 price -- no depeg needed to trigger this) holds
    /// 1,000,000 tokens, so group0's value is almost entirely tokenB's. A trade sized off that
    /// value asks for far more raw tokenA than the 1 wei that actually exists.
    function test_RevertsOnInsufficientMemberBalanceFromRawBalanceImbalance() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, 1, 1_000_000e18, 1_000_000e18);

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000_000e18);

        // Independently computed expected `requested`, the same way
        // test_MultiMemberGroupPricesOffFullGroupValueNotJustTheTradedToken does: both tokens are
        // still pegged at $1 here (this reproduction doesn't need a real depeg, just a raw
        // balance far below a group's value share), so group0's value is exactly balA + balB and
        // the value-to-tokenA-raw-units conversion is 1:1.
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

    /// @notice Exact-out counterpart to `test_RevertsOnInsufficientMemberBalanceFromRawBalanceImbalance`
    /// -- the new check sits after the shared exactIn/exactOut branch (`PortfolioManagerSwap.sol`),
    /// so it must catch this on both entry points, not just exactIn. Same fixture: tokenA holds 1
    /// wei, tokenB holds 1,000,000e18. Unlike exactIn, `amountOut` here is the taker's own direct
    /// input, so the expected revert value is just the requested amount, not a formula result.
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

    // ===== Price-deviation circuit breaker (ADR-0012) =====

    function test_ExcessivePriceDeviationBlocksTrade() public {
        ISwapVM.Order memory order = _buildOrder(0, 0.1e9); // maxDeviationBps = 10%
        _shipOrder(order, 50_000e18, 50_000e18, 100_000e18); // group0 = group1 = 100,000e18, at target

        // A direct balance change outside ship()/swap() entirely (e.g. the Safe owner's own
        // withdrawal, or here, a donation) -- group0 (tokenA+tokenB) balloons to 1,000,000e18
        // while group1 stays at 100,000e18, far past the 10% band around the 50/50 target.
        tokenA.mint(maker, 900_000e18);

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), 1_000e18);

        // spotPrice(tokenC->tokenA) = (100,000/0.5) / (1,000,000/0.5) = 0.1e18 exactly (equal
        // weights cancel), i.e. 90% deviation from WAD -- well past the 10% ceiling.
        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerSwap.PortfolioManagerSwapExcessivePriceDeviation.selector, 0.1e18, uint256(0.1e9)
            )
        );
        taker.swap(order, address(tokenC), address(tokenA), 500e18, takerData);
    }

    function test_PriceDeviationWithinToleranceStillPricesNormally() public {
        ISwapVM.Order memory order = _buildOrder(0, 0.1e9); // maxDeviationBps = 10%
        _shipOrder(order, 50_000e18, 50_000e18, 100_000e18); // group0 = group1 = 100,000e18

        // Only a mild 5% skew -- group0 grows to 105,000e18, group1 stays at 100,000e18, still
        // inside the 10% band, so the trade must price exactly as it would with the check absent.
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

    /// @notice group0's two members (tokenA, tokenB) are fuzzed to independently diverging
    /// prices -- a depeg -- while group1 (tokenC) stays healthy. Round-trip non-profitability
    /// (DONATION-RESISTANCE-PROOF.md/ADR-0007) is already fuzz-tested at the pure
    /// `PortfolioManagerPricing` level; this exercises the same guarantee through the real
    /// `OracleAdapter`-summed group value of a divergently-priced multi-token group, not a value
    /// handed to the formula directly.
    /// @dev Either leg may legitimately revert with `PortfolioManagerSwapInsufficientMemberBalance`
    /// (a low-priced minority member's raw balance smaller than its share of group value) or
    /// swap-vm's `TakerTraitsAmountOutMustBeGreaterThanZero` (a tiny second-leg trade rounding to
    /// zero). Both asserted by selector, not caught blindly. The invariant is only asserted when
    /// both legs actually complete.
    function testFuzz_DepegDivergenceWithinGroupNeverProfitsRoundTripTrader(
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
        // A realistic depeg range: anywhere from a 90% haircut to a 10x blowup, independently
        // for each of group0's two members -- e.g. tokenA depegs to $0.10 while tokenB holds
        // near $1, or both drift in opposite directions.
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

    /// @dev `try` requires an external call -- `_swapExactIn` is internal, so this thin wrapper
    ///      is what the fuzz test above actually calls via `this._externalSwapExactIn(...)`.
    function _externalSwapExactIn(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount)
        external
        returns (uint256, uint256)
    {
        return _swapExactIn(order, tokenIn, tokenOut, amount);
    }

    /// @dev The two legitimate ways a round-trip leg can revert without violating the invariant
    ///      this fuzz test checks -- see the test's own doc comment for why each is acceptable.
    function _assertAcceptableRoundTripRevert(bytes memory reason) private pure {
        bytes4 selector = bytes4(reason);
        assertTrue(
            selector == IPortfolioManagerSwap.PortfolioManagerSwapInsufficientMemberBalance.selector
                || selector == TakerTraitsLib.TakerTraitsAmountOutMustBeGreaterThanZero.selector,
            "unexpected revert reason during round trip"
        );
    }
}
