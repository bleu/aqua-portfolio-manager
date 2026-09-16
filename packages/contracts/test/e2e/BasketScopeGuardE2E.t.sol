// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Aqua} from "aqua/Aqua.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {BasketScopeGuard} from "../../src/BasketScopeGuard.sol";
import {AquaE2EBase} from "./base/AquaE2EBase.t.sol";

/// @notice Exercises `BasketScopeGuard` for real: on top of `AquaE2EBase`'s forked Aqua/Safe
/// infra, deploys a real Guard, installs it on a fresh Safe, attests onboarding, then ships
/// through it via real `execTransaction` calls against the real Aqua registry — no external
/// Anvil, no deploy script, no `deployments/local.json`.
///
/// `BasketScopeGuard.t.sol` already covers the Guard's rules in isolation and integration
/// against fresh-deployed contracts; this file's only remaining job is confirming the same rules
/// hold against the *real* Aqua registry on a real fork, not a clean-room chain.
///
/// The Guard's example basket config (WETH in basket 1, a synthetic placeholder in basket 2) and
/// the PM trusted-strategy hash are placeholders — no real Portfolio Manager strategy or second
/// basket asset has been decided for a real deployment yet (M2/M3 scope); this fixture's job is
/// proving the Guard mechanism works end to end against real Aqua state, not shipping final
/// parameters.
contract BasketScopeGuardE2ETest is AquaE2EBase {
    /// @dev WETH predeploy address, standard across every OP-stack chain (Base included).
    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    /// @dev Not a real token — ship() never transfers tokens at ship time (confirmed against
    ///      Aqua.sol directly), so a synthetic address is fine as a second basket for this
    ///      placeholder config. Real group membership is M2/M3 scope.
    address internal constant SYNTHETIC_TOKEN_B = 0x000000000000000000000000000000000000b0b0;
    /// @dev Placeholder PM strategy hash — fixed (not derived from a real `strategy` payload) so
    ///      this test can independently reproduce it to exercise the Guard's PM-exemption rule.
    bytes32 internal constant PM_STRATEGY_HASH = keccak256("placeholder-pm-strategy");

    BasketScopeGuard internal guard;
    Safe internal safe;
    address internal basketOneToken = WETH_BASE;
    address internal basketTwoToken = SYNTHETIC_TOKEN_B;

    address internal unknownToken = address(0xF00D);

    function setUp() public override {
        super.setUp();

        safe = _newSafe(0); // distinct salt nonce from the PM fixtures' Safes

        address[] memory tokens = new address[](2);
        tokens[0] = basketOneToken;
        tokens[1] = basketTwoToken;
        uint256[] memory basketIds = new uint256[](2);
        basketIds[0] = 1;
        basketIds[1] = 2;
        guard = new BasketScopeGuard(address(aqua), address(safe), PM_STRATEGY_HASH, tokens, basketIds);

        // Install the Guard on the Safe for real, so this test exercises the actual enforced
        // state, not just a deployed-but-inert Guard contract.
        bytes memory setGuardData = abi.encodeWithSignature("setGuard(address)", address(guard));
        vm.prank(deployer);
        bool guardInstalled = safe.execTransaction(
            address(safe),
            0,
            setGuardData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _selfApprovedSignature()
        );
        require(guardInstalled, "setGuard failed");

        // Attest onboarding is clean. In a real onboarding flow this only happens after actually
        // running an off-chain onboarding pre-existing-strategy check against this Safe's real
        // Shipped-event history and confirming no violation. Here it's auto-attested: this is a
        // fresh Safe on a fresh fork with no prior activity, so there is nothing for that check
        // to find — but the attestation call itself is real and signed, exactly as it would be
        // in production, so this still exercises the actual gate PM's strategy ships through.
        bytes memory attestData = abi.encodeWithSignature("attestOnboardingClean()");
        vm.prank(deployer);
        bool attested = safe.execTransaction(
            address(guard),
            0,
            attestData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _selfApprovedSignature()
        );
        require(attested, "attestOnboardingClean failed");
    }

    function _shipCalldata(bytes memory strategy, address[] memory tokens) internal pure returns (bytes memory) {
        uint256[] memory amounts = new uint256[](tokens.length);
        return abi.encodeCall(Aqua.ship, (address(0xAAAA), strategy, tokens, amounts));
    }

    /// @dev Contains exactly one external call (`execTransaction`), so it's safe to call directly
    ///      under `vm.expectRevert()` too.
    function _shipThroughSafe(bytes memory strategy, address[] memory tokens) internal returns (bool) {
        bytes memory shipData = _shipCalldata(strategy, tokens);
        vm.prank(deployer);
        return safe.execTransaction(
            address(aqua),
            0,
            shipData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            _selfApprovedSignature()
        );
    }

    function test_E2E_DeployedSafeShipsSingleBasketStrategy() public {
        address[] memory tokens = new address[](1);
        tokens[0] = basketOneToken;

        bool ok = _shipThroughSafe("e2e single-basket strategy", tokens);
        assertTrue(ok, "a real single-basket ship() through the deployed Safe should succeed");
    }

    function test_E2E_DeployedSafeShipsPmStrategyAcrossBaskets() public {
        address[] memory tokens = new address[](2);
        tokens[0] = basketOneToken;
        tokens[1] = basketTwoToken;

        bytes memory pmStrategy = "placeholder-pm-strategy";
        assertEq(keccak256(pmStrategy), PM_STRATEGY_HASH, "test's PM strategy payload must match the Guard's hash");

        bool ok = _shipThroughSafe(pmStrategy, tokens);
        assertTrue(ok, "PM's own strategy should be allowed to span baskets on the deployed Safe");
    }

    function test_E2E_DeployedSafeBlocksCrossBasketShip() public {
        address[] memory tokens = new address[](2);
        tokens[0] = basketOneToken;
        tokens[1] = basketTwoToken;

        vm.expectRevert();
        _shipThroughSafe("e2e attacker strategy", tokens);
    }

    function test_E2E_DeployedSafeBlocksTokenOutsideUniverse() public {
        address[] memory tokens = new address[](2);
        tokens[0] = basketOneToken;
        tokens[1] = unknownToken;

        vm.expectRevert();
        _shipThroughSafe("e2e outside-universe strategy", tokens);
    }
}
