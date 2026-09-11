// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

/// @notice Deploys the test-fixture wallet the PM strategy E2E suite trades against — run
/// separately, after Deploy.s.sol, only by whoever needs that suite. Reads
/// deployments/local.json for the real deployer/Safe infra Deploy.s.sol already put on chain
/// (no separate Safe singleton/factory deployment here, reuses the real ones), and extends the
/// same manifest with this fixture's own addresses.
///
/// No TokenMock: the PM E2E suite trades real WETH and real Base DAI (both live on the fork this
/// environment runs against), funded via `deal()` rather than a mint-gated fake token --
/// exercises real token contract behavior instead of a simplified stand-in, and there's nothing
/// for a Deploy.s.sol reader to mistake for "what production deployment looks like," since this
/// is a clearly separate, clearly-named script.
///
/// DAI, not USDC: both WETH and DAI are 18-decimal. The production PM curve for a single-token
/// group (BLEUDEV-281's current scope) reads raw `balanceOf` with no decimal normalization at
/// all -- normalization only happens in `OracleAdapter`, for multi-token groups, which isn't
/// wired into the single-token-group path. Pairing WETH with a 6-decimal token like USDC would
/// make the curve treat 1 wei of WETH as equal-weight to 1 unit (1e-6) of USDC -- not a fixture
/// bug, a real limitation of the current curve scope this fixture would otherwise silently paper
/// over by picking numbers that happen to "work." Same-decimal real tokens sidestep it and keep
/// this suite testing what it's actually meant to.
/// @dev Inherits `StdCheats` (not just `Script`'s own `StdCheatsSafe` subset) specifically for
///      `deal()` — safe here because this script only ever runs against a local/forked network,
///      never a real broadcast (`deal()` writes storage directly, which isn't meaningful on a
///      real chain).
contract DeployMock is Script, StdCheats {
    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    /// @dev DAI on Base — https://basescan.org/token/0x50c5725949a6f0c72e6c4a641f24049a917db0cb
    address internal constant DAI_BASE = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

    uint256 internal constant DEFAULT_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    uint256 internal constant PM_UNIVERSE_FUNDING = 100_000e18;

    function run() external {
        string memory existing = vm.readFile("deployments/local.json");
        address aqua = vm.parseJsonAddress(existing, ".aqua");
        address router = vm.parseJsonAddress(existing, ".router");
        address safe = vm.parseJsonAddress(existing, ".safe");
        address guard = vm.parseJsonAddress(existing, ".guard");
        bytes32 pmStrategyHash = vm.parseJsonBytes32(existing, ".pmStrategyHash");
        address basketOneToken = vm.parseJsonAddress(existing, ".basketOneToken");
        address basketTwoToken = vm.parseJsonAddress(existing, ".basketTwoToken");
        address deployer = vm.parseJsonAddress(existing, ".deployer");
        Safe singleton = Safe(payable(vm.parseJsonAddress(existing, ".safeSingleton")));
        SafeProxyFactory factory = SafeProxyFactory(vm.parseJsonAddress(existing, ".safeFactory"));

        uint256 deployerPk = vm.envOr("DEPLOYER_PRIVATE_KEY", DEFAULT_DEPLOYER_KEY);

        vm.startBroadcast(deployerPk);

        // A second, separate dedicated maker wallet (ADR-0002) for the PM strategy E2E suite —
        // deliberately *not* the Guard-protected Safe Deploy.s.sol deploys: those tests exercise
        // the real weighted-curve opcode and protocol fee, not BasketScopeGuard (already fully
        // covered by BasketScopeGuardE2E.t.sol on that Safe), so a plain, guard-less Safe keeps
        // this from having to coordinate a real PM strategy hash against the other Safe's
        // placeholder Guard config.
        address[] memory owners = new address[](1);
        owners[0] = deployer;
        bytes memory setupData = abi.encodeWithSelector(
            Safe.setup.selector, owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))
        );
        Safe pmSafe = Safe(
            payable(
                address(
                    factory.createProxyWithNonce(
                        address(singleton),
                        setupData,
                        1 // different salt nonce than Deploy.s.sol's Guard-protected Safe
                    )
                )
            )
        );
        console.log("PM Safe deployed at", address(pmSafe));

        vm.stopBroadcast();

        // deal() writes storage directly -- not a broadcast transaction, doesn't need
        // vm.startBroadcast, and works against any ERC20 including ones without a public mint.
        deal(WETH_BASE, address(pmSafe), PM_UNIVERSE_FUNDING);
        deal(DAI_BASE, address(pmSafe), PM_UNIVERSE_FUNDING);
        console.log("PM Safe funded with real WETH/DAI via deal()");

        string memory objectKey = "deployment";
        vm.serializeAddress(objectKey, "aqua", aqua);
        vm.serializeAddress(objectKey, "router", router);
        vm.serializeAddress(objectKey, "safe", safe);
        vm.serializeAddress(objectKey, "guard", guard);
        vm.serializeBytes32(objectKey, "pmStrategyHash", pmStrategyHash);
        vm.serializeAddress(objectKey, "basketOneToken", basketOneToken);
        vm.serializeAddress(objectKey, "basketTwoToken", basketTwoToken);
        vm.serializeAddress(objectKey, "deployer", deployer);
        vm.serializeAddress(objectKey, "safeSingleton", address(singleton));
        vm.serializeAddress(objectKey, "safeFactory", address(factory));
        vm.serializeAddress(objectKey, "pmSafe", address(pmSafe));
        vm.serializeAddress(objectKey, "pmTokenA", WETH_BASE);
        string memory updated = vm.serializeAddress(objectKey, "pmTokenB", DAI_BASE);

        vm.writeJson(updated, "deployments/local.json");
        console.log("deployments/local.json extended with PM E2E fixture addresses");
    }
}
