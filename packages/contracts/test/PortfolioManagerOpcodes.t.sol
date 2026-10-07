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
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerFee} from "../src/utils/PortfolioManagerFee.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerPricing} from "../src/utils/PortfolioManagerPricing.sol";
import {PortfolioManagerSwap} from "../src/PortfolioManagerSwap.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {IPortfolioManagerSwap} from "../src/interfaces/IPortfolioManagerSwap.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice Tests fee collection and enforcement through SwapVM settlement against Aqua.
contract PortfolioManagerOpcodesTest is Test {
    uint256 internal constant FEE_BPS_SCALE = 1e9;
    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant SWAP_AMOUNT = 1_000e18;

    /// @dev Below PortfolioManagerFee.TIER_THRESHOLD_BPS (0.1225%) — 1/4 tier.
    uint32 internal constant LOW_TIER_FEE_BPS = 0.02e9 / 100; // 2 bps, the existing ADR-0008 default
    /// @dev Above the threshold — 1/6 tier.
    uint32 internal constant HIGH_TIER_FEE_BPS = 0.5e9 / 100; // 0.5%

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    PortfolioManagerStrategyValidator internal strategyValidator;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;
    MockTaker internal taker;

    address internal maker;

    PortfolioManagerArgsCodec.Group[] internal groups;

    function setUp() public {
        vm.warp(1_000_000);
        // answer 0 == sequencer up (Chainlink's uptime-feed convention); started long enough ago
        // that OracleAdapter's post-recovery grace period has already elapsed.
        MockAggregatorV3 sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 2 hours);

        aqua = new Aqua();
        strategyValidator = new PortfolioManagerStrategyValidator(address(sequencerFeed));
        router = new PortfolioManagerRouter(
            address(aqua), address(0), address(this), "PM", "1", address(strategyValidator), address(sequencerFeed)
        );

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");
        // Unit prices and 18 decimals make value amounts equal native balances.
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
        returns (PortfolioManagerArgsCodec.Group memory)
    {
        PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](1);
        // Keep feeds fresh so these tests isolate ledger and fee behavior.
        members[0] = PortfolioManagerArgsCodec.Member({token: token, feed: feed, maxStaleness: 18 hours});
        return PortfolioManagerArgsCodec.Group({weight: weight, members: members});
    }

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        return _orderForProgram(PortfolioManagerProgramBuilder.build(groups, lpFeeBps));
    }

    /// @dev Bypass the program builder to test fee enforcement in the opcode itself.
    function _buildOrderFromHandCraftedProgram(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        bytes memory args = PortfolioManagerArgsCodec.build(groups, lpFeeBps);
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

    /// @param tokenInLedgerAmount Authorized tokenA amount, independent of the funded wallet balance.
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

        strategyValidator.attestBuildParameters(order, tokens);

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

        // Fund enough input to cover both LP and DAO fees for exact-out.
        tokenA.mint(address(taker), amountOut * 3);
        return taker.swap(order, address(tokenA), address(tokenB), amountOut, takerData);
    }

    /// @dev Compute expected exact-out fees from the curve input and DAO rate.
    function _expectedExactOutDaoAmount(uint32 lpFeeBps, uint256 amountOut) internal view returns (uint256) {
        PortfolioManagerPricing.PoolState memory quote = PortfolioManagerPricing.PoolState({
            balanceIn: INITIAL_BALANCE,
            balanceOut: INITIAL_BALANCE,
            weightIn: groups[0].weight,
            weightOut: groups[1].weight,
            feeWad: uint256(lpFeeBps) * (1e18 / FEE_BPS_SCALE)
        });
        uint256 cleanAmountIn = PortfolioManagerPricing.exactOut(quote, amountOut);
        uint32 daoBps = PortfolioManagerFee.daoFeeBps(lpFeeBps);
        return cleanAmountIn * daoBps / (FEE_BPS_SCALE - daoBps);
    }

    // ===== Tests =====

    function test_ProtocolFeeLandsInDaoTreasuryAtLowTier() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        (uint256 amountIn,) = _swapExactIn(order, SWAP_AMOUNT);
        assertEq(amountIn, SWAP_AMOUNT, "taker pays the exact amount they specified");

        uint256 expectedTotalFee = SWAP_AMOUNT * (LOW_TIER_FEE_BPS / 4) / FEE_BPS_SCALE;
        uint256 expectedBleuAmount = expectedTotalFee / 2;
        uint256 expectedDaoAmount = expectedTotalFee - expectedBleuAmount;
        uint256 daoAmount = tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS);
        uint256 bleuAmount = tokenA.balanceOf(PortfolioManagerFee.BLEU_TREASURY_ADDRESS);

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match half of the 1/4-tier formula");
        assertEq(bleuAmount, expectedBleuAmount, "Bleu amount must match the other half of the 1/4-tier formula");
        assertEq(
            tokenA.balanceOf(maker),
            INITIAL_BALANCE + amountIn - daoAmount - bleuAmount,
            "wallet's net gain is amountIn minus the protocol pull"
        );
    }

    function test_ProtocolFeeLandsInDaoTreasuryAtHighTier() public {
        ISwapVM.Order memory order = _buildOrder(HIGH_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        _swapExactIn(order, SWAP_AMOUNT);

        uint256 expectedTotalFee = SWAP_AMOUNT * (HIGH_TIER_FEE_BPS / 6) / FEE_BPS_SCALE;
        uint256 expectedBleuAmount = expectedTotalFee / 2;
        uint256 expectedDaoAmount = expectedTotalFee - expectedBleuAmount;
        uint256 daoAmount = tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS);
        uint256 bleuAmount = tokenA.balanceOf(PortfolioManagerFee.BLEU_TREASURY_ADDRESS);

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match half of the 1/6-tier formula");
        assertEq(bleuAmount, expectedBleuAmount, "Bleu amount must match the other half of the 1/6-tier formula");
    }

    function test_ZeroLpFeeMeansZeroProtocolFee() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE);

        (uint256 amountIn,) = _swapExactIn(order, SWAP_AMOUNT);
        assertEq(amountIn, SWAP_AMOUNT);
        assertEq(tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS), 0);
        assertEq(tokenA.balanceOf(maker), INITIAL_BALANCE + amountIn, "with no LP fee, the full amountIn lands");
    }

    function test_ProtocolFeeSkipsWhenMakerUnderfunded() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);

        // Ship zero ledger for tokenA -- neither the DAO nor the Bleu pull can be covered at all.
        _shipOrder(order, 0);

        vm.recordLogs();
        (uint256 amountIn,) = _swapExactIn(order, SWAP_AMOUNT);
        assertEq(amountIn, SWAP_AMOUNT, "swap still completes even though both fee pulls were skipped");
        assertEq(tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS), 0, "DAO gets nothing");
        assertEq(tokenA.balanceOf(PortfolioManagerFee.BLEU_TREASURY_ADDRESS), 0, "Bleu gets nothing");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 daoSkipped = 0;
        uint256 bleuSkipped = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == Fee.ProtocolFeeSkipped.selector) {
                (, address token, address to, uint256 skippedAmount) =
                    abi.decode(logs[i].data, (bytes32, address, address, uint256));
                token;
                assertGt(skippedAmount, 0);
                if (to == PortfolioManagerFee.DAO_TREASURY_ADDRESS) {
                    daoSkipped++;
                } else if (to == PortfolioManagerFee.BLEU_TREASURY_ADDRESS) {
                    bleuSkipped++;
                }
            }
        }
        assertEq(daoSkipped, 1, "exactly one ProtocolFeeSkipped for the DAO's half");
        assertEq(bleuSkipped, 1, "exactly one ProtocolFeeSkipped for Bleu's half");
    }

    function test_ProtocolFeeLandsInDaoTreasuryAtLowTierExactOut() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        _swapExactOut(order, SWAP_AMOUNT);

        uint256 expectedTotalFee = _expectedExactOutDaoAmount(LOW_TIER_FEE_BPS, SWAP_AMOUNT);
        uint256 expectedBleuAmount = expectedTotalFee / 2;
        uint256 expectedDaoAmount = expectedTotalFee - expectedBleuAmount;
        uint256 daoAmount = tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS);
        uint256 bleuAmount = tokenA.balanceOf(PortfolioManagerFee.BLEU_TREASURY_ADDRESS);

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match half of the 1/4-tier exact-out formula");
        assertEq(
            bleuAmount, expectedBleuAmount, "Bleu amount must match the other half of the 1/4-tier exact-out formula"
        );
    }

    function test_ProtocolFeeLandsInDaoTreasuryAtHighTierExactOut() public {
        ISwapVM.Order memory order = _buildOrder(HIGH_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        _swapExactOut(order, SWAP_AMOUNT);

        uint256 expectedTotalFee = _expectedExactOutDaoAmount(HIGH_TIER_FEE_BPS, SWAP_AMOUNT);
        uint256 expectedBleuAmount = expectedTotalFee / 2;
        uint256 expectedDaoAmount = expectedTotalFee - expectedBleuAmount;
        uint256 daoAmount = tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS);
        uint256 bleuAmount = tokenA.balanceOf(PortfolioManagerFee.BLEU_TREASURY_ADDRESS);

        assertGt(daoAmount, 0, "DAO must actually receive a fee");
        assertEq(daoAmount, expectedDaoAmount, "DAO amount must match half of the 1/6-tier exact-out formula");
        assertEq(
            bleuAmount, expectedBleuAmount, "Bleu amount must match the other half of the 1/6-tier exact-out formula"
        );
    }

    function test_ZeroLpFeeMeansZeroProtocolFeeExactOut() public {
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE);

        (, uint256 amountOut) = _swapExactOut(order, SWAP_AMOUNT);
        assertEq(amountOut, SWAP_AMOUNT);
        assertEq(tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS), 0);
    }

    function test_ExactInPreservesInvariantWithFractionalInputReserve() public {
        feedA.setAnswer(0.5e18, block.timestamp);
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);
        tokenA.burn(maker, INITIAL_BALANCE - 3);
        tokenB.burn(maker, INITIAL_BALANCE - 100e18);

        _swapExactIn(order, 200);

        // Constant prices cancel from the equal-weight invariant. Flooring the input
        // reserve's value from 1.5 to 1 previously paid 99 B and reduced this product.
        assertGe(tokenA.balanceOf(maker) * tokenB.balanceOf(maker), 300e18);
    }

    function test_ExactOutPreservesInvariantWithFractionalInputReserve() public {
        feedA.setAnswer(0.5e18, block.timestamp);
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);
        tokenA.burn(maker, INITIAL_BALANCE - 3);
        tokenB.burn(maker, INITIAL_BALANCE - 100e18);

        _swapExactOut(order, 99e18);

        assertGe(tokenA.balanceOf(maker) * tokenB.balanceOf(maker), 300e18);
    }

    function testFuzz_FractionalReservesPreserveSettledInvariant(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amount,
        bool exactIn,
        bool withFee
    ) public {
        balanceIn = bound(balanceIn, 3, 1e6);
        balanceOut = bound(balanceOut, 8, INITIAL_BALANCE);
        feedA.setAnswer(0.5e18, block.timestamp);
        feedB.setAnswer(0.75e18, block.timestamp);
        ISwapVM.Order memory order = _buildOrder(withFee ? LOW_TIER_FEE_BPS : 0);
        _shipOrder(order, INITIAL_BALANCE);
        tokenA.burn(maker, INITIAL_BALANCE - balanceIn);
        tokenB.burn(maker, INITIAL_BALANCE - balanceOut);

        if (exactIn) {
            // Keep output nonzero even at the smallest reserve and after fee rounding.
            amount = bound(amount, balanceIn + 4, 10 * balanceIn);
            _swapExactIn(order, amount);
        } else {
            amount = bound(amount, 1, balanceOut / 2);
            // Small output reserves can require much more native input than output.
            tokenA.mint(address(taker), 10 * balanceIn + 100);
            _swapExactOut(order, amount);
        }

        // Uses settled native balances, independent of rounded oracle values or powers.
        assertGe(tokenA.balanceOf(maker) * tokenB.balanceOf(maker), balanceIn * balanceOut);
        assertGt(tokenB.balanceOf(maker), 0);
    }

    function test_ExactOutRoundsRequestedOutputValueUp() public {
        feedB.setAnswer(0.5e18, block.timestamp);
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE);
        tokenA.burn(maker, INITIAL_BALANCE - 100);
        tokenB.burn(maker, INITIAL_BALANCE - 100);

        // Three output units are worth 1.5 value units. Flooring that request to one
        // charges only three input units, violating (100 + input) * (100 - 3) >= 100^2.
        // Constant prices cancel from this equal-weight invariant, so native balances
        // provide an independent integer oracle without using the production pricing math.
        (, uint256 amountOut) = _swapExactOut(order, 3);

        assertEq(amountOut, 3);
        assertGe(
            tokenA.balanceOf(maker) * tokenB.balanceOf(maker),
            100 * 100,
            "rounding output value down must not decrease the settled invariant"
        );
    }

    function test_ExactOutRoundsRequiredNativeInputUp() public {
        feedA.setAnswer(2e18, block.timestamp);
        ISwapVM.Order memory order = _buildOrder(0);
        _shipOrder(order, INITIAL_BALANCE);
        tokenA.burn(maker, INITIAL_BALANCE - 100);
        tokenB.burn(maker, INITIAL_BALANCE - 100);

        // The conservative curve quote requires three value units, or 1.5 input units.
        // Paying only one native unit would leave 101 * 99 < 100^2 in the maker's wallet.
        (, uint256 amountOut) = _swapExactOut(order, 1);

        assertEq(amountOut, 1);
        assertGe(
            tokenA.balanceOf(maker) * tokenB.balanceOf(maker),
            100 * 100,
            "rounding native input down must not decrease the settled invariant"
        );
    }

    function test_ProtocolFeeSkipsWhenMakerUnderfundedExactOut() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);

        // Ship zero ledger for tokenA -- neither the DAO nor the Bleu pull can be covered at all.
        _shipOrder(order, 0);

        vm.recordLogs();
        (, uint256 amountOut) = _swapExactOut(order, SWAP_AMOUNT);
        assertEq(amountOut, SWAP_AMOUNT, "swap still completes even though both fee pulls were skipped");
        assertEq(tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS), 0, "DAO gets nothing");
        assertEq(tokenA.balanceOf(PortfolioManagerFee.BLEU_TREASURY_ADDRESS), 0, "Bleu gets nothing");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 skippedEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == Fee.ProtocolFeeSkipped.selector) {
                skippedEvents++;
            }
        }
        assertEq(skippedEvents, 2, "one ProtocolFeeSkipped per recipient");
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

        // Restore identical balances to isolate the effect of the LP fee.
        assertLt(amountOutWithLpFee, amountOutNoLpFee, "a nonzero LP curve fee must strictly reduce quoted output");
    }

    /// @notice Aqua rejects unshipped tokens before PM dispatch.
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

    /// @notice Aqua permits a shipped token that the encoded PM universe does not declare.
    /// @dev Attest two tokens, then ship three. Attestation does not bind ship()'s later token list.
    ///      Aqua accepts the token, but PM's _resolve rejects it.
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

        address[] memory declaredTokens = new address[](2);
        declaredTokens[0] = address(tokenA);
        declaredTokens[1] = address(tokenB);
        strategyValidator.attestBuildParameters(order, declaredTokens);

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

    function test_RevertsWhenStrategyWasNeverAttested() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);

        tokenA.mint(maker, INITIAL_BALANCE);
        tokenB.mint(maker, INITIAL_BALANCE);
        vm.startPrank(maker);
        tokenA.approve(address(aqua), type(uint256).max);
        tokenB.approve(address(aqua), type(uint256).max);
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = INITIAL_BALANCE;
        amounts[1] = INITIAL_BALANCE;

        // Ships directly, skipping strategyValidator.attestBuildParameters entirely -- exactly what
        // a caller that never went through the recommended multicall batch would do.
        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);

        bytes memory takerData = _exactInTakerData();
        tokenA.mint(address(taker), SWAP_AMOUNT * 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerSwap.PortfolioManagerSwapBuildParametersNotAttested.selector, router.hash(order)
            )
        );
        taker.swap(order, address(tokenA), address(tokenB), SWAP_AMOUNT, takerData);
    }

    /// @notice Hand-packed programs still pay the DAO/Bleu split when they execute the PM curve opcode.
    function test_ProtocolFeeIsMandatoryEvenBypassingOurProgramBuilder() public {
        ISwapVM.Order memory order = _buildOrderFromHandCraftedProgram(LOW_TIER_FEE_BPS);
        _shipOrder(order, INITIAL_BALANCE);

        _swapExactIn(order, SWAP_AMOUNT);

        uint256 expectedTotalFee = SWAP_AMOUNT * (LOW_TIER_FEE_BPS / 4) / FEE_BPS_SCALE;
        uint256 expectedBleuAmount = expectedTotalFee / 2;
        uint256 expectedDaoAmount = expectedTotalFee - expectedBleuAmount;
        assertEq(
            tokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS),
            expectedDaoAmount,
            "the DAO still gets its half even though this order's program bytes were hand-packed, never built by PortfolioManagerProgramBuilder"
        );
        assertEq(
            tokenA.balanceOf(PortfolioManagerFee.BLEU_TREASURY_ADDRESS),
            expectedBleuAmount,
            "Bleu still gets its half even though this order's program bytes were hand-packed, never built by PortfolioManagerProgramBuilder"
        );
    }
}
