// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {BasketScopeGuard} from "../src/BasketScopeGuard.sol";
import {BasketScopeGuardFactory} from "../src/BasketScopeGuardFactory.sol";
import {Aqua} from "aqua/Aqua.sol";

contract BasketScopeGuardFactoryTest is Test {
    Aqua internal aqua;
    BasketScopeGuardFactory internal factory;

    address internal tokenA = address(0xA11CE);
    address internal tokenB = address(0xB0B);
    address internal safe_ = address(0x5AFE);
    bytes32 internal pmStrategyHash = keccak256("PM STRATEGY");
    address internal constant TRUSTED_PM_ROUTER = address(0xAAAA);

    address[] internal tokens;
    uint256[] internal basketIds;

    function setUp() public {
        aqua = new Aqua();
        factory = new BasketScopeGuardFactory();

        tokens.push(tokenA);
        tokens.push(tokenB);
        basketIds.push(1);
        basketIds.push(1);
    }

    /// @dev The whole point of the factory: computeAddress must predict correctly *before* the
    ///      Guard exists, not just match in hindsight -- called here ahead of `deploy`, same as
    ///      an off-chain caller building a batch would.
    function test_ComputeAddressMatchesRealDeploymentPredictedInAdvance() public {
        address predicted =
            factory.computeAddress(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);
        assertEq(predicted.code.length, 0, "must be predictable before any code exists there");

        address deployed = factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);

        assertEq(deployed, predicted, "deployed address must match the prediction exactly");
        assertGt(predicted.code.length, 0, "the predicted address must actually hold the Guard now");
    }

    function test_DeployedGuardHasTheExactConfigurationPassedIn() public {
        address deployed = factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);
        BasketScopeGuard guard = BasketScopeGuard(deployed);

        assertEq(guard.AQUA(), address(aqua));
        assertEq(guard.SAFE(), safe_);
        assertEq(guard.TRUSTED_PM_STRATEGY_HASH(), pmStrategyHash);
        assertEq(guard.TRUSTED_PM_ROUTER(), TRUSTED_PM_ROUTER);
        assertEq(guard.basketOf(tokenA), 1);
        assertEq(guard.basketOf(tokenB), 1);
    }

    /// @notice Retrying `deploy` with identical arguments after an earlier success
    /// returns the same address instead of reverting -- no silent second Guard either, since
    /// CREATE2 can't redeploy there, but the caller gets a usable result back, not a failed batch.
    function test_DeployReturnsSameAddressOnRetryWithIdenticalArguments() public {
        address first = factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);

        address second = factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);

        assertEq(second, first, "retrying with the same configuration must return the same Guard address");
    }

    /// @notice The front-running scenario `deploy`'s own doc comment describes: someone else
    /// deploys the identical configuration first (simulated here by calling `deploy` directly with
    /// the same arguments, which is indistinguishable on-chain from a front-runner's own call).
    /// The real owner's later `deploy()` step in the same atomic batch must not revert.
    function test_DeployAfterAnotherCallerFrontRanWithIdenticalArgumentsDoesNotRevert() public {
        vm.prank(address(0xBADBAD));
        address frontRun = factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);

        address ownersResult =
            factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);

        assertEq(ownersResult, frontRun, "the real owner's own deploy step must resolve to the front-run address");
    }

    function test_EmitsGuardAlreadyDeployedInsteadOfGuardDeployedOnRetry() public {
        address deployed = factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);

        vm.expectEmit(true, true, true, true);
        emit BasketScopeGuardFactory.GuardAlreadyDeployed(deployed, safe_, pmStrategyHash, address(aqua));
        factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);
    }

    function test_DifferentStrategyHashesProduceDifferentAddresses() public view {
        address addr1 =
            factory.computeAddress(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);
        address addr2 = factory.computeAddress(
            address(aqua), safe_, keccak256("DIFFERENT STRATEGY"), TRUSTED_PM_ROUTER, tokens, basketIds
        );
        assertTrue(addr1 != addr2, "distinct configurations must never collide");
    }

    function test_DifferentSafesProduceDifferentAddresses() public view {
        address addr1 =
            factory.computeAddress(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);
        address addr2 = factory.computeAddress(
            address(aqua), address(0x5AFE2), pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds
        );
        assertTrue(addr1 != addr2, "two Safes requesting the same strategy hash must not collide");
    }

    function test_EmitsGuardDeployedWithTheRealAddress() public {
        address predicted =
            factory.computeAddress(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);

        vm.expectEmit(true, true, true, true);
        emit BasketScopeGuardFactory.GuardDeployed(predicted, safe_, pmStrategyHash, address(aqua));
        factory.deploy(address(aqua), safe_, pmStrategyHash, TRUSTED_PM_ROUTER, tokens, basketIds);
    }
}
