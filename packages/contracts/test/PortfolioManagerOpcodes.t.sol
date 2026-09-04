// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Aqua} from "aqua/Aqua.sol";
import {TokenMock} from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {Fee} from "swap-vm/instructions/Fee.sol";
import {MockTaker} from "../lib/swap-vm/test/mocks/MockTaker.sol";

import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {PortfolioManagerProgramBuilder} from "../src/PortfolioManagerProgramBuilder.sol";

/// @notice Exercises BLEUDEV-327's shipped fee mechanism through a real SwapVM.swap() call
/// against a real Aqua registry — not the individual instructions in isolation, which
/// PortfolioManagerPricing.t.sol/PortfolioManagerArgsBuilder.t.sol already cover. This file
/// answers: does the *composition* (a chained Fee._aquaProtocolFeeAmountInXD pull, tiered per
/// 1IP-103, before the curve opcode) actually behave as designed end to end.
contract PortfolioManagerOpcodesTest is Test {
    uint256 internal constant FEE_BPS_SCALE = 1e9;
    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant SWAP_AMOUNT = 1_000e18;

    /// @dev Below PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS (0.1225%) — 1/4 tier.
    uint32 internal constant LOW_TIER_FEE_BPS = 0.02e9 / 100; // 2 bps, the existing ADR-0008 default
    /// @dev Above the threshold — 1/6 tier.
    uint32 internal constant HIGH_TIER_FEE_BPS = 0.5e9 / 100; // 0.5%

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    MockTaker internal taker;

    address internal maker;

    address[] internal universe;
    uint256[] internal weights;

    function setUp() public {
        aqua = new Aqua();
        router = new PortfolioManagerRouter(address(aqua), address(0), address(this), "PM", "1");

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");

        maker = vm.addr(0x1234);

        taker = new MockTaker(aqua, router, address(this));

        universe = new address[](2);
        universe[0] = address(tokenA);
        universe[1] = address(tokenB);
        weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;
    }

    // ===== Helpers =====

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        bytes memory program = PortfolioManagerProgramBuilder.build(universe, weights, lpFeeBps);

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

    /// @param tokenInLedgerAmount Aqua-ledger amount shipped for tokenA specifically — kept
    ///        separate from the maker's real wallet balance (always `INITIAL_BALANCE`, since
    ///        that's what the curve actually prices off, per ADR-0002) so a test can starve
    ///        just the ledger `_AQUA.pull()` draws from without touching real exposure.
    function _shipOrder(ISwapVM.Order memory order, uint256 tokenInLedgerAmount) internal returns (bytes32) {
        tokenA.mint(maker, INITIAL_BALANCE);
        tokenB.mint(maker, INITIAL_BALANCE);

        vm.prank(maker);
        tokenA.approve(address(aqua), type(uint256).max);
        vm.prank(maker);
        tokenB.approve(address(aqua), type(uint256).max);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = tokenInLedgerAmount;
        amounts[1] = INITIAL_BALANCE;

        vm.prank(maker);
        bytes32 strategyHash = aqua.ship(address(router), abi.encode(order), tokens, amounts);
        assertEq(strategyHash, router.hash(order), "strategy hash must match order hash");
        return strategyHash;
    }

    function _swapExactIn(ISwapVM.Order memory order, uint256 amount) internal returns (uint256, uint256) {
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

        tokenA.mint(address(taker), amount * 2);
        return taker.swap(order, address(tokenA), address(tokenB), amount, takerData);
    }

    // ===== Tests =====

    function test_DaoFeeBpsTiering() public pure {
        // Pure formula check, no swap harness needed — the boundary and both tiers.
        assertEq(PortfolioManagerProgramBuilder.daoFeeBps(0), 0);
        assertEq(PortfolioManagerProgramBuilder.daoFeeBps(LOW_TIER_FEE_BPS), LOW_TIER_FEE_BPS / 4);
        assertEq(
            PortfolioManagerProgramBuilder.daoFeeBps(PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS),
            PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS / 4,
            "the threshold itself is still low-tier (<=), per 1IP-103's own wording"
        );
        assertEq(
            PortfolioManagerProgramBuilder.daoFeeBps(PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS + 1),
            (PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS + 1) / 6
        );
        assertEq(PortfolioManagerProgramBuilder.daoFeeBps(HIGH_TIER_FEE_BPS), HIGH_TIER_FEE_BPS / 6);
    }

    function test_ProtocolFeeLandsInDaoTreasuryAtLowTier() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        (uint256 amountIn,) = _swapExactIn(order, SWAP_AMOUNT);
        assertEq(amountIn, SWAP_AMOUNT, "taker pays the exact amount they specified");

        uint256 expectedDaoAmount = SWAP_AMOUNT * (LOW_TIER_FEE_BPS / 4) / FEE_BPS_SCALE;
        uint256 daoAmount = tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match the 1/4-tier formula");
        assertEq(
            tokenA.balanceOf(maker),
            INITIAL_BALANCE + amountIn - daoAmount,
            "wallet's net gain is amountIn minus the protocol pull"
        );
    }

    function test_ProtocolFeeLandsInDaoTreasuryAtHighTier() public {
        ISwapVM.Order memory order = _buildOrder(HIGH_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        _swapExactIn(order, SWAP_AMOUNT);

        uint256 expectedDaoAmount = SWAP_AMOUNT * (HIGH_TIER_FEE_BPS / 6) / FEE_BPS_SCALE;
        uint256 daoAmount = tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match the 1/6-tier formula");
    }

    function test_ZeroLpFeeMeansZeroProtocolFee() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE);

        (uint256 amountIn,) = _swapExactIn(order, SWAP_AMOUNT);
        assertEq(amountIn, SWAP_AMOUNT);
        assertEq(tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS), 0);
        assertEq(tokenA.balanceOf(maker), INITIAL_BALANCE + amountIn, "with no LP fee, the full amountIn lands");
    }

    function test_ProtocolFeeSkipsWhenMakerUnderfunded() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);

        // Ship zero ledger for tokenA -- the DAO pull cannot be covered at all.
        _shipOrder(order, 0);

        vm.recordLogs();
        (uint256 amountIn,) = _swapExactIn(order, SWAP_AMOUNT);
        assertEq(amountIn, SWAP_AMOUNT, "swap still completes even though the fee pull was skipped");
        assertEq(tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS), 0, "DAO gets nothing");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 skippedEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == Fee.ProtocolFeeSkipped.selector) {
                skippedEvents++;
                (, address token, address to, uint256 skippedAmount) =
                    abi.decode(logs[i].data, (bytes32, address, address, uint256));
                token;
                assertEq(to, PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);
                assertGt(skippedAmount, 0);
            }
        }
        assertEq(skippedEvents, 1, "exactly one ProtocolFeeSkipped");
    }

    function test_LpOwnCurveFeeStillAppliesOnTopOfProtocolFee() public {
        uint256 snapshot = vm.snapshotState();

        ISwapVM.Order memory zeroFeeOrder = _buildOrder(0);
        _shipOrder(zeroFeeOrder, INITIAL_BALANCE);
        (, uint256 amountOutNoLpFee) = _swapExactIn(zeroFeeOrder, SWAP_AMOUNT);

        vm.revertToState(snapshot);

        ISwapVM.Order memory feeOrder = _buildOrder(LOW_TIER_FEE_BPS);
        _shipOrder(feeOrder, INITIAL_BALANCE);
        (, uint256 amountOutWithLpFee) = _swapExactIn(feeOrder, SWAP_AMOUNT);

        // Same starting balances (via the snapshot/revert) -- only the LP's own curve fee
        // differs, so it alone must explain a strictly smaller quoted output. Confirms feeWad
        // still reaches PortfolioManagerPricing correctly, unaffected by the protocol-fee pull
        // running ahead of it in the program.
        assertLt(amountOutWithLpFee, amountOutNoLpFee, "a nonzero LP curve fee must strictly reduce quoted output");
    }
}
