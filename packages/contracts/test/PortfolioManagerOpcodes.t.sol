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
/// answers: does the *composition* (two chained Fee._aquaProtocolFeeAmountInXD pulls before
/// the curve opcode) actually behave as designed end to end.
contract PortfolioManagerOpcodesTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant FEE_BPS_SCALE = 1e9;
    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant SWAP_AMOUNT = 1_000e18;

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    MockTaker internal taker;

    address internal maker;
    address internal daoAddress;
    address internal bleuAddress;

    address[] internal universe;
    uint256[] internal weights;

    function setUp() public {
        aqua = new Aqua();
        router = new PortfolioManagerRouter(address(aqua), address(0), address(this), "PM", "1");

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");

        maker = vm.addr(0x1234);
        daoAddress = vm.addr(0xDA0);
        bleuAddress = vm.addr(0xB1EA);

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
        bytes memory program =
            PortfolioManagerProgramBuilder.build(universe, weights, lpFeeBps, daoAddress, bleuAddress);

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

    function test_BothProtocolFeePullsLandAndSplitEvenly() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE);

        (uint256 amountIn,) = _swapExactIn(order, SWAP_AMOUNT);
        assertEq(amountIn, SWAP_AMOUNT, "taker pays the exact amount they specified");

        uint256 daoAmount = tokenA.balanceOf(daoAddress);
        uint256 bleuAmount = tokenA.balanceOf(bleuAddress);

        uint256 expectedDaoAmount = SWAP_AMOUNT * PortfolioManagerProgramBuilder.DAO_FEE_BPS / FEE_BPS_SCALE;
        uint256 bleuFeeBps = uint256(PortfolioManagerProgramBuilder.DAO_FEE_BPS) * FEE_BPS_SCALE
            / (FEE_BPS_SCALE - PortfolioManagerProgramBuilder.DAO_FEE_BPS);
        uint256 expectedBleuAmount = (SWAP_AMOUNT - expectedDaoAmount) * bleuFeeBps / FEE_BPS_SCALE;

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match the chained-fee formula");
        assertEq(bleuAmount, expectedBleuAmount, "Bleu amount must match the chained-fee formula");
        // bleuFeeBps is solved to make these equal, but integer division in that solve (not in
        // the pull itself) leaves a few-wei rounding gap on amounts this size — dust, not a
        // design flaw; PortfolioManagerProgramBuilder's comment derives the intended formula.
        assertApproxEqAbs(daoAmount, bleuAmount, 1e10, "the 50/50 split must land within rounding dust");

        // The wallet starts at INITIAL_BALANCE, temporarily loses both fee pulls, then is
        // credited the taker's full amountIn by SwapVM's own settlement (Aqua.push) — so its
        // net gain from this trade is amountIn minus both protocol pulls, not the full amountIn.
        assertEq(
            tokenA.balanceOf(maker),
            INITIAL_BALANCE + amountIn - daoAmount - bleuAmount,
            "wallet's net gain is amountIn minus both protocol pulls"
        );
    }

    function test_OneProtocolFeePullSkipsIndependentlyWhenMakerUnderfunded() public {
        ISwapVM.Order memory order = _buildOrder(0);

        // Fee.sol's _aquaProtocolFeeAmountInXD wraps the rest of the program (shrinks amountIn,
        // recurses into ctx.runLoop(), *then* pulls once that returns) — so the pull for the
        // instruction composed FIRST in program bytes (DAO) actually executes LAST, and the one
        // composed SECOND (Bleu) executes first, against whatever ledger is available before
        // DAO gets a turn. Ship just enough tokenA ledger for Bleu's (first-executing) pull to
        // land, leaving nothing for DAO's (second-executing) pull.
        uint256 expectedDaoAmount = SWAP_AMOUNT * PortfolioManagerProgramBuilder.DAO_FEE_BPS / FEE_BPS_SCALE;
        uint256 bleuFeeBpsForLedger = uint256(PortfolioManagerProgramBuilder.DAO_FEE_BPS) * FEE_BPS_SCALE
            / (FEE_BPS_SCALE - PortfolioManagerProgramBuilder.DAO_FEE_BPS);
        uint256 expectedBleuAmount = (SWAP_AMOUNT - expectedDaoAmount) * bleuFeeBpsForLedger / FEE_BPS_SCALE;
        _shipOrder(order, expectedBleuAmount);

        vm.recordLogs();
        (uint256 amountIn,) = _swapExactIn(order, SWAP_AMOUNT);
        assertEq(amountIn, SWAP_AMOUNT, "swap still completes even though one fee pull was skipped");

        assertEq(tokenA.balanceOf(bleuAddress), expectedBleuAmount, "Bleu's pull (executes first) still lands in full");
        assertEq(tokenA.balanceOf(daoAddress), 0, "DAO's pull (executes second) is skipped, not partially collected");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 skippedEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == Fee.ProtocolFeeSkipped.selector) {
                skippedEvents++;
                (, address token, address to, uint256 skippedAmount) =
                    abi.decode(logs[i].data, (bytes32, address, address, uint256));
                token;
                skippedAmount;
                assertEq(to, daoAddress, "the skip must be reported for DAO specifically");
            }
        }
        assertEq(skippedEvents, 1, "exactly one ProtocolFeeSkipped, not zero and not two");
    }

    function test_LpOwnCurveFeeStillAppliesOnTopOfProtocolFee() public {
        uint32 lpFeeBps = 0.01e9; // 1% — the LP's own curve fee, unrelated to the protocol fee

        uint256 snapshot = vm.snapshotState();

        ISwapVM.Order memory zeroFeeOrder = _buildOrder(0);
        _shipOrder(zeroFeeOrder, INITIAL_BALANCE);
        (, uint256 amountOutNoLpFee) = _swapExactIn(zeroFeeOrder, SWAP_AMOUNT);

        vm.revertToState(snapshot);

        ISwapVM.Order memory feeOrder = _buildOrder(lpFeeBps);
        _shipOrder(feeOrder, INITIAL_BALANCE);
        (, uint256 amountOutWithLpFee) = _swapExactIn(feeOrder, SWAP_AMOUNT);

        // Same starting balances (via the snapshot/revert), same protocol fee either way —
        // only the LP's own curve fee differs, so it alone must explain a strictly smaller
        // quoted output. Confirms feeWad still reaches PortfolioManagerPricing correctly,
        // unaffected by the protocol-fee chain running ahead of it in the program.
        assertLt(amountOutWithLpFee, amountOutNoLpFee, "a nonzero LP curve fee must strictly reduce quoted output");
    }

    function test_ProgramBuilderRevertsOnZeroRecipient() public {
        vm.expectRevert(PortfolioManagerProgramBuilder.PortfolioManagerProgramBuilderZeroRecipient.selector);
        this._buildWithZeroDao();
    }

    function _buildWithZeroDao() external view {
        PortfolioManagerProgramBuilder.build(universe, weights, 0, address(0), bleuAddress);
    }
}
