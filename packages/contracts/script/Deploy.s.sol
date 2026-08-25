// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {BasketScopeGuard} from "../src/BasketScopeGuard.sol";
import {PoCRouter} from "../src/PoCRouter.sol";

/// @notice Deploys this repo's contracts against whichever RPC it's pointed at.
///
/// Meant for the docker-compose forked-Anvil environment (see ../../../docker-compose.yml):
/// on a real Base fork, `AQUA_ADDRESS` defaults to Aqua's real deployed registry
/// (`lib/aqua/README.md`'s deployment table — same address on every supported chain,
/// including Base) rather than deploying a fresh one, so what gets tested here is our
/// contracts against real protocol state, not a clean-room chain.
///
/// The Guard's example basket config (WETH-only, basket 1) and the PM trusted-strategy hash
/// (zero) are placeholders — there is no real Portfolio Manager strategy to trust yet, that's
/// M2/M3 implementation work (BLEUDEV-258 and its children). This script's job is proving the
/// fork -> deploy -> test pipeline works end to end against real Aqua state, not shipping
/// final parameters.
contract Deploy is Script {
    /// @dev Aqua's real registry address — deterministic, same on every supported chain
    /// (Ethereum, Base, Optimism, Arbitrum, ... — see lib/aqua/README.md's deployment table).
    address internal constant AQUA_MAINNET = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;

    /// @dev WETH predeploy address, standard across every OP-stack chain (Base included).
    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;

    function run() external {
        address aqua = vm.envOr("AQUA_ADDRESS", AQUA_MAINNET);
        address weth = vm.envOr("WETH_ADDRESS", WETH_BASE);

        vm.startBroadcast();

        address deployer = msg.sender;

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

        // Placeholder basket config: WETH in basket 1, no trusted PM strategy yet.
        address[] memory tokens = new address[](1);
        tokens[0] = weth;
        uint256[] memory basketIds = new uint256[](1);
        basketIds[0] = 1;
        BasketScopeGuard guard = new BasketScopeGuard(aqua, bytes32(0), tokens, basketIds);
        console.log("BasketScopeGuard deployed at", address(guard));

        vm.stopBroadcast();
    }
}
