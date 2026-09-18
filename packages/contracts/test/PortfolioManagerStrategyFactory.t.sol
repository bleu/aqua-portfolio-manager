// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {TokenMock} from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";

import {PortfolioManagerArgsBuilder} from "../src/PortfolioManagerArgsBuilder.sol";
import {PortfolioManagerProgramBuilder} from "../src/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerStrategyFactory} from "../src/PortfolioManagerStrategyFactory.sol";
import {IPortfolioManagerStrategyFactory} from "../src/interfaces/IPortfolioManagerStrategyFactory.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice Confirms the factory actually closes the gap it exists for: a mismatch between
/// PortfolioManagerArgsBuilder's declared universe and IAqua.ship()'s own tokens array, in
/// either direction, reverts. Deliberately a pure validation check only -- it never calls
/// Aqua.ship() itself, so there's no ledger/settlement path to exercise here; see
/// PortfolioManagerE2EBase.t.sol for the real Safe + MultiSendCallOnly flow this feeds into.
contract PortfolioManagerStrategyFactoryTest is Test {
    PortfolioManagerStrategyFactory internal factory;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    TokenMock internal tokenC;

    address internal maker;

    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;

    function setUp() public {
        factory = new PortfolioManagerStrategyFactory();

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");
        tokenC = new TokenMock("Token C", "TKC");

        // $1.00 per token (18-decimal feed) -- keeps the tolerance tests' expected shares easy
        // to compute directly off raw balances.
        feedA = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedB = new MockAggregatorV3(18, 1e18, block.timestamp);

        maker = vm.addr(0x1234);
    }

    /// @dev The factory only cross-checks token membership, never prices anything, so a shared
    ///      dummy feed address across every single-member group is fine here.
    address internal constant DUMMY_FEED = address(0xFEED);

    function _groups(address[] memory declaredTokens, uint256[] memory weights)
        internal
        pure
        returns (PortfolioManagerArgsBuilder.Group[] memory groups)
    {
        groups = new PortfolioManagerArgsBuilder.Group[](declaredTokens.length);
        for (uint256 i = 0; i < declaredTokens.length; i++) {
            PortfolioManagerArgsBuilder.Member[] memory members = new PortfolioManagerArgsBuilder.Member[](1);
            members[0] =
                PortfolioManagerArgsBuilder.Member({token: declaredTokens[i], feed: DUMMY_FEED, maxStaleness: 1 hours});
            groups[i] = PortfolioManagerArgsBuilder.Group({weight: weights[i], members: members});
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

        factory.requireUniverseMatches(order, declared);
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
                IPortfolioManagerStrategyFactory.PortfolioManagerStrategyFactoryDeclaredTokenNotShipped.selector,
                address(tokenC)
            )
        );
        factory.requireUniverseMatches(order, shipped);
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
                IPortfolioManagerStrategyFactory.PortfolioManagerStrategyFactoryShippedTokenNotDeclared.selector,
                address(tokenC)
            )
        );
        factory.requireUniverseMatches(order, shipped);
    }

    function test_RevertsOnNonPortfolioManagerProgram() public {
        // Opcode 99 doesn't exist on any router this factory knows about -- simulates a program
        // this factory was never meant to validate, e.g. a different strategy entirely.
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
            IPortfolioManagerStrategyFactory.PortfolioManagerStrategyFactoryNotAPortfolioManagerStrategy.selector
        );
        factory.requireUniverseMatches(order, tokens);
    }

    // ===== requireBalancedWithinTolerance (ADR-0012) =====

    /// @dev 2 single-member groups (tokenA/feedA, tokenB/feedB), both $1.00/token, 50/50 target
    ///      -- real pricing, unlike `_order`'s DUMMY_FEED groups above, since this check actually
    ///      reads balances and oracle prices.
    function _toleranceOrder(uint32 maxDeviationBps) internal view returns (ISwapVM.Order memory) {
        PortfolioManagerArgsBuilder.Group[] memory groups = new PortfolioManagerArgsBuilder.Group[](2);
        PortfolioManagerArgsBuilder.Member[] memory membersA = new PortfolioManagerArgsBuilder.Member[](1);
        membersA[0] =
            PortfolioManagerArgsBuilder.Member({token: address(tokenA), feed: address(feedA), maxStaleness: 1 hours});
        groups[0] = PortfolioManagerArgsBuilder.Group({weight: 0.5e18, members: membersA});

        PortfolioManagerArgsBuilder.Member[] memory membersB = new PortfolioManagerArgsBuilder.Member[](1);
        membersB[0] =
            PortfolioManagerArgsBuilder.Member({token: address(tokenB), feed: address(feedB), maxStaleness: 1 hours});
        groups[1] = PortfolioManagerArgsBuilder.Group({weight: 0.5e18, members: membersB});

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

        factory.requireBalancedWithinTolerance(order, maker);
    }

    function test_TolerancePassesWithinBand() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%
        // 105,000 / 205,000 = 51.2%, only ~2.4% off the 50% target -- inside the 10% band.
        tokenA.mint(maker, 105_000e18);
        tokenB.mint(maker, 100_000e18);

        factory.requireBalancedWithinTolerance(order, maker);
    }

    function test_ToleranceRevertsWhenWalletIsFundedOffTargetBeyondBand() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9); // 10%
        // 10,000 / 110,000 = ~9.09% actual share vs. a 50% target -- ~82% relative deviation,
        // e.g. a wallet funded off-target from the start, never through ship() at all.
        uint256 balA = 10_000e18;
        uint256 balB = 100_000e18;
        tokenA.mint(maker, balA);
        tokenB.mint(maker, balB);

        uint256 actualShareWad = balA * 1e18 / (balA + balB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerStrategyFactory.PortfolioManagerStrategyFactoryExcessivePriceDeviation.selector,
                uint256(0),
                actualShareWad,
                uint256(0.5e18)
            )
        );
        factory.requireBalancedWithinTolerance(order, maker);
    }

    function test_ToleranceZeroMaxDeviationBpsIsANoOpEvenWhenBadlySkewed() public {
        ISwapVM.Order memory order = _toleranceOrder(0); // disabled
        tokenA.mint(maker, 10_000e18);
        tokenB.mint(maker, 100_000e18);

        factory.requireBalancedWithinTolerance(order, maker);
    }

    // ===== attestBuildParameters (BLEUDEV-381) =====

    function test_AttestBuildParametersRecordsStateAndEmitsEvent() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9);
        tokenA.mint(maker, 100_000e18);
        tokenB.mint(maker, 100_000e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        bytes32 strategyHash = keccak256(abi.encode(order));

        assertFalse(factory.buildParamsAttested(strategyHash), "must be unattested before the call");

        vm.expectEmit(true, false, false, false, address(factory));
        emit IPortfolioManagerStrategyFactory.BuildParametersAttested(strategyHash);
        factory.attestBuildParameters(order, tokens);

        assertTrue(factory.buildParamsAttested(strategyHash), "must be attested after a successful call");
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
                IPortfolioManagerStrategyFactory.PortfolioManagerStrategyFactoryShippedTokenNotDeclared.selector,
                address(tokenC)
            )
        );
        factory.attestBuildParameters(order, shipped);

        assertFalse(
            factory.buildParamsAttested(keccak256(abi.encode(order))), "a reverted attestation must not be recorded"
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
            IPortfolioManagerStrategyFactory.PortfolioManagerStrategyFactoryExcessivePriceDeviation.selector
        );
        factory.attestBuildParameters(order, tokens);
    }

    function test_AttestBuildParametersIsIdempotent() public {
        ISwapVM.Order memory order = _toleranceOrder(0.1e9);
        tokenA.mint(maker, 100_000e18);
        tokenB.mint(maker, 100_000e18);

        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        factory.attestBuildParameters(order, tokens);
        factory.attestBuildParameters(order, tokens); // must not revert

        assertTrue(factory.buildParamsAttested(keccak256(abi.encode(order))));
    }
}
