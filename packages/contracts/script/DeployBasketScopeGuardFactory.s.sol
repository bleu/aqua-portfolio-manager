// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Script, console} from "forge-std/Script.sol";
import {BasketScopeGuardFactory} from "../src/BasketScopeGuardFactory.sol";

/// @notice Deploys the one, reusable BasketScopeGuardFactory -- not a per-strategy deployment.
///         Every LP's own Guard is deployed later, per strategy, by calling this factory's own
///         `deploy()` (see docs/guides/fresh-wallet-setup.md and the ship wizard's own Guard step).
contract DeployBasketScopeGuardFactory is Script {
    function run() external returns (BasketScopeGuardFactory factory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        factory = new BasketScopeGuardFactory();
        vm.stopBroadcast();

        console.log("deployer:", deployer);
        console.log("BasketScopeGuardFactory:", address(factory));
    }
}
