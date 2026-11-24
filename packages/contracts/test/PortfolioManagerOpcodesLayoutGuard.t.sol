// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Aqua} from "aqua/Aqua.sol";
import {TokenMock} from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";
import {Controls} from "swap-vm/instructions/Controls.sol";
import {MockTaker} from "../lib/swap-vm/test/mocks/MockTaker.sol";

import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {GatedPortfolioManagerProgramBuilder} from "../src/utils/GatedPortfolioManagerProgramBuilder.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {PortfolioManagerTokenRegistry} from "../src/utils/PortfolioManagerTokenRegistry.sol";
import {PortfolioManagerFeedRegistry} from "../src/utils/PortfolioManagerFeedRegistry.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice `PortfolioManagerOpcodes._opcodes()`'s array order has no compiler-enforced link to
/// the `CURVE_OPCODE`/`KYC_GATE_OPCODE` indices hardcoded into `PortfolioManagerProgramBuilder.sol`
/// and `GatedPortfolioManagerProgramBuilder.sol` (see `PortfolioManagerOpcodes.CURVE_OPCODE`'s own
/// doc comment for why a runtime check isn't viable here). This test is the actual guard: it ships
/// a strategy built by the real `GatedPortfolioManagerProgramBuilder` and proves opcode byte 0
/// still settles the curve swap while opcode byte 1 still enforces the resolver KYC gate.
/// Reordering or extending `_opcodes()` without updating both builders in lockstep fails this
/// test -- either the swap stops settling, or the KYC gate stops blocking an uncredentialed
/// resolver.
contract PortfolioManagerOpcodesLayoutGuardTest is Test {
    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant SWAP_AMOUNT = 1_000e18;
    uint32 internal constant DEFAULT_MAX_STALENESS = 1 hours;
    address internal constant DAO_TREASURY_TEST = address(0xDA0);
    address internal constant TRIM_TREASURY_TEST = address(0x7121);
    uint32 internal constant FEE_RATE_BPS = 166_666_667;

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    PortfolioManagerStrategyValidator internal strategyValidator;
    PortfolioManagerTokenRegistry internal tokenRegistry;
    PortfolioManagerFeedRegistry internal feedRegistry;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    TokenMock internal resolverKycToken;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;

    address internal maker;
    address internal credentialedResolver;
    address internal uncredentialedResolver;

    PortfolioManagerArgsCodec.Group[] internal groups;
    ISwapVM.Order internal order;

    function setUp() public {
        vm.warp(1_000_000);
        MockAggregatorV3 sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 2 hours);

        aqua = new Aqua();
        tokenRegistry = new PortfolioManagerTokenRegistry();
        feedRegistry = new PortfolioManagerFeedRegistry(address(this));
        strategyValidator = new PortfolioManagerStrategyValidator(
            address(sequencerFeed), address(tokenRegistry), address(feedRegistry)
        );
        router = new PortfolioManagerRouter(
            address(aqua),
            address(0),
            address(this),
            "PM",
            "1",
            address(strategyValidator),
            address(sequencerFeed),
            address(tokenRegistry),
            address(feedRegistry),
            DAO_TREASURY_TEST,
            TRIM_TREASURY_TEST,
            FEE_RATE_BPS,
            FEE_RATE_BPS
        );

        tokenA = new TokenMock("Token A", "TKA");
        tokenB = new TokenMock("Token B", "TKB");
        resolverKycToken = new TokenMock("Aqua Resolver", "RES");
        feedA = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedB = new MockAggregatorV3(18, 1e18, block.timestamp);

        maker = vm.addr(0x1234);
        credentialedResolver = vm.addr(0xA11CE);
        uncredentialedResolver = vm.addr(0xBEEF);
        resolverKycToken.mint(credentialedResolver, 1);

        PortfolioManagerArgsCodec.Member[] memory membersA = new PortfolioManagerArgsCodec.Member[](1);
        membersA[0] = PortfolioManagerArgsCodec.Member({
            tokenIndex: tokenRegistry.register(address(tokenA)),
            feedIndex: feedRegistry.register(address(feedA), DEFAULT_MAX_STALENESS)
        });
        groups.push(PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersA}));

        PortfolioManagerArgsCodec.Member[] memory membersB = new PortfolioManagerArgsCodec.Member[](1);
        membersB[0] = PortfolioManagerArgsCodec.Member({
            tokenIndex: tokenRegistry.register(address(tokenB)),
            feedIndex: feedRegistry.register(address(feedB), DEFAULT_MAX_STALENESS)
        });
        groups.push(PortfolioManagerArgsCodec.Group({weight: 0.5e18, members: membersB}));

        bytes memory program = GatedPortfolioManagerProgramBuilder.build(groups, 5e6, address(resolverKycToken));
        order = MakerTraitsLib.build(
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
        amounts[0] = INITIAL_BALANCE;
        amounts[1] = INITIAL_BALANCE;
        strategyValidator.attestBuildParameters(order, tokens, new string[](0));
        vm.prank(maker);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
    }

    function _exactInTakerData() internal pure returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(0),
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

    /// @notice Pins `_opcodes()[CURVE_OPCODE]` (index 0) to the curve swap: a credentialed
    /// resolver's trade must still settle through it.
    function test_OpcodeZeroStillSettlesTheCurveSwap() public {
        MockTaker taker = new MockTaker(aqua, router, credentialedResolver);
        tokenA.mint(address(taker), SWAP_AMOUNT * 2);

        vm.prank(credentialedResolver, credentialedResolver);
        taker.swap(order, address(tokenA), address(tokenB), SWAP_AMOUNT, _exactInTakerData());

        assertGt(tokenB.balanceOf(maker), 0, "opcode 0 must still dispatch to the curve swap");
    }

    /// @notice Pins `_opcodes()[KYC_GATE_OPCODE]` (index 1) to the resolver KYC gate: an
    /// uncredentialed resolver must still be blocked before the curve swap ever runs.
    function test_OpcodeOneStillEnforcesTheKycGate() public {
        MockTaker taker = new MockTaker(aqua, router, uncredentialedResolver);
        tokenA.mint(address(taker), SWAP_AMOUNT * 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                Controls.TxOriginTokenBalanceIsZero.selector, uncredentialedResolver, address(resolverKycToken)
            )
        );
        vm.prank(uncredentialedResolver, uncredentialedResolver);
        taker.swap(order, address(tokenA), address(tokenB), SWAP_AMOUNT, _exactInTakerData());
    }
}
