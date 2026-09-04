// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {BasketScopeGuard} from "../src/BasketScopeGuard.sol";
import {PoCRouter} from "../src/PoCRouter.sol";

/// @notice Deploys this repo's contracts against whichever RPC it's pointed at, installs the
/// Guard on the Safe, and writes their addresses to deployments/local.json so E2E tests
/// (test/BasketScopeGuardE2E.t.sol) can connect to these exact deployed instances instead of
/// deploying their own.
///
/// Meant for the docker-compose forked-Anvil environment (see ../../../docker-compose.yml):
/// on a real Base fork, `AQUA_ADDRESS` defaults to Aqua's real deployed registry
/// (`lib/aqua/README.md`'s deployment table — same address on every supported chain,
/// including Base) rather than deploying a fresh one, so what gets tested here is our
/// contracts against real protocol state, not a clean-room chain.
///
/// The Guard's example basket config (WETH in basket 1, a synthetic placeholder in basket 2)
/// and the PM trusted-strategy hash are placeholders — there is no real Portfolio Manager
/// strategy to trust yet, that's M2/M3 implementation work (BLEUDEV-258 and its children).
/// This script's job is proving the fork -> deploy -> test pipeline works end to end against
/// real Aqua state, not shipping final parameters.
contract Deploy is Script {
    /// @dev Aqua's real registry address — deterministic, same on every supported chain
    /// (Ethereum, Base, Optimism, Arbitrum, ... — see lib/aqua/README.md's deployment table).
    address internal constant AQUA_MAINNET = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;

    /// @dev WETH predeploy address, standard across every OP-stack chain (Base included).
    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;

    /// @dev Not a real token — ship() never transfers tokens at ship time (confirmed against
    /// Aqua.sol directly), so a synthetic address is fine as a second basket for this
    /// environment's placeholder config. Real group membership is M2/M3 scope.
    address internal constant SYNTHETIC_TOKEN_B = 0x000000000000000000000000000000000000b0b0;

    /// @dev Anvil's well-known default account #0 private key — this environment's deployer
    /// AND sole Safe owner. Test-only, never a real key. Overridable via env for anyone running
    /// this against a real deployer key, but the default matches docker-compose.yml's
    /// hardcoded `deploy` service key so setGuard's self-signature lines up out of the box.
    uint256 internal constant DEFAULT_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /// @dev Placeholder PM strategy hash — no real PM strategy exists yet. Fixed (not derived
    /// from a real `strategy` payload) so the E2E test can independently reproduce it to
    /// exercise the Guard's PM-exemption rule.
    bytes32 internal constant PM_STRATEGY_HASH = keccak256("placeholder-pm-strategy");

    function run() external {
        address aqua = vm.envOr("AQUA_ADDRESS", AQUA_MAINNET);
        address weth = vm.envOr("WETH_ADDRESS", WETH_BASE);
        uint256 deployerPk = vm.envOr("DEPLOYER_PRIVATE_KEY", DEFAULT_DEPLOYER_KEY);
        address deployer = vm.addr(deployerPk);

        vm.startBroadcast(deployerPk);

        // Own independent router (ADR-0010), pointed at the real Aqua registry.
        PoCRouter router = new PoCRouter(aqua, weth, deployer, "AquaPortfolioManager", "1");
        console.log("PoCRouter deployed at", address(router));

        // A fresh Safe (ADR-0002/ADR-0011) — the dedicated maker wallet convention — owned
        // solely by the deployer for this environment.
        Safe singleton = new Safe();
        SafeProxyFactory factory = new SafeProxyFactory();
        address[] memory owners = new address[](1);
        owners[0] = deployer;
        bytes memory setupData = abi.encodeWithSelector(
            Safe.setup.selector, owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))
        );
        Safe safe = Safe(payable(address(factory.createProxyWithNonce(address(singleton), setupData, 0))));
        console.log("Safe deployed at", address(safe));

        // Placeholder basket config: WETH in basket 1, a synthetic token in basket 2.
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = SYNTHETIC_TOKEN_B;
        uint256[] memory basketIds = new uint256[](2);
        basketIds[0] = 1;
        basketIds[1] = 2;
        BasketScopeGuard guard = new BasketScopeGuard(aqua, address(safe), PM_STRATEGY_HASH, tokens, basketIds);
        console.log("BasketScopeGuard deployed at", address(guard));

        // Install the Guard on the Safe for real, so the E2E test exercises the actual
        // enforced state, not just a deployed-but-inert Guard contract.
        bytes memory setGuardData = abi.encodeWithSignature("setGuard(address)", address(guard));
        bytes32 txHash = safe.getTransactionHash(
            address(safe), 0, setGuardData, Enum.Operation.Call, 0, 0, 0, address(0), address(0), safe.nonce()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPk, txHash);
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
            abi.encodePacked(r, s, v)
        );
        require(guardInstalled, "setGuard failed");
        console.log("Guard installed on Safe");

        // Attest onboarding is clean. In a real onboarding flow this only happens after
        // actually running an off-chain onboarding pre-existing-strategy check (BLEUDEV-321)
        // against this Safe's real Shipped-event history and confirming no violation. Here it's
        // auto-attested: this is a fresh Safe on a fresh
        // fork with no prior activity, so there is nothing for that check to find — but the
        // attestation call itself is real and signed, exactly as it would be in production,
        // so this still exercises the actual gate PM's strategy ships through.
        bytes memory attestData = abi.encodeWithSignature("attestOnboardingClean()");
        bytes32 attestTxHash = safe.getTransactionHash(
            address(guard), 0, attestData, Enum.Operation.Call, 0, 0, 0, address(0), address(0), safe.nonce()
        );
        (uint8 av, bytes32 ar, bytes32 as_) = vm.sign(deployerPk, attestTxHash);
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
            abi.encodePacked(ar, as_, av)
        );
        require(attested, "attestOnboardingClean failed");
        console.log("Onboarding attested");

        vm.stopBroadcast();

        string memory json = string.concat(
            "{",
            '"aqua":"',
            vm.toString(aqua),
            '",',
            '"router":"',
            vm.toString(address(router)),
            '",',
            '"safe":"',
            vm.toString(address(safe)),
            '",',
            '"guard":"',
            vm.toString(address(guard)),
            '",',
            '"pmStrategyHash":"',
            vm.toString(PM_STRATEGY_HASH),
            '",',
            '"basketOneToken":"',
            vm.toString(weth),
            '",',
            '"basketTwoToken":"',
            vm.toString(SYNTHETIC_TOKEN_B),
            '"',
            "}"
        );
        vm.writeJson(json, "deployments/local.json");
        console.log("Deployment manifest written to deployments/local.json");
    }
}
