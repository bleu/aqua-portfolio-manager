// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Aqua} from "aqua/Aqua.sol";
import {IAqua} from "aqua/interfaces/IAqua.sol";
import {TokenMock} from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {Fee} from "swap-vm/instructions/Fee.sol";
import {MockTaker} from "../lib/swap-vm/test/mocks/MockTaker.sol";

import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {PortfolioManagerProgramBuilder} from "../src/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerArgsBuilder} from "../src/PortfolioManagerArgsBuilder.sol";
import {PortfolioManagerPricing} from "../src/PortfolioManagerPricing.sol";
import {PortfolioManagerSwap} from "../src/PortfolioManagerSwap.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";
import {IPortfolioManagerSwap} from "../src/interfaces/IPortfolioManagerSwap.sol";

/// @notice Exercises the shipped protocol-fee mechanism through a real SwapVM.swap() call
/// against a real Aqua registry — not the individual instructions in isolation, which
/// PortfolioManagerPricing.t.sol/PortfolioManagerArgsBuilder.t.sol already cover. This file
/// answers: does the protocol-fee pull baked into PortfolioManagerSwap's own execution (tiered
/// per 1IP-103) actually behave as designed end to end, and is it actually mandatory — not just
/// something PortfolioManagerProgramBuilder happens to include.
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
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;
    MockTaker internal taker;

    address internal maker;

    PortfolioManagerArgsBuilder.Group[] internal groups;

    function setUp() public {
        aqua = new Aqua();
        router = new PortfolioManagerRouter(address(aqua), address(0), address(this), "PM", "1");

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");
        // $1.00 per token (18-decimal feed) so a group's oracle-valued sum equals its raw
        // balance exactly, matching every DAO-fee/tiering assertion below (all derived from
        // INITIAL_BALANCE / SWAP_AMOUNT as if they were the group's value directly).
        feedA = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedB = new MockAggregatorV3(18, 1e18, block.timestamp);

        maker = vm.addr(0x1234);

        taker = new MockTaker(aqua, router, address(this));

        groups.push(_singleMemberGroup(0.5e18, address(tokenA), address(feedA)));
        groups.push(_singleMemberGroup(0.5e18, address(tokenB), address(feedB)));
    }

    // ===== Helpers =====

    function _singleMemberGroup(uint256 weight, address token, address feed)
        internal
        pure
        returns (PortfolioManagerArgsBuilder.Group memory)
    {
        PortfolioManagerArgsBuilder.Member[] memory members = new PortfolioManagerArgsBuilder.Member[](1);
        // The packed encoding's maxStaleness field is a uint16 (max ~18.2 hours) -- generous on
        // purpose within that ceiling, since this suite's own vm.warp usage (if any) is about
        // ledger/fee mechanics, not oracle freshness.
        members[0] = PortfolioManagerArgsBuilder.Member({token: token, feed: feed, maxStaleness: 18 hours});
        return PortfolioManagerArgsBuilder.Group({weight: weight, members: members});
    }

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        return _orderForProgram(PortfolioManagerProgramBuilder.build(groups, lpFeeBps));
    }

    /// @dev Deliberately does NOT call PortfolioManagerProgramBuilder — hand-packs the wire
    ///      format directly (opcode 0, the curve, per VM.sol's runLoop) the way any third party
    ///      who never heard of our builder still could, using only the LP-facing
    ///      PortfolioManagerArgsBuilder encoding (public, documented, nothing secret about it).
    ///      Proves the protocol fee survives bypassing our own tooling entirely.
    function _buildOrderFromHandCraftedProgram(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        bytes memory args = PortfolioManagerArgsBuilder.build(groups, lpFeeBps);
        bytes memory program = abi.encodePacked(uint8(0), uint8(args.length), args);
        return _orderForProgram(program);
    }

    function _orderForProgram(bytes memory program) internal view returns (ISwapVM.Order memory) {
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

    function _swapExactIn(ISwapVM.Order memory order, uint256 amount) internal returns (uint256, uint256) {
        bytes memory takerData = _exactInTakerData();

        tokenA.mint(address(taker), amount * 2);
        return taker.swap(order, address(tokenA), address(tokenB), amount, takerData);
    }

    function _swapExactOut(ISwapVM.Order memory order, uint256 amountOut) internal returns (uint256, uint256) {
        bytes memory takerData = TakerTraitsLib.build(
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

        // Exact-out grosses amountIn up by both the LP's own curve fee and the protocol fee on
        // top -- mint generously past amountOut so the taker never runs short regardless of tier.
        tokenA.mint(address(taker), amountOut * 3);
        return taker.swap(order, address(tokenA), address(tokenB), amountOut, takerData);
    }

    /// @dev Replicates PortfolioManagerSwap's own exact-out math (clean amountIn via the curve,
    ///      then grossed up by daoBps/(FEE_BPS - daoBps)) so tests can assert an independently
    ///      derived expected value instead of just "some nonzero fee landed".
    function _expectedExactOutDaoAmount(uint32 lpFeeBps, uint256 amountOut) internal view returns (uint256) {
        PortfolioManagerPricing.Quote memory quote = PortfolioManagerPricing.Quote({
            balanceIn: INITIAL_BALANCE,
            balanceOut: INITIAL_BALANCE,
            weightIn: groups[0].weight,
            weightOut: groups[1].weight,
            feeWad: uint256(lpFeeBps) * (1e18 / FEE_BPS_SCALE)
        });
        uint256 cleanAmountIn = PortfolioManagerPricing.exactOut(quote, amountOut);
        uint32 daoBps = PortfolioManagerProgramBuilder.daoFeeBps(lpFeeBps);
        return cleanAmountIn * daoBps / (FEE_BPS_SCALE - daoBps);
    }

    // ===== Tests =====

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

    function test_ProtocolFeeLandsInDaoTreasuryAtLowTierExactOut() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        _swapExactOut(order, SWAP_AMOUNT);

        uint256 expectedDaoAmount = _expectedExactOutDaoAmount(LOW_TIER_FEE_BPS, SWAP_AMOUNT);
        uint256 daoAmount = tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match the 1/4-tier exact-out formula");
    }

    function test_ProtocolFeeLandsInDaoTreasuryAtHighTierExactOut() public {
        ISwapVM.Order memory order = _buildOrder(HIGH_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        _swapExactOut(order, SWAP_AMOUNT);

        uint256 expectedDaoAmount = _expectedExactOutDaoAmount(HIGH_TIER_FEE_BPS, SWAP_AMOUNT);
        uint256 daoAmount = tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match the 1/6-tier exact-out formula");
    }

    function test_ZeroLpFeeMeansZeroProtocolFeeExactOut() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE);

        (, uint256 amountOut) = _swapExactOut(order, SWAP_AMOUNT);
        assertEq(amountOut, SWAP_AMOUNT);
        assertEq(tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS), 0);
    }

    function test_ProtocolFeeSkipsWhenMakerUnderfundedExactOut() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);

        // Ship zero ledger for tokenA -- the DAO pull cannot be covered at all.
        _shipOrder(order, 0);

        vm.recordLogs();
        (, uint256 amountOut) = _swapExactOut(order, SWAP_AMOUNT);
        assertEq(amountOut, SWAP_AMOUNT, "swap still completes even though the fee pull was skipped");
        assertEq(tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS), 0, "DAO gets nothing");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 skippedEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == Fee.ProtocolFeeSkipped.selector) {
                skippedEvents++;
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

    /// @notice A token never shipped to Aqua at all: `SwapVM`'s own `AQUA.safeBalances()` gate
    /// rejects it before dispatch reaches this opcode. See `PortfolioManagerSwap.sol` for why
    /// our own declared-universe check exists anyway.
    function test_RevertsWhenTakerRequestsTokenOutsideDeclaredUniverse() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        bytes32 strategyHash = _shipOrder(order, INITIAL_BALANCE);

        TokenMock outsideToken = new TokenMock("Outside", "OUT");
        bytes memory takerData = _exactInTakerData();

        outsideToken.mint(address(taker), SWAP_AMOUNT * 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAqua.SafeBalancesForTokenNotInActiveStrategy.selector,
                maker,
                address(router),
                strategyHash,
                address(outsideToken)
            )
        );
        taker.swap(order, address(outsideToken), address(tokenB), SWAP_AMOUNT, takerData);
    }

    /// @notice The one case where our own declared-universe check is genuinely reachable, not
    /// just defense-in-depth: a token shipped to Aqua's ledger that PM's own args-level universe
    /// never gave a weight to (a ship()/PortfolioManagerArgsBuilder encoding mismatch, not a
    /// malicious taker). `AQUA.safeBalances()` passes -- the token really is part of the active
    /// strategy -- so dispatch reaches this opcode, and `_groupIndexOf` is what actually catches it.
    function test_RevertsWhenShippedTokenIsMissingFromPmsOwnDeclaredUniverse() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);

        TokenMock tokenC = new TokenMock("Token C", "TKC");
        tokenA.mint(maker, INITIAL_BALANCE);
        tokenB.mint(maker, INITIAL_BALANCE);
        tokenC.mint(maker, INITIAL_BALANCE);
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
        amounts[0] = INITIAL_BALANCE;
        amounts[1] = INITIAL_BALANCE;
        amounts[2] = INITIAL_BALANCE;

        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);

        bytes memory takerData = _exactInTakerData();
        tokenC.mint(address(taker), SWAP_AMOUNT * 2);
        vm.expectRevert(
            abi.encodeWithSelector(IPortfolioManagerSwap.PortfolioManagerSwapTokenNotDeclared.selector, address(tokenC))
        );
        taker.swap(order, address(tokenC), address(tokenB), SWAP_AMOUNT, takerData);
    }

    /// @notice The central guarantee: the protocol fee is not merely a convention our own
    /// program-builder happens to follow. A strategy shipped from program bytes that never
    /// touched PortfolioManagerProgramBuilder -- built by hand, exactly as any third party
    /// could -- still pays the DAO the moment it invokes our curve opcode, because the pull is
    /// baked into PortfolioManagerSwap's own execution, not a separate, omittable instruction.
    function test_ProtocolFeeIsMandatoryEvenBypassingOurProgramBuilder() public {
        ISwapVM.Order memory order = _buildOrderFromHandCraftedProgram(LOW_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        _swapExactIn(order, SWAP_AMOUNT);

        uint256 expectedDaoAmount = SWAP_AMOUNT * (LOW_TIER_FEE_BPS / 4) / FEE_BPS_SCALE;
        assertEq(
            tokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS),
            expectedDaoAmount,
            "the DAO still gets paid even though this order's program bytes were hand-packed, never built by PortfolioManagerProgramBuilder"
        );
    }
}
