// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
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

/// @notice Confirms ShipStrategy.s.sol's fix actually closes the gap PMDrainPoC.t.sol found: the
/// same stale-price depeg trade that extracted real profit from the currently-deployed order
/// (maxDeviationBps=0) reverts against a strategy built the same way but with the new nonzero
/// value. Not the real deployed strategy -- this order is never shipped, only reconstructed here
/// to prove the fix before spending a real redeploy on it.
contract MaxDeviationBpsFixTest is Test {
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

    /// @dev Matches ShipStrategy.s.sol's MAX_DEVIATION_BPS exactly -- this test would need updating
    /// if that value ever changes.
    uint32 internal constant MAX_DEVIATION_BPS = 50_000_000; // 5% of PM_BPS's 1e9 scale

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    MockTaker internal taker;
    ISwapVM.Order internal order;

    function setUp() public {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org"));
        vm.createSelectFork(rpcUrl);

        aqua = Aqua(AQUA_BASE);
        router = PortfolioManagerRouter(payable(ROUTER));

        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        groups[0] = _majors();
        groups[1] = _stables();
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, LP_FEE_BPS, MAX_DEVIATION_BPS);

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

    /// @notice PMDrainPoC.t.sol's peak-profit trade size ($1 of USDC, 10% stale depeg) against the
    /// currently-shipped order. The only difference here is a nonzero maxDeviationBps -- if the fix
    /// works, this same trade must revert instead of paying out.
    function test_DepegTradeThatProfitedOnCurrentStrategy_RevertsWithTheFix() public {
        (, int256 realAnswer,,,) = AggregatorV3Interface(USDC_USD_FEED).latestRoundData();
        assertGt(realAnswer, 0, "sanity: real feed answer must be positive");

        uint256 staleUpdatedAt = block.timestamp - (MAX_STALENESS - 1 minutes);
        vm.mockCall(
            USDC_USD_FEED,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), realAnswer, uint256(0), staleUpdatedAt, uint80(0))
        );

        uint256 tradeAmountUsdc = 1_000_000; // $1 of USDC (6 decimals) -- the PoC's peak-profit size
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

        vm.expectRevert();
        taker.swap(order, USDC, WETH, tradeAmountUsdc, takerData);
    }
}
