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
    address internal constant ROUTER = 0x02a11927B0a1c701FEB589Ca86886F4ae1F85f02;
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
