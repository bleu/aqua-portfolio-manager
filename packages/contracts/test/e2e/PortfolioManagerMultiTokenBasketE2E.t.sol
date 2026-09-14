// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Aqua} from "aqua/Aqua.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";

import {PortfolioManagerRouter} from "../../src/PortfolioManagerRouter.sol";
import {PortfolioManagerArgsBuilder} from "../../src/PortfolioManagerArgsBuilder.sol";
import {PortfolioManagerProgramBuilder} from "../../src/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerStrategyFactory} from "../../src/PortfolioManagerStrategyFactory.sol";
import {PortfolioManagerPricing} from "../../src/PortfolioManagerPricing.sol";
import {OracleAdapter} from "../../src/OracleAdapter.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {MockTaker} from "../../lib/swap-vm/test/mocks/MockTaker.sol";

/// @notice Real multi-token oracle-valued groups (ADR-0003/BLEUDEV-347), end to end against the
/// actually deployed router/Aqua/factory on a real Base fork -- a "majors" group {WETH, WBTC}
/// and a "stables" group {DAI, USDT, USDC}, each member priced through its own real Chainlink
/// feed. `PortfolioManagerE2EBase.t.sol`'s single-group suite already covers protocol-fee and
/// basic curve mechanics end to end; this file's job is specifically proving the multi-member
/// group-valuation path (`OracleAdapter.groupValueWad`) works correctly against real balances
/// and real live prices, not a mock.
///
/// Deliberately self-contained (own Safe/MultiSendCallOnly plumbing, not
/// `PortfolioManagerE2EBase`) -- that base's fields are hard-shaped around a 2-token,
/// single-member-group universe; this fixture's 5-token, 2-group universe doesn't fit it.
///
/// Requires `deployments/local.json` with the fields `Deploy.mock.multitoken.sol` adds -- skips
/// entirely if missing, same convention as `PortfolioManagerE2EBase.t.sol`.
contract PortfolioManagerMultiTokenBasketE2ETest is Test {
    string internal constant MANIFEST_PATH = "deployments/local.json";
    uint256 internal constant MAJORS_WEIGHT = 0.5e18;
    uint256 internal constant STABLES_WEIGHT = 0.5e18;

    /// @dev Matches Deploy.mock.multitoken.sol's own funding amounts (kept in sync manually --
    ///      that script's own deal() calls are inert against a live node, see `_shipOnly`).
    uint256 internal constant WETH_FUNDING = 20e18;
    uint256 internal constant WBTC_FUNDING = 1e8;
    uint256 internal constant DAI_FUNDING = 60_000e18;
    uint256 internal constant USDT_FUNDING = 30_000e6;
    uint256 internal constant USDC_FUNDING = 30_000e6;

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    Safe internal multiTokenSafe;
    address internal deployer;
    MockTaker internal taker;
    PortfolioManagerStrategyFactory internal strategyFactory;
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
    PortfolioManagerArgsBuilder.Group[] internal groups;

    function setUp() public {
        if (!vm.exists(MANIFEST_PATH) || !vm.keyExistsJson(vm.readFile(MANIFEST_PATH), ".multiTokenSafe")) {
            vm.skip(
                true,
                "deployments/local.json missing the multi-token fixture - run `forge script script/Deploy.s.sol --broadcast` then `forge script script/Deploy.mock.multitoken.sol --broadcast` first"
            );
            return;
        }

        string memory json = vm.readFile(MANIFEST_PATH);
        aqua = Aqua(vm.parseJsonAddress(json, ".aqua"));
        router = PortfolioManagerRouter(payable(vm.parseJsonAddress(json, ".router")));
        multiTokenSafe = Safe(payable(vm.parseJsonAddress(json, ".multiTokenSafe")));
        deployer = vm.parseJsonAddress(json, ".deployer");
        strategyFactory = PortfolioManagerStrategyFactory(vm.parseJsonAddress(json, ".pmStrategyFactory"));
        multiSendCallOnly = MultiSendCallOnly(vm.parseJsonAddress(json, ".multiSendCallOnly"));

        weth = IERC20(vm.parseJsonAddress(json, ".multiTokenWeth"));
        wbtc = IERC20(vm.parseJsonAddress(json, ".multiTokenWbtc"));
        dai = IERC20(vm.parseJsonAddress(json, ".multiTokenDai"));
        usdt = IERC20(vm.parseJsonAddress(json, ".multiTokenUsdt"));
        usdc = IERC20(vm.parseJsonAddress(json, ".multiTokenUsdc"));
        wethFeed = vm.parseJsonAddress(json, ".multiTokenWethFeed");
        wbtcFeed = vm.parseJsonAddress(json, ".multiTokenWbtcFeed");
        daiFeed = vm.parseJsonAddress(json, ".multiTokenDaiFeed");
        usdtFeed = vm.parseJsonAddress(json, ".multiTokenUsdtFeed");
        usdcFeed = vm.parseJsonAddress(json, ".multiTokenUsdcFeed");
        maxStaleness = vm.parseJsonUint(json, ".multiTokenMaxStaleness");

        taker = new MockTaker(aqua, router, address(this));

        PortfolioManagerArgsBuilder.Member[] memory majors = new PortfolioManagerArgsBuilder.Member[](2);
        majors[0] =
            PortfolioManagerArgsBuilder.Member({token: address(weth), feed: wethFeed, maxStaleness: maxStaleness});
        majors[1] =
            PortfolioManagerArgsBuilder.Member({token: address(wbtc), feed: wbtcFeed, maxStaleness: maxStaleness});
        groups.push(PortfolioManagerArgsBuilder.Group({weight: MAJORS_WEIGHT, members: majors}));

        PortfolioManagerArgsBuilder.Member[] memory stables = new PortfolioManagerArgsBuilder.Member[](3);
        stables[0] =
            PortfolioManagerArgsBuilder.Member({token: address(dai), feed: daiFeed, maxStaleness: maxStaleness});
        stables[1] =
            PortfolioManagerArgsBuilder.Member({token: address(usdt), feed: usdtFeed, maxStaleness: maxStaleness});
        stables[2] =
            PortfolioManagerArgsBuilder.Member({token: address(usdc), feed: usdcFeed, maxStaleness: maxStaleness});
        groups.push(PortfolioManagerArgsBuilder.Group({weight: STABLES_WEIGHT, members: stables}));
    }

    // ===== Helpers =====

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, lpFeeBps);
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

    /// @dev Batches `PortfolioManagerStrategyFactory.requireUniverseMatches` with the real
    ///      `Aqua.ship` call via `MultiSendCallOnly` -- see `PortfolioManagerE2EBase.t.sol`'s
    ///      identical note on why this doesn't route through the factory itself.
    function _shipOnly(ISwapVM.Order memory order) internal returns (bytes32) {
        address[] memory tokens = new address[](5);
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
        deal(address(weth), address(multiTokenSafe), WETH_FUNDING);
        deal(address(wbtc), address(multiTokenSafe), WBTC_FUNDING);
        deal(address(dai), address(multiTokenSafe), DAI_FUNDING);
        deal(address(usdt), address(multiTokenSafe), USDT_FUNDING);
        deal(address(usdc), address(multiTokenSafe), USDC_FUNDING);

        uint256[] memory amounts = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = IERC20(tokens[i]).balanceOf(address(multiTokenSafe));
        }

        vm.startPrank(address(multiTokenSafe));
        for (uint256 i = 0; i < 5; i++) {
            IERC20(tokens[i]).approve(address(aqua), type(uint256).max);
        }
        vm.stopPrank();

        bytes memory validateData =
            abi.encodeCall(PortfolioManagerStrategyFactory.requireUniverseMatches, (order, tokens));
        bytes memory shipData = abi.encodeCall(Aqua.ship, (address(router), abi.encode(order), tokens, amounts));

        bytes memory batch = abi.encodePacked(
            _encodeMultiSendTx(address(strategyFactory), validateData), _encodeMultiSendTx(address(aqua), shipData)
        );
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (batch));

        vm.prank(deployer);
        bool ok = multiTokenSafe.execTransaction(
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
        require(ok, "ship through multi-token PM Safe failed");

        bytes32 strategyHash = keccak256(abi.encode(order));
        assertEq(strategyHash, router.hash(order), "strategy hash must match order hash");
        return strategyHash;
    }

    function _encodeMultiSendTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }

    /// @dev See `PortfolioManagerE2EBase.t.sol`'s identical note: `deployer` is
    ///      `multiTokenSafe`'s sole owner, so Safe's pre-approved-hash signature form needs no
    ///      real ECDSA signature.
    function _selfApprovedSignature() internal view returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(deployer))), bytes32(0), uint8(1));
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
    function _groupValueWad(PortfolioManagerArgsBuilder.Member[] memory members) internal view returns (uint256 total) {
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

        PortfolioManagerPricing.Quote memory correctQuote = PortfolioManagerPricing.Quote({
            balanceIn: correctBalanceIn,
            balanceOut: correctBalanceOut,
            weightIn: STABLES_WEIGHT,
            weightOut: MAJORS_WEIGHT,
            feeWad: 0
        });

        // Wrong expectation (what a regression to single-token-only pricing would compute):
        // balanceOut = WETH's own oracle value alone, ignoring WBTC entirely.
        uint256 wethOnlyValueWad = _usdValueWad(address(weth), wethFeed, weth.balanceOf(address(multiTokenSafe)));
        PortfolioManagerPricing.Quote memory wrongQuote = PortfolioManagerPricing.Quote({
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
        uint256 expectedCorrectOutValueWad = PortfolioManagerPricing.exactIn(correctQuote, usdcAmountInValueWad);
        uint256 expectedWrongOutValueWad = PortfolioManagerPricing.exactIn(wrongQuote, usdcAmountInValueWad);

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
}
