// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Aqua} from "aqua/Aqua.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";

import {AquaE2EBase} from "./base/AquaE2EBase.t.sol";
import {PortfolioManagerRouter} from "../../src/PortfolioManagerRouter.sol";
import {PortfolioManagerArgsCodec} from "../../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "../../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerStrategyValidator} from "../../src/PortfolioManagerStrategyValidator.sol";
import {IPortfolioManagerStrategyValidator} from "../../src/interfaces/IPortfolioManagerStrategyValidator.sol";
import {PortfolioManagerPricing} from "../../src/utils/PortfolioManagerPricing.sol";
import {OracleAdapter} from "../../src/utils/OracleAdapter.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {MockTaker} from "../../lib/swap-vm/test/mocks/MockTaker.sol";

/// @notice Real multi-token oracle-valued groups (ADR-0003), end to end against a
/// real Base fork -- a "majors" group {WETH, WBTC} and a "stables" group {DAI, USDT, USDC}, each
/// member priced through its own real Chainlink feed. `PortfolioManagerE2EBase.t.sol`'s
/// single-group suite already covers protocol-fee and basic curve mechanics end to end; this
/// file's job is specifically proving the multi-member group-valuation path
/// (`OracleAdapter.groupValueWad`) works correctly against real balances and real live prices,
/// not a mock.
///
/// Deliberately self-contained beyond `AquaE2EBase`'s shared Aqua/Safe infra (own Router/
/// StrategyValidator/MultiSendCallOnly, not `PortfolioManagerE2EBase`) -- that base's PM-specific
/// fields are hard-shaped around a 2-token, single-member-group universe; this fixture's 5-token,
/// 2-group universe doesn't fit it.
contract PortfolioManagerMultiTokenBasketE2ETest is AquaE2EBase {
    uint256 internal constant MAJORS_WEIGHT = 0.5e18;
    uint256 internal constant STABLES_WEIGHT = 0.5e18;

    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    /// @dev WBTC on Base — https://basescan.org/token/0x1cea84203673764244e05693e42e6ace62be9ba5
    address internal constant WBTC_BASE = 0x1ceA84203673764244E05693e42E6Ace62bE9BA5;
    /// @dev DAI on Base — https://basescan.org/token/0x50c5725949a6f0c72e6c4a641f24049a917db0cb
    address internal constant DAI_BASE = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    /// @dev USDT on Base — https://basescan.org/token/0xfde4c96c8593536e31f229ea8f37b2ada2699bb2
    address internal constant USDT_BASE = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    /// @dev USDC on Base — https://basescan.org/token/0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
    address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @dev Chainlink ETH/USD on Base — https://basescan.org/address/0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70
    address internal constant ETH_USD_FEED_BASE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    /// @dev Chainlink BTC/USD on Base — https://basescan.org/address/0x64c911996d3c6ac71f9b455b1e8e7266bcbd848f
    address internal constant BTC_USD_FEED_BASE = 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F;
    /// @dev Chainlink DAI/USD on Base — https://basescan.org/address/0x591e79239a7d679378ec8c847e5038150364c78f
    address internal constant DAI_USD_FEED_BASE = 0x591e79239a7d679378eC8c847e5038150364C78F;
    /// @dev Chainlink USDT/USD on Base — https://basescan.org/address/0xf19d560eb8d2adf07bd6d13ed03e1d11215721f9
    address internal constant USDT_USD_FEED_BASE = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    /// @dev Chainlink USDC/USD on Base — https://basescan.org/address/0x7e860098f58bbfc8648a4311b374b1d669a2bc6b
    address internal constant USDC_USD_FEED_BASE = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;

    /// @dev The packed encoding's maxStaleness field is a uint16 (max ~18.2 hours).
    uint256 internal constant MULTI_TOKEN_MAX_STALENESS = 12 hours;

    uint256 internal constant WETH_FUNDING = 20e18;
    uint256 internal constant WBTC_FUNDING = 1e8;
    uint256 internal constant DAI_FUNDING = 60_000e18;
    uint256 internal constant USDT_FUNDING = 30_000e6;
    uint256 internal constant USDC_FUNDING = 30_000e6;

    PortfolioManagerRouter internal router;
    Safe internal multiTokenSafe;
    MockTaker internal taker;
    PortfolioManagerStrategyValidator internal strategyValidator;
    MultiSendCallOnly internal multiSendCallOnly;

    IERC20 internal weth;
    IERC20 internal wbtc;
    IERC20 internal dai;
    IERC20 internal usdt;
    IERC20 internal usdc;
    address internal wethFeed;
    address internal wbtcFeed;
    address internal daiFeed;
    address internal usdtFeed;
    address internal usdcFeed;
    uint256 internal maxStaleness;

    /// @dev groups[0] = majors {WETH, WBTC}, groups[1] = stables {DAI, USDT, USDC}.
    PortfolioManagerArgsCodec.Group[] internal groups;

    function setUp() public override {
        super.setUp();

        router = new PortfolioManagerRouter(address(aqua), WETH_BASE, deployer, "AquaPortfolioManager", "1");
        strategyValidator = new PortfolioManagerStrategyValidator();
        multiSendCallOnly = new MultiSendCallOnly();
        multiTokenSafe = _newSafe(2); // distinct salt nonce from the other E2E fixtures' Safes

        weth = IERC20(WETH_BASE);
        wbtc = IERC20(WBTC_BASE);
        dai = IERC20(DAI_BASE);
        usdt = IERC20(USDT_BASE);
        usdc = IERC20(USDC_BASE);
        wethFeed = ETH_USD_FEED_BASE;
        wbtcFeed = BTC_USD_FEED_BASE;
        daiFeed = DAI_USD_FEED_BASE;
        usdtFeed = USDT_USD_FEED_BASE;
        usdcFeed = USDC_USD_FEED_BASE;
        maxStaleness = MULTI_TOKEN_MAX_STALENESS;

        taker = new MockTaker(aqua, router, address(this));

        PortfolioManagerArgsCodec.Member[] memory majors = new PortfolioManagerArgsCodec.Member[](2);
        majors[0] = PortfolioManagerArgsCodec.Member({token: address(weth), feed: wethFeed, maxStaleness: maxStaleness});
        majors[1] = PortfolioManagerArgsCodec.Member({token: address(wbtc), feed: wbtcFeed, maxStaleness: maxStaleness});
        groups.push(PortfolioManagerArgsCodec.Group({weight: MAJORS_WEIGHT, members: majors}));

        PortfolioManagerArgsCodec.Member[] memory stables = new PortfolioManagerArgsCodec.Member[](3);
        stables[0] = PortfolioManagerArgsCodec.Member({token: address(dai), feed: daiFeed, maxStaleness: maxStaleness});
        stables[1] =
            PortfolioManagerArgsCodec.Member({token: address(usdt), feed: usdtFeed, maxStaleness: maxStaleness});
        stables[2] =
            PortfolioManagerArgsCodec.Member({token: address(usdc), feed: usdcFeed, maxStaleness: maxStaleness});
        groups.push(PortfolioManagerArgsCodec.Group({weight: STABLES_WEIGHT, members: stables}));
    }

    // ===== Helpers =====

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        return _buildOrder(lpFeeBps, 0);
    }

    function _buildOrder(uint32 lpFeeBps, uint32 maxDeviationBps) internal view returns (ISwapVM.Order memory) {
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, lpFeeBps, maxDeviationBps);
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: address(multiTokenSafe),
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

    /// @dev Batches `PortfolioManagerStrategyValidator.requireUniverseMatches` and
    ///      `requireBalancedWithinTolerance` with the real `Aqua.ship` call via
    ///      `MultiSendCallOnly` -- see `PortfolioManagerE2EBase.t.sol`'s identical note on why
    ///      this doesn't route through the validator itself.
    function _shipOnly(ISwapVM.Order memory order) internal returns (bytes32) {
        bool ok = _shipRaw(order, WETH_FUNDING, WBTC_FUNDING, DAI_FUNDING, USDT_FUNDING, USDC_FUNDING);
        require(ok, "ship through multi-token PM Safe failed");

        bytes32 strategyHash = keccak256(abi.encode(order));
        assertEq(strategyHash, router.hash(order), "strategy hash must match order hash");
        return strategyHash;
    }

    /// @dev Funding amounts split out of `_shipOnly` (which always uses the fixture's own
    ///      defaults) so a deviation-tolerance test can fund the wallet deliberately off-target.
    ///      Deliberately returns the raw `execTransaction` success bool with no `require` --
    ///      `vm.expectRevert` needs the original revert (e.g. a custom error from the tolerance
    ///      check) to reach it directly, not get replaced by a generic string reason.
    function _shipRaw(
        ISwapVM.Order memory order,
        uint256 wethAmount,
        uint256 wbtcAmount,
        uint256 daiAmount,
        uint256 usdtAmount,
        uint256 usdcAmount
    ) internal returns (bool) {
        (address[] memory tokens, uint256[] memory amounts) =
            _fundAndApprove(wethAmount, wbtcAmount, daiAmount, usdtAmount, usdcAmount);
        return _execShipBatch(order, tokens, amounts);
    }

    /// @dev Deals real balances and approves Aqua -- split out of `_shipRaw` so a revert-testing
    ///      caller can arm `vm.expectRevert()` immediately before the single call that should
    ///      revert (`_execShipBatch`), not before these several real, non-reverting external
    ///      calls (`balanceOf`/`approve`), which would otherwise consume `expectRevert`'s "next
    ///      call" slot instead -- same pitfall `test_StaleFeedEventuallyBlocksTrade` already
    ///      documents for `deal()`.
    function _fundAndApprove(
        uint256 wethAmount,
        uint256 wbtcAmount,
        uint256 daiAmount,
        uint256 usdtAmount,
        uint256 usdcAmount
    ) internal returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](5);
        tokens[0] = address(weth);
        tokens[1] = address(wbtc);
        tokens[2] = address(dai);
        tokens[3] = address(usdt);
        tokens[4] = address(usdc);

        // deal() only mutates a forge *script*'s own local simulation state, not the live node
        // it broadcasts against -- Deploy.mock.multitoken.sol's own deal() calls never actually
        // persist on chain (confirmed empirically: the safe's real balance is 0 immediately
        // after that script runs). Real funding has to happen here, inside the test itself,
        // same as PortfolioManagerE2EBase.t.sol's `_fundAndShip` already does for the
        // single-group fixture.
        deal(address(weth), address(multiTokenSafe), wethAmount);
        deal(address(wbtc), address(multiTokenSafe), wbtcAmount);
        deal(address(dai), address(multiTokenSafe), daiAmount);
        deal(address(usdt), address(multiTokenSafe), usdtAmount);
        deal(address(usdc), address(multiTokenSafe), usdcAmount);

        amounts = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = IERC20(tokens[i]).balanceOf(address(multiTokenSafe));
        }

        vm.startPrank(address(multiTokenSafe));
        for (uint256 i = 0; i < 5; i++) {
            IERC20(tokens[i]).approve(address(aqua), type(uint256).max);
        }
        vm.stopPrank();
    }

    function _execShipBatch(ISwapVM.Order memory order, address[] memory tokens, uint256[] memory amounts)
        internal
        returns (bool)
    {
        bytes memory validateData =
            abi.encodeCall(PortfolioManagerStrategyValidator.requireUniverseMatches, (order, tokens));
        bytes memory toleranceData =
            abi.encodeCall(PortfolioManagerStrategyValidator.requireBalancedWithinTolerance, (order, order.maker));
        bytes memory shipData = abi.encodeCall(Aqua.ship, (address(router), abi.encode(order), tokens, amounts));

        bytes memory batch = abi.encodePacked(
            _encodeMultiSendTx(address(strategyValidator), validateData),
            _encodeMultiSendTx(address(strategyValidator), toleranceData),
            _encodeMultiSendTx(address(aqua), shipData)
        );
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (batch));

        vm.prank(deployer);
        return multiTokenSafe.execTransaction(
            address(multiSendCallOnly),
            0,
            multiSendData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _selfApprovedSignature()
        );
    }

    function _encodeMultiSendTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
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

    function _swapExactIn(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount)
        internal
        returns (uint256, uint256)
    {
        bytes memory takerData = _exactInTakerData();
        deal(tokenIn, address(taker), amount * 2);
        return taker.swap(order, tokenIn, tokenOut, amount, takerData);
    }

    /// @dev Independently replicates `PortfolioManagerSwap._groupValueWad` (real balance ×
    ///      real live price, normalized by the token's own decimals) so tests can assert an
    ///      analytically-derived expected quote against the actual swap output, the same pattern
    ///      `PortfolioManagerSwapMultiTokenGroups.t.sol`'s unit tests use.
    function _groupValueWad(PortfolioManagerArgsCodec.Member[] memory members) internal view returns (uint256 total) {
        for (uint256 i = 0; i < members.length; i++) {
            OracleAdapter.PriceFeed memory feed = OracleAdapter.PriceFeed({
                feed: AggregatorV3Interface(members[i].feed), maxStaleness: members[i].maxStaleness
            });
            uint256 price = OracleAdapter.priceWad(feed);
            uint8 decimals = IERC20Metadata(members[i].token).decimals();
            total += IERC20(members[i].token).balanceOf(address(multiTokenSafe)) * price / 10 ** decimals;
        }
    }

    /// @dev Same per-token conversion `_groupValueWad` does for a whole group, but for an
    ///      arbitrary token amount -- used to put two different tokens' realized swap amounts on
    ///      a common WAD-scaled USD footing for a rate comparison.
    function _usdValueWad(address token, address feed, uint256 amount) internal view returns (uint256) {
        OracleAdapter.PriceFeed memory pf =
            OracleAdapter.PriceFeed({feed: AggregatorV3Interface(feed), maxStaleness: maxStaleness});
        uint256 price = OracleAdapter.priceWad(pf);
        uint8 decimals = IERC20Metadata(token).decimals();
        return amount * price / 10 ** decimals;
    }

    // ===== Tests =====

    // Each test below builds its order with a distinct feeBps (0/1/2/3, all negligible at
    // PM_BPS scale) purely so it encodes to a distinct strategyHash -- on a real `--rpc-url`
    // fork, state isn't reset between test functions the way the default in-memory backend
    // does, so byte-identical orders across tests would collide on the same already-shipped
    // Aqua ledger entry (same trick PortfolioManagerSkewWorseningE2E.t.sol's own reversed-
    // universe order and PortfolioManagerShipE2E.t.sol's "LOW_TIER_FEE_BPS + 1" already use).

    function test_ShipsTwoGroupStrategyAndLedgerReflectsIt() public {
        ISwapVM.Order memory order = _buildOrder(0);
        // _shipOnly funds the wallet itself (see its own note on why) -- WETH_FUNDING is the
        // known, fixed amount it deals, so there's no need to read the balance beforehand.
        bytes32 strategyHash = _shipOnly(order);

        (uint248 ledgerBalance, uint8 tokensCount) =
            aqua.rawBalances(address(multiTokenSafe), address(router), strategyHash, address(weth));
        assertEq(ledgerBalance, WETH_FUNDING, "Aqua's ledger must reflect the real WETH balance shipped");
        assertEq(tokensCount, 5, "Aqua's ledger must track all 5 declared tokens for this strategy");
    }

    function test_CrossGroupTradePricesOffBothGroupsFullOracleValuedSum() public {
        ISwapVM.Order memory order = _buildOrder(1);
        _shipOnly(order);

        // Trade direction: taker gives USDC (stables), receives WETH (majors) -- so balanceIn is
        // the stables group's full sum, balanceOut is the majors group's full sum. Majors' real
        // funding (20 WETH vs. 1 WBTC) is deliberately uneven, so a correct group-valued quote
        // can only be reproduced by summing both members, not by reading WETH alone.
        uint256 correctBalanceIn = _groupValueWad(groups[1].members);
        uint256 correctBalanceOut = _groupValueWad(groups[0].members);

        uint256 usdcAmountIn = 300e6; // 300 USDC, well within the stables group's funded balance

        PortfolioManagerPricing.PoolState memory correctPoolState = PortfolioManagerPricing.PoolState({
            balanceIn: correctBalanceIn,
            balanceOut: correctBalanceOut,
            weightIn: STABLES_WEIGHT,
            weightOut: MAJORS_WEIGHT,
            feeWad: 0
        });

        // Wrong expectation (what a regression to single-token-only pricing would compute):
        // balanceOut = WETH's own oracle value alone, ignoring WBTC entirely.
        uint256 wethOnlyValueWad = _usdValueWad(address(weth), wethFeed, weth.balanceOf(address(multiTokenSafe)));
        PortfolioManagerPricing.PoolState memory wrongPoolState = PortfolioManagerPricing.PoolState({
            balanceIn: correctBalanceIn,
            balanceOut: wethOnlyValueWad,
            weightIn: STABLES_WEIGHT,
            weightOut: MAJORS_WEIGHT,
            feeWad: 0
        });

        // PortfolioManagerPricing.exactIn expects amountIn in the SAME numeraire as
        // balanceIn/balanceOut (oracle-VALUE-scaled WAD here, per ADR-0003) -- not USDC's own
        // native 6-decimal units. Convert in, then convert the result back to WETH's own native
        // units, mirroring exactly what PortfolioManagerSwap._portfolioManagerSwapXD itself does.
        uint256 usdcAmountInValueWad = _usdValueWad(address(usdc), usdcFeed, usdcAmountIn);
        uint256 expectedCorrectOutValueWad = PortfolioManagerPricing.exactIn(correctPoolState, usdcAmountInValueWad);
        uint256 expectedWrongOutValueWad = PortfolioManagerPricing.exactIn(wrongPoolState, usdcAmountInValueWad);

        uint256 wethPriceWad = OracleAdapter.priceWad(
            OracleAdapter.PriceFeed({feed: AggregatorV3Interface(wethFeed), maxStaleness: maxStaleness})
        );
        uint256 expectedCorrectOut = expectedCorrectOutValueWad * 1e18 / wethPriceWad;
        uint256 expectedWrongOut = expectedWrongOutValueWad * 1e18 / wethPriceWad;

        (, uint256 actualAmountOut) = _swapExactIn(order, address(usdc), address(weth), usdcAmountIn);

        // assertApproxEqAbs, not assertEq: this test's own independent conversion (value WAD ->
        // WETH native units as two separate divisions) and the production code's single-pass
        // conversion round in the same direction but not always to the identical wei -- a dust-
        // level (<0.001%) tolerance, not a real discrepancy.
        assertApproxEqAbs(
            actualAmountOut,
            expectedCorrectOut,
            expectedCorrectOut / 1e5,
            "must price off majors' full WETH+WBTC oracle-valued sum"
        );
        // A WETH-balance-only quote UNDERstates the majors group's real value (WBTC is real
        // value ignored, not double-counted), which understates balanceOut and so understates
        // amountOut too (amountOut scales with balanceOut at fixed weights/balanceIn) -- so the
        // correct, WBTC-inclusive output must come out strictly LARGER than that quote, not
        // smaller.
        assertGt(
            actualAmountOut,
            expectedWrongOut,
            "a WETH-balance-only quote (ignoring WBTC) would understate the majors group's value and yield less output"
        );
    }

    /// @notice Unlike `test_SkewReducingBeatsSkewWorseningAtTheSameTradeSize` (which deliberately
    /// resets state via `vm.snapshotState()` between its two trades to isolate a single-trade
    /// comparison), this fires two same-direction trades back to back with no reset -- proving
    /// the second one gets a strictly worse rate purely because the first trade's real balance
    /// change (read fresh via `balanceOf`, ADR-0002) feeds into the second trade's quote. Neither
    /// the pure-library fuzz suite (`PortfolioManagerPricing.t.sol`) nor any other E2E test here
    /// exercises this: the fuzz tests call `exactIn` once per run against synthetic balances,
    /// with no second call carrying the first's output back in as new state.
    function test_SecondTradeInSameDirectionGetsWorseRateThanTheFirst() public {
        ISwapVM.Order memory order = _buildOrder(6);
        _shipOnly(order);

        uint256 amountIn = 300e6; // 300 USDC each time, well within the funded stables balance

        (, uint256 firstOut) = _swapExactIn(order, address(usdc), address(weth), amountIn);
        (, uint256 secondOut) = _swapExactIn(order, address(usdc), address(weth), amountIn);

        assertLt(
            secondOut,
            firstOut,
            "a second same-direction trade must get a worse rate once the first trade's real balance change is priced in"
        );
    }

    function test_SkewReducingBeatsSkewWorseningAtTheSameTradeSize() public {
        ISwapVM.Order memory order = _buildOrder(2);
        _shipOnly(order);

        // Donate extra DAI directly to the wallet (a real ERC20 balance change, not a PM trade,
        // same "external skew" pattern PortfolioManagerSkewReducingE2E.t.sol uses) -- pushes the
        // stables group's value above its 50% target share of the total portfolio.
        deal(address(dai), address(multiTokenSafe), dai.balanceOf(address(multiTokenSafe)) + 40_000e18);

        uint256 snapshot = vm.snapshotState();

        // Skew-reducing: the wallet sheds the overweight side -- taker gives WETH (majors),
        // receives USDC (stables).
        (, uint256 reducingOut) = _swapExactIn(order, address(weth), address(usdc), 0.05e18);

        vm.revertToState(snapshot);

        // Skew-worsening: the wallet gains even more of the already-overweight side -- taker
        // gives USDC (stables), receives WETH (majors).
        (uint256 worseningIn, uint256 worseningOut) = _swapExactIn(order, address(usdc), address(weth), 300e6);

        // The two trades swap in opposite directions between differently-valued tokens, so
        // compare a common WAD-scaled "USD out per USD in" rate (using the same live oracle
        // prices the curve itself used), not the raw output amounts directly.
        uint256 reducingRateWad =
            _usdValueWad(address(usdc), usdcFeed, reducingOut) * 1e18 / _usdValueWad(address(weth), wethFeed, 0.05e18);
        uint256 worseningRateWad = _usdValueWad(address(weth), wethFeed, worseningOut) * 1e18
            / _usdValueWad(address(usdc), usdcFeed, worseningIn);

        assertGt(
            reducingRateWad,
            worseningRateWad,
            "shedding an overweight group must be priced better than piling further into it, per PRICING.md"
        );
    }

    function test_StaleFeedEventuallyBlocksTrade() public {
        ISwapVM.Order memory order = _buildOrder(3);
        _shipOnly(order);

        // Real Chainlink feeds each update on their own independent cadence -- unlike the mock
        // feeds PortfolioManagerSwapMultiTokenGroups.t.sol's unit tests use, there's no way to
        // control exactly which declared member goes stale first here. Warping past the OLDEST
        // member's own updatedAt + maxStaleness guarantees at least that one is stale; that
        // member's own feed/timestamp is tracked so the exact revert can still be asserted
        // (the "even a non-traded member's staleness blocks the trade" claim itself is already
        // proven precisely, with full mock control, by that unit test).
        address[5] memory feeds = [wethFeed, wbtcFeed, daiFeed, usdtFeed, usdcFeed];
        uint256 oldestUpdatedAt = type(uint256).max;
        address oldestFeed;
        for (uint256 i = 0; i < feeds.length; i++) {
            (,,, uint256 updatedAt,) = AggregatorV3Interface(feeds[i]).latestRoundData();
            if (updatedAt < oldestUpdatedAt) {
                oldestUpdatedAt = updatedAt;
                oldestFeed = feeds[i];
            }
        }

        // The fork's feed data is frozen at the fork block -- warping past the oldest member's
        // own maxStaleness window is a real, live way to trigger staleness, not a mock.
        vm.warp(oldestUpdatedAt + maxStaleness + 1);

        // Funds the taker and builds calldata BEFORE arming expectRevert, then calls
        // taker.swap() directly (not through _swapExactIn) -- vm.expectRevert only tracks the
        // very next call frame, and an intervening deal() between arming it and the real call
        // (as _swapExactIn's own internal ordering does) consumes that slot instead.
        uint256 amount = 300e6;
        deal(address(usdc), address(taker), amount * 2);
        bytes memory takerData = _exactInTakerData();

        vm.expectRevert(
            abi.encodeWithSelector(
                OracleAdapter.OracleAdapterStalePrice.selector, oldestFeed, oldestUpdatedAt, maxStaleness
            )
        );
        taker.swap(order, address(usdc), address(weth), amount, takerData);
    }

    // ===== Price-deviation circuit breaker (ADR-0012) =====

    function test_ShipSucceedsWithGenerousToleranceUnderNormalFunding() public {
        // A wide 90% band -- not meant to be tight, just proving the new batch leg doesn't
        // spuriously block a normal ship() under this fixture's real, live-priced funding.
        ISwapVM.Order memory order = _buildOrder(4, 0.9e9);
        _shipOnly(order);
    }

    function test_ShipRevertsWhenWalletIsExtremelySkewedBeyondDeviationTolerance() public {
        ISwapVM.Order memory order = _buildOrder(5, 0.1e9); // 10% band

        // Stables funded 1000x over -- regardless of live WETH/WBTC prices, a wallet holding
        // ~99.9% of its value in one group against a 50/50 target is far outside any reasonable
        // tolerance. Mirrors a wallet that was never balanced to begin with, or drained on the
        // majors side by a direct Safe-owner withdrawal outside ship()/swap() entirely.
        (address[] memory tokens, uint256[] memory amounts) =
            _fundAndApprove(WETH_FUNDING, WBTC_FUNDING, DAI_FUNDING * 1000, USDT_FUNDING * 1000, USDC_FUNDING * 1000);

        // Live oracle prices make the exact `actualShareWad` argument unpredictable -- match on
        // the selector alone, not the full encoded error.
        vm.expectPartialRevert(
            IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorExcessivePriceDeviation.selector
        );
        _execShipBatch(order, tokens, amounts);
    }
}
