// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Script, console} from "forge-std/Script.sol";
import {Arbitrageur} from "../src/Arbitrageur.sol";

/// @notice Deploys the real Arbitrageur executor against this deployment's own Router and Base's
///         real Uniswap V4 PoolManager (used only as a zero-fee flash-borrow source for
///         `tokenIn` -- see Arbitrageur.sol's own doc comment; the arbitrage trade itself is
///         against the PM Router, never against a V4 pool).
contract DeployArbitrageur is Script {
    // The current PortfolioManagerRouter (packages/contracts/script/RedeployValidatorAndRouter.s.sol's
    // own 2026-10-26 run) -- the previous constant here pointed at a stale router address that
    // predated even the last router redeploy, so any trade this contract attempted would have
    // targeted a strategy registry nothing is actually shipped under. ROUTER is immutable once
    // deployed (Arbitrageur.sol), so a router change always means a fresh deployment, never a
    // config update to the existing contract.
    address internal constant ROUTER = 0x42A61d818BA014Baa78E6658a69930f4BA7465dC;
    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;

    function run() external returns (Arbitrageur arbitrageur) {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);

        vm.startBroadcast(ownerKey);
        arbitrageur = new Arbitrageur(ROUTER, POOL_MANAGER, owner);
        vm.stopBroadcast();

        console.log("owner:", owner);
        console.log("Arbitrageur:", address(arbitrageur));
    }
}
