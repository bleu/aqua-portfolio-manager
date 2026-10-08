// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {TokenMock} from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";

import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {IPortfolioManagerStrategyValidator} from "../src/interfaces/IPortfolioManagerStrategyValidator.sol";
import {OracleAdapter} from "../src/utils/OracleAdapter.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice Tests validation separately from shipping. Safe batch integration is covered in the E2E suite.
contract PortfolioManagerStrategyValidatorTest is Test {
    PortfolioManagerStrategyValidator internal validator;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    TokenMock internal tokenC;

    address internal maker;

    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;
    MockAggregatorV3 internal sequencerFeed;

    function setUp() public {
        vm.warp(1_000_000);
        // answer 0 == sequencer up (Chainlink's uptime-feed convention); started long enough ago
        // that OracleAdapter's post-recovery grace period has already elapsed.
        sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 2 hours);
        validator = new PortfolioManagerStrategyValidator(address(sequencerFeed));

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");
        tokenC = new TokenMock("Token C", "TKC");

        // $1.00 per token (18-decimal feed) -- keeps the tolerance tests' expected shares easy
        // to compute directly off raw balances.
        feedA = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedB = new MockAggregatorV3(18, 1e18, block.timestamp);

        maker = vm.addr(0x1234);
    }

    /// @dev Universe checks do not read feeds. Deviation tests use priced feeds separately.
    address internal constant DUMMY_FEED = address(0xFEED);

    function _groups(address[] memory declaredTokens, uint256[] memory weights)
        internal
        pure
        returns (PortfolioManagerArgsCodec.Group[] memory groups)
    {
        groups = new PortfolioManagerArgsCodec.Group[](declaredTokens.length);
        for (uint256 i = 0; i < declaredTokens.length; i++) {
            PortfolioManagerArgsCodec.Member[] memory members = new PortfolioManagerArgsCodec.Member[](1);
            members[0] =
                PortfolioManagerArgsCodec.Member({token: declaredTokens[i], feed: DUMMY_FEED, maxStaleness: 1 hours});
            groups[i] = PortfolioManagerArgsCodec.Group({weight: weights[i], members: members});
        }
    }

    function _order(address[] memory declaredTokens, uint256[] memory weights)
        internal
        view
        returns (ISwapVM.Order memory)
    {
        bytes memory program = PortfolioManagerProgramBuilder.build(_groups(declaredTokens, weights), 0);
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
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

    function test_PassesWhenDeclaredAndShippedUniversesMatch() public view {
        address[] memory declared = new address[](2);
        declared[0] = address(tokenA);
        declared[1] = address(tokenB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        ISwapVM.Order memory order = _order(declared, weights);

        validator.requireUniverseMatches(order, declared);
    }

    function test_RevertsWhenDeclaredTokenIsNotShipped() public {
        address[] memory declared = new address[](3);
        declared[0] = address(tokenA);
        declared[1] = address(tokenB);
        declared[2] = address(tokenC);
        uint256[] memory weights = new uint256[](3);
        weights[0] = 0.4e18;
        weights[1] = 0.3e18;
        weights[2] = 0.3e18;

        ISwapVM.Order memory order = _order(declared, weights);

        // Only ships A and B -- C is declared in the args but never given to Aqua's ledger.
        address[] memory shipped = new address[](2);
        shipped[0] = address(tokenA);
        shipped[1] = address(tokenB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorDeclaredTokenNotShipped.selector,
                address(tokenC)
            )
        );
        validator.requireUniverseMatches(order, shipped);
    }

    function test_RevertsWhenShippedTokenIsNotDeclared() public {
        address[] memory declared = new address[](2);
        declared[0] = address(tokenA);
        declared[1] = address(tokenB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        ISwapVM.Order memory order = _order(declared, weights);

        // Ships A, B, AND C -- C is on Aqua's ledger but the args never gave it a weight.
        address[] memory shipped = new address[](3);
        shipped[0] = address(tokenA);
        shipped[1] = address(tokenB);
        shipped[2] = address(tokenC);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorShippedTokenNotDeclared.selector,
                address(tokenC)
            )
        );
        validator.requireUniverseMatches(order, shipped);
    }

    /// @dev Builds an order from an arbitrary program, bypassing _order/_groups so the trailing-
    ///      instruction tests can append raw bytes after a legitimate leading curve.
    function _orderWithProgram(bytes memory program) internal view returns (ISwapVM.Order memory) {
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
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

    /// @dev A trailing curve instruction after the leading, validated one must never be silently
    ///      accepted into the attested scope -- its own args were never checked.
    function test_RevertsOnTrailingCurveInstruction() public {
        address[] memory declared = new address[](2);
        declared[0] = address(tokenA);
        declared[1] = address(tokenB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        bytes memory program = PortfolioManagerProgramBuilder.build(_groups(declared, weights), 0);
        // Appends a second, unvalidated curve instruction after the first's own args.
        bytes memory trailingCurve = abi.encodePacked(uint8(PortfolioManagerProgramBuilder.CURVE_OPCODE), uint8(0));
        program = abi.encodePacked(program, trailingCurve);

        vm.expectRevert(
            IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorTrailingCurveInstruction.selector
        );
        validator.requireUniverseMatches(_orderWithProgram(program), declared);
    }

    /// @dev A trailing curve must be rejected even when it comes after a legitimate non-curve
    ///      instruction, not just immediately after the leading curve -- the walk must not stop
    ///      at the first trailing instruction.
    function test_RevertsOnTrailingCurveInstructionAfterANonCurveInstruction() public {
        address[] memory declared = new address[](2);
        declared[0] = address(tokenA);
        declared[1] = address(tokenB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        bytes memory program = PortfolioManagerProgramBuilder.build(_groups(declared, weights), 0);
        // KYC_GATE_OPCODE = 1, matching GatedPortfolioManagerProgramBuilder's own wire format.
        bytes memory kycGate = abi.encodePacked(uint8(1), uint8(20), address(0xC0DE));
        bytes memory trailingCurve = abi.encodePacked(uint8(PortfolioManagerProgramBuilder.CURVE_OPCODE), uint8(0));
        program = abi.encodePacked(program, kycGate, trailingCurve);

        vm.expectRevert(
            IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorTrailingCurveInstruction.selector
        );
        validator.requireUniverseMatches(_orderWithProgram(program), declared);
    }

    /// @dev A trailing non-curve instruction (e.g. the resolver KYC gate) does not re-price
    ///      anything, so it must stay allowed -- this is the real, shipped Gated program shape.
    function test_AllowsTrailingNonCurveInstruction() public view {
        address[] memory declared = new address[](2);
        declared[0] = address(tokenA);
        declared[1] = address(tokenB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;

        bytes memory program = PortfolioManagerProgramBuilder.build(_groups(declared, weights), 0);
        bytes memory kycGate = abi.encodePacked(uint8(1), uint8(20), address(0xC0DE));
        program = abi.encodePacked(program, kycGate);

        validator.requireUniverseMatches(_orderWithProgram(program), declared);
    }

    function test_RevertsOnNonPortfolioManagerProgram() public {
        bytes memory program = abi.encodePacked(uint8(99), uint8(0));
        ISwapVM.Order memory order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
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

        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);

        vm.expectRevert(
            IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorNotAPortfolioManagerStrategy.selector
        );
        validator.requireUniverseMatches(order, tokens);
    }

    // ===== requireBalancedWithinTolerance (ADR-0012) =====

    /// @dev Two single-member groups with unit prices and equal weights for balance checks.
    function _toleranceOrder(uint32 maxDeviationBps) internal view returns (ISwapVM.Order memory) {
        PortfolioManagerArgsCodec.Group[] memory groups = new PortfolioManagerArgsCodec.Group[](2);
        PortfolioManagerArgsCodec.Member[] memory membersA = new PortfolioManagerArgsCodec.Member[](1);
        membersA[0] =
            PortfolioManagerArgsCodec.Member({token: address(tokenA), feed: address(feedA), maxStaleness: 1 hours});
        groups[0] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersA});

        PortfolioManagerArgsCodec.Member[] memory membersB = new PortfolioManagerArgsCodec.Member[](1);
        membersB[0] =
            PortfolioManagerArgsCodec.Member({token: address(tokenB), feed: address(feedB), maxStaleness: 1 hours});
        groups[1] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersB});

        bytes memory program = PortfolioManagerProgramBuilder.build(groups, 0, maxDeviationBps);
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
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

    function test_TolerancePassesWhenWalletIsAtTarget() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%
        tokenA.mint(maker, 100_000e18);
        tokenB.mint(maker, 100_000e18);

        validator.requireBalancedWithinTolerance(order, maker);
    }

    function test_TolerancePassesWithinBand() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%
        // Equal weights -- pairwise spot price is 105,000/100,000 = 1.05, 5% off the 1.0 parity
        // the swap guard also checks -- inside the 10% band.
        tokenA.mint(maker, 105_000e18);
        tokenB.mint(maker, 100_000e18);

        validator.requireBalancedWithinTolerance(order, maker);
    }

    function test_ToleranceRevertsWhenWalletIsFundedOffTargetBeyondBand() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%
        // Equal weights -- pairwise spot price is 10,000/100,000 = 0.1, 90% off the 1.0 parity
        // the swap guard also checks -- well past the 10% band.
        uint256 balA = 10_000e18;
        uint256 balB = 100_000e18;
        tokenA.mint(maker, balA);
        tokenB.mint(maker, balB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorExcessivePriceDeviation.selector,
                uint256(0),
                uint256(1),
                uint256(0.1e18),
                uint256(0.1e9)
            )
        );
        validator.requireBalancedWithinTolerance(order, maker);
    }

    /// @dev The actual BLEUDEV-407 bug: a wallet the OLD per-group-share metric would have passed
    ///      (8.1% share deviation, under the 10% band) but whose pairwise spot price is already
    ///      15% off parity -- exactly the gap between the two metrics. Proves attestation now
    ///      rejects a strategy that would have shipped fine under the old check and then had every
    ///      cross-group swap immediately revert against PortfolioManagerSwap's own pairwise guard.
    function test_ToleranceRevertsOnPairwiseSpotPriceEvenWhenTheOldShareMetricWouldHavePassed() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%
        uint256 balA = 85_000e18;
        uint256 balB = 100_000e18;
        tokenA.mint(maker, balA);
        tokenB.mint(maker, balB);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorExcessivePriceDeviation.selector,
                uint256(0),
                uint256(1),
                uint256(0.85e18),
                uint256(0.1e9)
            )
        );
        validator.requireBalancedWithinTolerance(order, maker);
    }

    function test_ToleranceZeroMaxDeviationBpsIsANoOpEvenWhenBadlySkewed() public {
        ISwapVM.Order memory order = _toleranceOrder(0); // disabled
        tokenA.mint(maker, 10_000e18);
        tokenB.mint(maker, 100_000e18);

        validator.requireBalancedWithinTolerance(order, maker);
    }

    /// @dev Proves the deviation check actually asks the sequencer feed, not just that wiring a
    ///      constructor param compiles -- flips the same mock setUp wired in, to "down".
    function test_ToleranceRevertsWhenSequencerIsDown() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%
        tokenA.mint(maker, 100_000e18);
        tokenB.mint(maker, 100_000e18);
        sequencerFeed.setAnswer(1, block.timestamp); // answer 1 == down

        vm.expectRevert(
            abi.encodeWithSelector(OracleAdapter.OracleAdapterSequencerDown.selector, address(sequencerFeed))
        );
        validator.requireBalancedWithinTolerance(order, maker);
    }

    function test_ToleranceRevertsWithDescriptiveErrorOnEmptyPortfolio() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%, unfunded wallet

        vm.expectRevert(IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorEmptyPortfolio.selector);
        validator.requireBalancedWithinTolerance(order, maker);
    }

    // ===== attestBuildParameters =====

    function test_AttestBuildParametersRecordsStateAndEmitsEvent() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9);
        tokenA.mint(maker, 100_000e18);
        tokenB.mint(maker, 100_000e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        bytes32 strategyHash = keccak256(abi.encode(order));

        assertFalse(validator.buildParamsAttested(strategyHash), "must be unattested before the call");

        vm.expectEmit(true, false, false, false, address(validator));
        emit IPortfolioManagerStrategyValidator.BuildParametersAttested(strategyHash);
        validator.attestBuildParameters(order, tokens);

        assertTrue(validator.buildParamsAttested(strategyHash), "must be attested after a successful call");
    }

    function test_AttestBuildParametersRevertsOnUniverseMismatchSameAsRequireUniverseMatches() public {
        address[] memory declared = new address[](2);
        declared[0] = address(tokenA);
        declared[1] = address(tokenB);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;
        ISwapVM.Order memory order = _order(declared, weights);

        address[] memory shipped = new address[](3);
        shipped[0] = address(tokenA);
        shipped[1] = address(tokenB);
        shipped[2] = address(tokenC);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorShippedTokenNotDeclared.selector,
                address(tokenC)
            )
        );
        validator.attestBuildParameters(order, shipped);

        assertFalse(
            validator.buildParamsAttested(keccak256(abi.encode(order))), "a reverted attestation must not be recorded"
        );
    }

    function test_AttestBuildParametersRevertsOnExcessiveDeviationSameAsRequireBalancedWithinTolerance() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%
        uint256 balA = 10_000e18;
        uint256 balB = 100_000e18;
        tokenA.mint(maker, balA);
        tokenB.mint(maker, balB);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        vm.expectPartialRevert(
            IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorExcessivePriceDeviation.selector
        );
        validator.attestBuildParameters(order, tokens);
    }

    /// @dev The ship-time pairwise deviation check (BLEUDEV-407) is just as unit-agnostic as the
    ///      swap-side step cap (BLEUDEV-403/ADR-0016) -- it only compares groupValuesWad ratios,
    ///      never an absolute USD amount -- so it must keep working unchanged against a numeraire
    ///      member too. tokenA is its own numeraire (feed == address(0)); only feedB is read.
    function test_ToleranceWorksWhenOneMemberIsItsOwnNumeraire() public {
        PortfolioManagerArgsCodec.Group[] memory numeraireGroups = new PortfolioManagerArgsCodec.Group[](2);
        PortfolioManagerArgsCodec.Member[] memory membersA = new PortfolioManagerArgsCodec.Member[](1);
        membersA[0] = PortfolioManagerArgsCodec.Member({token: address(tokenA), feed: address(0), maxStaleness: 0});
        numeraireGroups[0] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersA});

        PortfolioManagerArgsCodec.Member[] memory membersB = new PortfolioManagerArgsCodec.Member[](1);
        membersB[0] =
            PortfolioManagerArgsCodec.Member({token: address(tokenB), feed: address(feedB), maxStaleness: 1 hours});
        numeraireGroups[1] = PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersB});

        bytes memory program = PortfolioManagerProgramBuilder.build(numeraireGroups, 0, 0.1e9); // 10%
        ISwapVM.Order memory order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
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

        tokenA.mint(maker, 100_000e18);
        tokenB.mint(maker, 100_000e18);
        validator.requireBalancedWithinTolerance(order, maker); // at target, must not revert

        // Push 90% past parity -- same shape as test_ToleranceRevertsWhenWalletIsFundedOffTargetBeyondBand,
        // just denominated in tokenA instead of USD. Confirms the check still fires correctly.
        tokenA.mint(maker, 890_000e18); // tokenA group now 990,000e18 vs tokenB's 100,000e18
        vm.expectPartialRevert(
            IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorExcessivePriceDeviation.selector
        );
        validator.requireBalancedWithinTolerance(order, maker);
    }

    function test_AttestBuildParametersIsIdempotent() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9);
        tokenA.mint(maker, 100_000e18);
        tokenB.mint(maker, 100_000e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        validator.attestBuildParameters(order, tokens);
        validator.attestBuildParameters(order, tokens); // must not revert

        assertTrue(validator.buildParamsAttested(keccak256(abi.encode(order))));
    }
}
