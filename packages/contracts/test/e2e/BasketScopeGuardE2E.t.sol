// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {BasketScopeGuard} from "../../src/BasketScopeGuard.sol";
import {Aqua} from "aqua/Aqua.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";

/// @notice Exercises the actual contracts `script/Deploy.s.sol` puts on chain — not fresh
/// in-test instances — via real `execTransaction` calls through the real deployed Safe, with
/// the real Guard already installed, against the real Aqua registry.
///
/// `BasketScopeGuard.t.sol` covers the Guard's rules in isolation and integration; this file
/// answers a different question: does the *actually deployed* environment (docker-compose's
/// anvil -> deploy -> test pipeline) enforce those same rules, end to end, against real
/// protocol state?
///
/// Requires deployments/local.json (written by Deploy.s.sol) — skips entirely if it doesn't
/// exist, so plain `forge test` without a prior `forge script script/Deploy.s.sol --broadcast`
/// (or `docker compose up`) still passes instead of failing on a missing file.
contract BasketScopeGuardE2ETest is Test {
    string internal constant MANIFEST_PATH = "deployments/local.json";

    Aqua internal aqua;
    BasketScopeGuard internal guard;
    Safe internal safe;
    address internal basketOneToken;
    address internal basketTwoToken;
    bytes32 internal pmStrategyHash;
    address internal deployer;

    address internal unknownToken = address(0xF00D);

    /// @dev Matches GuardManager.sol's GUARD_STORAGE_SLOT exactly (keccak256("guard_manager.guard.address")
    /// minus 1) — `getGuard()` is `internal` on Safe, so this is the only way to read it back
    /// from outside the contract.
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    function setUp() public {
        if (!vm.exists(MANIFEST_PATH)) {
            vm.skip(true, "deployments/local.json missing - run `forge script script/Deploy.s.sol --broadcast` first");
            return;
        }

        string memory json = vm.readFile(MANIFEST_PATH);
        aqua = Aqua(vm.parseJsonAddress(json, ".aqua"));
        guard = BasketScopeGuard(vm.parseJsonAddress(json, ".guard"));
        safe = Safe(payable(vm.parseJsonAddress(json, ".safe")));
        basketOneToken = vm.parseJsonAddress(json, ".basketOneToken");
        basketTwoToken = vm.parseJsonAddress(json, ".basketTwoToken");
        pmStrategyHash = vm.parseJsonBytes32(json, ".pmStrategyHash");
        deployer = vm.parseJsonAddress(json, ".deployer");

        // The manifest only tells us addresses — confirm the Guard is *actually* wired up on
        // the deployed Safe, not just sitting deployed-but-uninstalled somewhere.
        address installedGuard = address(uint160(uint256(vm.load(address(safe), GUARD_STORAGE_SLOT))));
        assertEq(installedGuard, address(guard), "deployed Safe must have the deployed Guard installed");

        // Same for onboarding: confirm attestOnboardingClean() was actually called for real
        // against this deployed Guard, not just that PM's strategy happens to ship for some
        // other reason.
        assertTrue(guard.onboardingAttested(), "deployed Guard must have onboarding attested");
    }

    function _shipCalldata(bytes memory strategy, address[] memory tokens) internal pure returns (bytes memory) {
        uint256[] memory amounts = new uint256[](tokens.length);
        return abi.encodeCall(Aqua.ship, (address(0xAAAA), strategy, tokens, amounts));
    }

    /// @dev Safe's `v == 1` pre-approved-hash signature trick -- see
    ///      PortfolioManagerE2EBase.sol's `_selfApprovedSignature` for the full mechanism.
    ///      `deployer` is `safe`'s sole owner, and every caller pranks as `deployer` first.
    function _selfApprovedSignature() internal view returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(deployer))), bytes32(0), uint8(1));
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

        // Must match Deploy.s.sol's PM_STRATEGY_HASH exactly, or this is just another
        // untrusted strategy and the cross-basket ship below would (correctly) fail — this
        // reproduces that fixed placeholder strategy payload, not the hash directly, so the
        // test is actually exercising Aqua's own `keccak256(strategy)` computation matching
        // the Guard's stored hash, not just asserting a hash equality in isolation.
        bytes memory pmStrategy = "placeholder-pm-strategy";
        assertEq(keccak256(pmStrategy), pmStrategyHash, "test's PM strategy payload must match the deployed hash");

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
