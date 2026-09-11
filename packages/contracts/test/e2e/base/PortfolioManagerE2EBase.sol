// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Aqua} from "aqua/Aqua.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {MakerTraitsLib} from "swap-vm/libs/MakerTraits.sol";
import {TakerTraitsLib} from "swap-vm/libs/TakerTraits.sol";

import {PortfolioManagerRouter} from "../../../src/PortfolioManagerRouter.sol";
import {PortfolioManagerProgramBuilder} from "../../../src/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerStrategyFactory} from "../../../src/PortfolioManagerStrategyFactory.sol";
import {MockTaker} from "../../../lib/swap-vm/test/mocks/MockTaker.sol";

/// @notice Shared setup for the PM strategy E2E suite: connects to the actually deployed
/// contracts `script/Deploy.s.sol` + `script/Deploy.mock.sol` put on chain
/// (`deployments/local.json`), not fresh in-test instances — mirroring
/// `BasketScopeGuardE2ETest`'s own pattern, but for the weighted-curve opcode and protocol fee
/// rather than the Guard.
///
/// Deliberately uses a *separate*, guard-less Safe (`Deploy.mock.sol`'s `pmSafe`) rather than
/// the Guard-protected one `BasketScopeGuardE2ETest` uses: these scenarios exercise the curve
/// and fee, not `BasketScopeGuard` (already fully covered on its own Safe), and reusing that
/// Safe would require coordinating a real PM strategy hash against its placeholder Guard config
/// for no benefit to what these tests actually check.
///
/// Trades real WETH/DAI (`Deploy.mock.sol`'s `pmTokenA`/`pmTokenB`, funded via `deal()`), not
/// mock tokens — same-decimal (both 18) real tokens on purpose, since the single-token-group
/// curve does no decimal normalization; see `Deploy.mock.sol`'s own note on why not USDC.
///
/// Requires `deployments/local.json` with the PM fixture fields `Deploy.mock.sol` adds — skips
/// entirely if the file's missing, so plain `forge test` without a prior `forge script
/// script/Deploy.s.sol --broadcast && forge script script/Deploy.mock.sol --broadcast` (or
/// `docker compose up`) still passes instead of failing on a missing file.
abstract contract PortfolioManagerE2EBase is Test {
    string internal constant MANIFEST_PATH = "deployments/local.json";

    uint256 internal constant INITIAL_BALANCE = 100_000e18;
    uint256 internal constant FEE_BPS_SCALE = 1e9;

    /// @dev Below PortfolioManagerProgramBuilder.TIER_THRESHOLD_BPS (≈0.1225%) — 1/4 tier.
    uint32 internal constant LOW_TIER_FEE_BPS = 0.02e9 / 100; // 2 bps, the existing ADR-0008 default

    Aqua internal aqua;
    PortfolioManagerRouter internal router;
    Safe internal pmSafe;
    IERC20 internal pmTokenA;
    IERC20 internal pmTokenB;
    address internal deployer;
    MockTaker internal taker;
    PortfolioManagerStrategyFactory internal strategyFactory;
    MultiSendCallOnly internal multiSendCallOnly;

    address[] internal universe;
    uint256[] internal weights;

    function setUp() public virtual {
        if (!vm.exists(MANIFEST_PATH)) {
            vm.skip(
                true,
                "deployments/local.json missing - run `forge script script/Deploy.s.sol --broadcast` then `forge script script/Deploy.mock.sol --broadcast` first"
            );
            return;
        }

        string memory json = vm.readFile(MANIFEST_PATH);
        aqua = Aqua(vm.parseJsonAddress(json, ".aqua"));
        router = PortfolioManagerRouter(payable(vm.parseJsonAddress(json, ".router")));
        pmSafe = Safe(payable(vm.parseJsonAddress(json, ".pmSafe")));
        pmTokenA = IERC20(vm.parseJsonAddress(json, ".pmTokenA"));
        pmTokenB = IERC20(vm.parseJsonAddress(json, ".pmTokenB"));
        deployer = vm.parseJsonAddress(json, ".deployer");
        strategyFactory = PortfolioManagerStrategyFactory(vm.parseJsonAddress(json, ".pmStrategyFactory"));
        multiSendCallOnly = MultiSendCallOnly(vm.parseJsonAddress(json, ".multiSendCallOnly"));

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

    /// @dev Funds the PM Safe with real universe-token balances (what `PortfolioManagerSwap`
    ///      actually reads via `balanceOf`, ADR-0002), then ships `order` through the Safe for
    ///      real — a genuine `execTransaction` from the deployer (the Safe's sole owner here),
    ///      because "ship from the dedicated wallet" is the scenario under test here. Funding
    ///      itself uses `deal()` since it's just setup plumbing, not the scenario under test.
    /// @param tokenInLedgerAmount Aqua-ledger amount shipped for tokenA specifically — kept
    ///        separate from the Safe's real wallet balance (always `INITIAL_BALANCE`, since
    ///        that's what the curve actually prices off) so a test can starve just the ledger
    ///        `_AQUA.pull()` draws from without touching real exposure.
    function _fundAndShip(ISwapVM.Order memory order, uint256 tokenInLedgerAmount) internal returns (bytes32) {
        deal(address(pmTokenA), address(pmSafe), INITIAL_BALANCE);
        deal(address(pmTokenB), address(pmSafe), INITIAL_BALANCE);

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

    /// @dev Just the execTransaction ship() call, no funding/approval -- split out of
    ///      `_fundAndShip` so that caller can skip straight to shipping once a wallet is already
    ///      funded/approved. Contains exactly one external call (`execTransaction`), so it's safe
    ///      to call directly under `vm.expectRevert()` too.
    ///
    ///      Routes through `MultiSendCallOnly` (PR review) rather than calling `Aqua.ship()`
    ///      directly: batches `PortfolioManagerStrategyFactory.requireUniverseMatches` and
    ///      `Aqua.ship` atomically, both legs still executed as plain calls originating from
    ///      `pmSafe` (`MultiSendCallOnly` structurally rejects nested delegatecalls), so a bad
    ///      strategy encoding never reaches Aqua's ledger at all -- while `Aqua.ship()`'s own
    ///      `msg.sender` stays `pmSafe`, exactly like a direct call would.  A factory that called
    ///      `Aqua.ship()` on the maker's behalf instead would key the ledger to the factory's own
    ///      address, breaking every real trade against the strategy (`Aqua.safeBalances`/
    ///      `SwapVM._transferIn` look the ledger up by `order.maker`, not by whoever shipped it)
    ///      -- confirmed empirically before landing on this design.
    function _shipOnly(ISwapVM.Order memory order, address[] memory tokens, uint256[] memory amounts)
        internal
        returns (bool)
    {
        bytes memory validateData =
            abi.encodeCall(PortfolioManagerStrategyFactory.requireUniverseMatches, (order, tokens));
        bytes memory shipData = abi.encodeCall(Aqua.ship, (address(router), abi.encode(order), tokens, amounts));

        bytes memory batch = abi.encodePacked(
            _encodeMultiSendTx(address(strategyFactory), validateData), _encodeMultiSendTx(address(aqua), shipData)
        );
        bytes memory multiSendData = abi.encodeCall(MultiSendCallOnly.multiSend, (batch));

        vm.prank(deployer);
        return pmSafe.execTransaction(
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
    }

    /// @dev `MultiSendCallOnly`'s own encoding: operation (always 0, call-only) + to (20 bytes) +
    ///      value (32 bytes) + data length (32 bytes) + data, packed with no padding.
    function _encodeMultiSendTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), to, uint256(0), data.length, data);
    }

    /// @dev Safe's `checkNSignatures` treats `v == 1` as a pre-approved hash, with the approving
    ///      owner's address packed into `r` (`s` unused) -- and when the transaction's executor
    ///      (`execTransaction`'s `msg.sender`) IS that owner, the check passes immediately with
    ///      no prior `approveHash()` call and no real ECDSA signature at all (`Safe.sol`'s
    ///      `executor != currentOwner` short-circuit, checked before the `approvedHashes` fallback).
    ///      `deployer` is `pmSafe`'s sole owner and every caller of this signature pranks as
    ///      `deployer` first, so this replaces needing a hardcoded private key to produce a real
    ///      signature -- Pedro's suggestion to "impersonate wallets directly" instead.
    function _selfApprovedSignature() internal view returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(deployer))), bytes32(0), uint8(1));
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

        deal(tokenIn, address(taker), amount * 2);
        return taker.swap(order, tokenIn, tokenOut, amount, takerData);
    }
}
