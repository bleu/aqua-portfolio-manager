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
import {PortfolioManagerProgramBuilder} from "../src/utils/PortfolioManagerProgramBuilder.sol";
import {GatedPortfolioManagerProgramBuilder} from "../src/utils/GatedPortfolioManagerProgramBuilder.sol";
import {PortfolioManagerArgsCodec} from "../src/utils/PortfolioManagerArgsCodec.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {MockAggregatorV3} from "./OracleAdapter.t.sol";

/// @notice Proves the resolver KYC gate: a strategy built with `GatedPortfolioManagerProgramBuilder`
/// only trades for a `tx.origin` holding the configured credential token, while a strategy built
/// with the plain, ungated `PortfolioManagerProgramBuilder` is completely unaffected by the new
/// opcode's presence in `PortfolioManagerOpcodes`.
contract GatedPortfolioManagerProgramBuilderTest is Test {
    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant SWAP_AMOUNT = 1_000e18;

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    PortfolioManagerStrategyValidator internal strategyValidator;
    TokenMock internal tokenA;
    TokenMock internal tokenB;
    TokenMock internal resolverKycToken;
    MockAggregatorV3 internal feedA;
    MockAggregatorV3 internal feedB;

    address internal maker;
    address internal credentialedResolver;
    address internal uncredentialedResolver;

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
        // Stands in for 1inch's real per-chain KycNFT -- Controls._onlyTxOriginTokenBalanceNonZero
        // only ever calls IERC20(token).balanceOf(tx.origin), so any ERC20-shaped mock is a
        // faithful stand-in for the real ERC721 credential (same interface call, see Controls.sol's
        // own "NFTs are natively supported" doc comment).
        resolverKycToken = new TokenMock("Aqua Resolver", "RES");

        feedA = new MockAggregatorV3(18, 1e18, block.timestamp);
        feedB = new MockAggregatorV3(18, 1e18, block.timestamp);

        maker = vm.addr(0x1234);
        credentialedResolver = vm.addr(0xA11CE);
        uncredentialedResolver = vm.addr(0xBEEF);
        resolverKycToken.mint(credentialedResolver, 1);

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
        members[0] = PortfolioManagerArgsCodec.Member({token: token, feed: feed, maxStaleness: 18 hours});
        return PortfolioManagerArgsCodec.Group({weight: weight, members: members});
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

    function _shipOrder(ISwapVM.Order memory order) internal returns (bytes32) {
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

        strategyValidator.attestBuildParameters(order, tokens);

        vm.prank(maker);
        return aqua.ship(address(router), abi.encode(order), tokens, amounts);
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

    /// @dev `resolverOrigin` is set as both the taker owner and, critically, `tx.origin` for the
    ///      swap call -- `vm.prank`'s two-arg form is required here since the gate reads
    ///      `tx.origin`, not `msg.sender`, and a bare one-arg prank never touches `tx.origin`.
    /// @dev Returns the funded taker instead of also calling `swap()` itself -- `vm.expectRevert`
    ///      attaches to the very next call, so every setup call (deploying `MockTaker`, minting)
    ///      must happen *before* a caller sets up its own `expectRevert`, not folded into a helper
    ///      that runs after it.
    function _fundedTakerFor(address resolverOrigin) internal returns (MockTaker taker) {
        taker = new MockTaker(aqua, router, resolverOrigin);
        tokenA.mint(address(taker), SWAP_AMOUNT * 2);
    }

    // ===== Tests =====

    function test_GatedStrategyRevertsForUncredentialedResolver() public {
        bytes memory program = GatedPortfolioManagerProgramBuilder.build(groups, 0, address(resolverKycToken));
        ISwapVM.Order memory order = _orderForProgram(program);
        _shipOrder(order);
        MockTaker taker = _fundedTakerFor(uncredentialedResolver);

        vm.expectRevert(
            abi.encodeWithSelector(
                Controls.TxOriginTokenBalanceIsZero.selector, uncredentialedResolver, address(resolverKycToken)
            )
        );
        vm.prank(uncredentialedResolver, uncredentialedResolver);
        taker.swap(order, address(tokenA), address(tokenB), SWAP_AMOUNT, _exactInTakerData());
    }

    /// @dev `address(0)` has no code, so `IERC20(token).balanceOf(...)` fails ABI-decoding the
    ///      empty returndata instead of hitting `TxOriginTokenBalanceIsZero` -- still fails safe
    ///      (no uncredentialed swap goes through), just with a different, less informative revert.
    function test_GatedStrategyRevertsForZeroAddressToken() public {
        bytes memory program = GatedPortfolioManagerProgramBuilder.build(groups, 0, address(0));
        ISwapVM.Order memory order = _orderForProgram(program);
        _shipOrder(order);
        MockTaker taker = _fundedTakerFor(uncredentialedResolver);

        vm.expectRevert();
        vm.prank(uncredentialedResolver, uncredentialedResolver);
        taker.swap(order, address(tokenA), address(tokenB), SWAP_AMOUNT, _exactInTakerData());
    }

    function test_GatedStrategySucceedsForCredentialedResolver() public {
        bytes memory program = GatedPortfolioManagerProgramBuilder.build(groups, 0, address(resolverKycToken));
        ISwapVM.Order memory order = _orderForProgram(program);
        _shipOrder(order);
        MockTaker taker = _fundedTakerFor(credentialedResolver);

        vm.prank(credentialedResolver, credentialedResolver);
        taker.swap(order, address(tokenA), address(tokenB), SWAP_AMOUNT, _exactInTakerData());

        assertGt(tokenB.balanceOf(maker), 0, "credentialed resolver's swap must actually settle");
    }

    /// @notice The new opcode's presence in `PortfolioManagerOpcodes` must be completely inert
    /// for strategies built with the plain, ungated builder -- proves adding the gate opcode
    /// didn't change behavior for anything that doesn't reference it.
    function test_UngatedStrategyUnaffectedByNewOpcodePresence() public {
        bytes memory program = PortfolioManagerProgramBuilder.build(groups, 0);
        ISwapVM.Order memory order = _orderForProgram(program);
        _shipOrder(order);
        // Neither resolver holds anything special here -- the point is that it doesn't matter.
        MockTaker taker = _fundedTakerFor(uncredentialedResolver);

        vm.prank(uncredentialedResolver, uncredentialedResolver);
        taker.swap(order, address(tokenA), address(tokenB), SWAP_AMOUNT, _exactInTakerData());

        assertGt(tokenB.balanceOf(maker), 0, "ungated strategy must trade regardless of tx.origin's KYC status");
    }
}
