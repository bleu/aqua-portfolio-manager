// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Aqua} from "aqua/Aqua.sol";
import {TokenMock} from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";

import {PortfolioManagerRouter} from "../../src/PortfolioManagerRouter.sol";
import {PortfolioManagerProgramBuilder} from "../../src/PortfolioManagerProgramBuilder.sol";
import {MockTaker} from "../../lib/swap-vm/test/mocks/MockTaker.sol";

/// @notice Shared setup for the PM strategy E2E suite (BLEUDEV-340 and children): connects to
/// the actually deployed contracts `script/Deploy.s.sol` puts on chain
/// (`deployments/local.json`), not fresh in-test instances — mirroring
/// `BasketScopeGuardE2ETest`'s own pattern, but for the weighted-curve opcode and protocol fee
/// (BLEUDEV-327) rather than the Guard.
///
/// Deliberately uses a *separate*, guard-less Safe (`Deploy.s.sol`'s `pmSafe`) rather than the
/// Guard-protected one `BasketScopeGuardE2ETest` uses: these scenarios exercise the curve and
/// fee, not `BasketScopeGuard` (already fully covered on its own Safe), and reusing that Safe
/// would require coordinating a real PM strategy hash against its placeholder Guard config for
/// no benefit to what these tests actually check.
///
/// Requires `deployments/local.json` — skips entirely if it doesn't exist, so plain `forge
/// test` without a prior `forge script script/Deploy.s.sol --broadcast` (or `docker compose
/// up`) still passes instead of failing on a missing file.
abstract contract PortfolioManagerE2EBase is Test {
    string internal constant MANIFEST_PATH = "deployments/local.json";

    /// @dev Matches script/Deploy.s.sol's DEFAULT_DEPLOYER_KEY — the deployer is also the PM
    /// Safe's sole owner in this environment, test-only, never a real key.
    uint256 internal constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant FEE_BPS_SCALE = 1e9;

    /// @dev Below PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS (≈0.1225%) — 1/4 tier.
    uint32 internal constant LOW_TIER_FEE_BPS = 0.02e9 / 100; // 2 bps, the existing ADR-0008 default

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    Safe internal pmSafe;
    TokenMock internal pmTokenA;
    TokenMock internal pmTokenB;
    address internal deployer;
    MockTaker internal taker;

    address[] internal universe;
    uint256[] internal weights;

    function setUp() public virtual {
        if (!vm.exists(MANIFEST_PATH)) {
            vm.skip(true, "deployments/local.json missing - run `forge script script/Deploy.s.sol --broadcast` first");
            return;
        }

        string memory json = vm.readFile(MANIFEST_PATH);
        aqua = Aqua(vm.parseJsonAddress(json, ".aqua"));
        router = PortfolioManagerRouter(payable(vm.parseJsonAddress(json, ".router")));
        pmSafe = Safe(payable(vm.parseJsonAddress(json, ".pmSafe")));
        pmTokenA = TokenMock(vm.parseJsonAddress(json, ".pmTokenA"));
        pmTokenB = TokenMock(vm.parseJsonAddress(json, ".pmTokenB"));
        deployer = vm.parseJsonAddress(json, ".deployer");

        taker = new MockTaker(aqua, router, address(this));

        universe = new address[](2);
        universe[0] = address(pmTokenA);
        universe[1] = address(pmTokenB);
        weights = new uint256[](2);
        weights[0] = 0.5e18;
        weights[1] = 0.5e18;
    }

    function _buildOrder(uint32 lpFeeBps) internal view returns (ISwapVM.Order memory) {
        bytes memory program = PortfolioManagerProgramBuilder.build(universe, weights, lpFeeBps);

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

    /// @dev Funds the PM Safe with real universe-token balances (what `ExposureReader` actually
    ///      reads, ADR-0002), then ships `order` through the Safe for real — a genuine
    ///      `execTransaction`, signed by the deployer (the Safe's sole owner here), not a
    ///      `vm.prank` shortcut, because "ship from the dedicated wallet" is exactly what
    ///      BLEUDEV-286 exists to prove. Funding itself uses `vm.prank` since it's just setup
    ///      plumbing, not the scenario under test.
    /// @param tokenInLedgerAmount Aqua-ledger amount shipped for tokenA specifically — kept
    ///        separate from the Safe's real wallet balance (always `INITIAL_BALANCE`, since
    ///        that's what the curve actually prices off) so a test can starve just the ledger
    ///        `_AQUA.pull()` draws from without touching real exposure.
    function _fundAndShip(ISwapVM.Order memory order, uint256 tokenInLedgerAmount) internal returns (bytes32) {
        vm.prank(deployer);
        pmTokenA.mint(address(pmSafe), INITIAL_BALANCE);
        vm.prank(deployer);
        pmTokenB.mint(address(pmSafe), INITIAL_BALANCE);

        vm.prank(address(pmSafe));
        pmTokenA.approve(address(aqua), type(uint256).max);
        vm.prank(address(pmSafe));
        pmTokenB.approve(address(aqua), type(uint256).max);

        address[] memory tokens = new address[](2);
        tokens[0] = address(pmTokenA);
        tokens[1] = address(pmTokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = tokenInLedgerAmount;
        amounts[1] = INITIAL_BALANCE;

        bool ok = _shipOnly(order, tokens, amounts);
        require(ok, "ship through PM Safe failed");

        bytes32 strategyHash = keccak256(abi.encode(order));
        assertEq(strategyHash, router.hash(order), "strategy hash must match order hash");
        return strategyHash;
    }

    /// @dev Just the sign-and-execTransaction ship() call, no funding/approval -- split out of
    ///      `_fundAndShip` so that caller can skip straight to shipping once a wallet is already
    ///      funded/approved. NOT safe to call under `vm.expectRevert()`: it bundles the
    ///      non-reverting `getTransactionHash` view call together with the reverting
    ///      `execTransaction` call in one internal function, and `vm.expectRevert()` attaches to
    ///      the next *external* call regardless of which internal function it's nested inside --
    ///      a negative test needs to compute the signed calldata inline, entirely outside the
    ///      armed window, the way `PortfolioManagerShipE2E.t.sol`'s
    ///      `test_ShippedStrategyIsImmutableOnReattempt` does.
    function _shipOnly(ISwapVM.Order memory order, address[] memory tokens, uint256[] memory amounts)
        internal
        returns (bool)
    {
        bytes memory shipData = abi.encodeCall(Aqua.ship, (address(router), abi.encode(order), tokens, amounts));
        bytes32 txHash = pmSafe.getTransactionHash(
            address(aqua), 0, shipData, Enum.Operation.Call, 0, 0, 0, address(0), address(0), pmSafe.nonce()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DEPLOYER_KEY, txHash);
        return pmSafe.execTransaction(
            address(aqua),
            0,
            shipData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            abi.encodePacked(r, s, v)
        );
    }

    function _swapExactIn(ISwapVM.Order memory order, address tokenIn, address tokenOut, uint256 amount)
        internal
        returns (uint256, uint256)
    {
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

        vm.prank(deployer);
        TokenMock(tokenIn).mint(address(taker), amount * 2);
        return taker.swap(order, tokenIn, tokenOut, amount, takerData);
    }
}
