// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {Aqua} from "aqua/Aqua.sol";

import {AquaE2EBase} from "./base/AquaE2EBase.t.sol";
import {PortfolioManagerRouter} from "../../src/PortfolioManagerRouter.sol";
import {PortfolioManagerArgsCodec} from "../../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "../../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerStrategyValidator} from "../../src/PortfolioManagerStrategyValidator.sol";
import {Arbitrageur} from "../../src/Arbitrageur.sol";
import {IBalancerVault} from "../../src/interfaces/IBalancerVault.sol";

/// @dev Stands in for whatever real DEX route Fynd would have found to convert the curve's
///      `tokenOut` proceeds back into `tokenIn` -- pulls `amountIn` of `tokenIn` via the
///      allowance `Arbitrageur` grants it, sends back a configurable `amountOut` of `tokenOut`.
///      Its own balance of `tokenOut` must be pre-funded by the test (`deal`), same as the real
///      market would need to actually hold the liquidity Fynd's route claims to use.
contract MockFyndRouter {
    using SafeERC20 for IERC20;

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 amountOut) external {
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenOut.safeTransfer(msg.sender, amountOut);
    }
}

/// @notice Real-fork proof that `Arbitrageur.executeFlashArbitrage` genuinely borrows, trades,
/// and repays within one transaction against a real, shipped PM strategy and the real Balancer V2
/// Vault (`0xBA12...F2C8`, same canonical address as every EVM chain Balancer V2 is deployed to,
/// already live on this Base fork -- no mock needed for the Vault itself). `MockFyndRouter` above
/// stands in for the real DEX route Fynd would find for the return leg, since hitting live DEX
/// liquidity deterministically from a test isn't practical. Access-control reverts
/// (`onlyOwner`, `receiveFlashLoan` vault-only) are covered separately in `test/Arbitrageur.t.sol`
/// (no fork needed there) -- same split `ArbitrageurE2E.t.sol` already uses.
contract ArbitrageurFlashE2ETest is AquaE2EBase {
    /// @dev Real Balancer V2 Vault -- same address on every EVM chain it's deployed to, Base
    ///      included (confirmed live: https://basescan.org/address/0xba12222222228d8ba445958a75a0704d566bf2c8).
    address internal constant BALANCER_VAULT_BASE = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    /// @dev WBTC on Base — https://basescan.org/token/0x1cea84203673764244e05693e42e6ace62be9ba5
    address internal constant WBTC_BASE = 0x1ceA84203673764244E05693e42E6Ace62bE9BA5;
    /// @dev USDT on Base — https://basescan.org/token/0xfde4c96c8593536e31f229ea8f37b2ada2699bb2
    address internal constant USDT_BASE = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    /// @dev USDC on Base — https://basescan.org/token/0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
    address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @dev Chainlink ETH/USD on Base — https://basescan.org/address/0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70
    address internal constant ETH_USD_FEED_BASE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    /// @dev Chainlink BTC/USD on Base — https://basescan.org/address/0x64c911996d3c6ac71f9b455b1e8e7266bcbd848f
    address internal constant BTC_USD_FEED_BASE = 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F;
    /// @dev Chainlink USDT/USD on Base — https://basescan.org/address/0xf19d560eb8d2adf07bd6d13ed03e1d11215721f9
    address internal constant USDT_USD_FEED_BASE = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    /// @dev Chainlink USDC/USD on Base — https://basescan.org/address/0x7e860098f58bbfc8648a4311b374b1d669a2bc6b
    address internal constant USDC_USD_FEED_BASE = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;

    uint256 internal constant MAX_STALENESS = 12 hours;
    uint256 internal constant GROUP_WEIGHT = 0.5e18;

    uint256 internal constant WETH_FUNDING = 20e18;
    uint256 internal constant WBTC_FUNDING = 1e8;
    uint256 internal constant USDT_FUNDING = 30_000e6;
    uint256 internal constant USDC_FUNDING = 30_000e6;

    uint256 private constant OWNER_KEY = 0xA12BEE;

    PortfolioManagerRouter internal router;
    PortfolioManagerStrategyValidator internal strategyValidator;
    MultiSendCallOnly internal multiSendCallOnly;
    Safe internal pmSafe;
    Arbitrageur internal arbitrageur;
    MockFyndRouter internal fyndRouter;
    address internal arbitrageurOwner;

    IERC20 internal weth;
    IERC20 internal wbtc;
    IERC20 internal usdt;
    IERC20 internal usdc;

    /// @dev groups[0] = {USDT, USDC}, groups[1] = {WBTC, WETH} -- the two-group basket this
    ///      feature is built for.
    PortfolioManagerArgsCodec.Group[] internal groups;

    function setUp() public override {
        super.setUp();

        strategyValidator = new PortfolioManagerStrategyValidator();
        router = new PortfolioManagerRouter(
            address(aqua), WETH_BASE, deployer, "AquaPortfolioManager", "1", address(strategyValidator)
        );
        multiSendCallOnly = new MultiSendCallOnly();
        pmSafe = _newSafe(3); // distinct salt nonce from the other E2E fixtures' Safes

        weth = IERC20(WETH_BASE);
        wbtc = IERC20(WBTC_BASE);
        usdt = IERC20(USDT_BASE);
        usdc = IERC20(USDC_BASE);

        arbitrageurOwner = vm.addr(OWNER_KEY);
        arbitrageur = new Arbitrageur(address(router), BALANCER_VAULT_BASE, arbitrageurOwner);
        fyndRouter = new MockFyndRouter();

        PortfolioManagerArgsCodec.Member[] memory stables = new PortfolioManagerArgsCodec.Member[](2);
        stables[0] = PortfolioManagerArgsCodec.Member({
            token: address(usdt), feed: USDT_USD_FEED_BASE, maxStaleness: MAX_STALENESS
        });
        stables[1] = PortfolioManagerArgsCodec.Member({
            token: address(usdc), feed: USDC_USD_FEED_BASE, maxStaleness: MAX_STALENESS
        });
        groups.push(PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: stables}));

        PortfolioManagerArgsCodec.Member[] memory majors = new PortfolioManagerArgsCodec.Member[](2);
        majors[0] = PortfolioManagerArgsCodec.Member({
            token: address(wbtc), feed: BTC_USD_FEED_BASE, maxStaleness: MAX_STALENESS
        });
        majors[1] = PortfolioManagerArgsCodec.Member({
            token: address(weth), feed: ETH_USD_FEED_BASE, maxStaleness: MAX_STALENESS
        });
        groups.push(PortfolioManagerArgsCodec.Group({weight: GROUP_WEIGHT, members: majors}));
    }

    // ===== Helpers =====

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, lpFeeBps);
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: address(pmSafe),
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

    /// @dev Same batched-multisend ship pattern `PortfolioManagerMultiTokenBasketE2E.t.sol` uses.
    function _shipOnly(ISwapVM.Order memory order) internal {
        address[] memory tokens = new address[](4);
        tokens[0] = address(usdt);
        tokens[1] = address(usdc);
        tokens[2] = address(wbtc);
        tokens[3] = address(weth);

        deal(address(usdt), address(pmSafe), USDT_FUNDING);
        deal(address(usdc), address(pmSafe), USDC_FUNDING);
        deal(address(wbtc), address(pmSafe), WBTC_FUNDING);
        deal(address(weth), address(pmSafe), WETH_FUNDING);

        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            amounts[i] = IERC20(tokens[i]).balanceOf(address(pmSafe));
        }

        vm.startPrank(address(pmSafe));
        for (uint256 i = 0; i < 4; i++) {
            IERC20(tokens[i]).approve(address(aqua), type(uint256).max);
        }
        vm.stopPrank();

        bytes memory attestData =
            abi.encodeCall(PortfolioManagerStrategyValidator.attestBuildParameters, (order, tokens));
        bytes memory shipData = abi.encodeCall(Aqua.ship, (address(router), abi.encode(order), tokens, amounts));

        bytes memory batch = abi.encodePacked(
            _encodeMultiSendTx(address(strategyValidator), attestData), _encodeMultiSendTx(address(aqua), shipData)
        );
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (batch));

        vm.prank(deployer);
        bool ok = pmSafe.execTransaction(
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
        require(ok, "ship through PM Safe failed");
    }

    function _encodeMultiSendTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }

    /// @dev Overwrites the real Balancer Vault's balance of `token` directly, isolating "does our
    ///      contract's flash-loan logic work" from "does Balancer's Base deployment happen to
    ///      hold enough of this token in its pools at whatever block this fork lands on."
    function _ensureVaultLiquidity(IERC20 token, uint256 amount) internal {
        deal(address(token), BALANCER_VAULT_BASE, amount);
    }

    // ===== Tests =====

    function test_FlashArbitrageRepaysLoanAndKeepsProfit() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOnly(order);

        uint256 amountIn = 1_000e6; // 1,000 USDT
        uint256 quotedOut = arbitrageur.quoteExactIn(order, address(usdt), address(wbtc), amountIn);
        assertGt(quotedOut, 0, "curve quote must be non-zero for a funded, shipped strategy");

        // The mock Fynd route returns 5% more USDT than the flash loan owes -- the "arbitrage
        // profit" this test is proving actually lands on the contract, sweepable by the owner.
        uint256 owed = amountIn; // Balancer flash loans are 0% fee
        uint256 fyndReturnAmount = (owed * 105) / 100;
        deal(address(usdt), address(fyndRouter), fyndReturnAmount);
        _ensureVaultLiquidity(usdt, amountIn * 10);

        Arbitrageur.FlashArbParams memory params = Arbitrageur.FlashArbParams({
            order: order,
            tokenIn: address(usdt),
            tokenOut: address(wbtc),
            amountIn: amountIn,
            minCurveAmountOut: quotedOut,
            fyndTarget: address(fyndRouter),
            fyndSpender: address(fyndRouter),
            fyndCalldata: abi.encodeCall(MockFyndRouter.swap, (wbtc, usdt, quotedOut, fyndReturnAmount)),
            deadline: uint40(block.timestamp + 60)
        });

        vm.prank(arbitrageurOwner);
        arbitrageur.executeFlashArbitrage(params);

        uint256 expectedProfit = fyndReturnAmount - owed;
        assertEq(usdt.balanceOf(address(arbitrageur)), expectedProfit, "profit must remain on the contract");

        vm.prank(arbitrageurOwner);
        arbitrageur.sweep(address(usdt), expectedProfit, arbitrageurOwner);
        assertEq(usdt.balanceOf(arbitrageurOwner), expectedProfit, "owner must be able to sweep the profit out");
    }

    function test_FlashArbitrageRevertsWhenFyndRouteReturnsInsufficientRepayment() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOnly(order);

        uint256 amountIn = 1_000e6;
        uint256 quotedOut = arbitrageur.quoteExactIn(order, address(usdt), address(wbtc), amountIn);

        // The mock Fynd route returns less than what's owed -- the flash loan, and with it the
        // whole transaction including the already-settled curve trade, must revert atomically.
        uint256 owed = amountIn;
        uint256 fyndReturnAmount = owed - 1;
        deal(address(usdt), address(fyndRouter), fyndReturnAmount);
        _ensureVaultLiquidity(usdt, amountIn * 10);

        Arbitrageur.FlashArbParams memory params = Arbitrageur.FlashArbParams({
            order: order,
            tokenIn: address(usdt),
            tokenOut: address(wbtc),
            amountIn: amountIn,
            minCurveAmountOut: quotedOut,
            fyndTarget: address(fyndRouter),
            fyndSpender: address(fyndRouter),
            fyndCalldata: abi.encodeCall(MockFyndRouter.swap, (wbtc, usdt, quotedOut, fyndReturnAmount)),
            deadline: uint40(block.timestamp + 60)
        });

        vm.prank(arbitrageurOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Arbitrageur.ArbitrageurInsufficientRepayment.selector, owed, fyndReturnAmount)
        );
        arbitrageur.executeFlashArbitrage(params);
    }
}
