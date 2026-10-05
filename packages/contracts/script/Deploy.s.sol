// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Script, console} from "forge-std/Script.sol";
import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";

/// @notice Deploys the reusable Portfolio Manager protocol pieces to a live chain: the strategy
///         validator and the router. Reuses the chain's existing Aqua registry and WETH predeploy
///         rather than deploying fresh ones. Does not touch Safe infrastructure, MultiSendCallOnly,
///         or BasketScopeGuard -- those are per-strategy setup (the Guard's constructor binds it to
///         one strategy's hash, so it can't exist before a basket is chosen) done in a follow-up.
contract Deploy is Script {
    function run() external returns (PortfolioManagerRouter router, PortfolioManagerStrategyValidator validator) {
        // Base mainnet addresses live in packages/addresses/base-mainnet.json, shared with the
        // TypeScript side (packages/addresses/src/index.ts) -- read live, nothing to regenerate.
        string memory addresses = vm.readFile("../addresses/base-mainnet.json");
        address aqua = vm.parseJsonAddress(addresses, ".aqua");
        address weth = vm.parseJsonAddress(addresses, ".tokens.WETH.address");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        validator = new PortfolioManagerStrategyValidator();
        router = new PortfolioManagerRouter(aqua, weth, deployer, "AquaPortfolioManager", "1", address(validator));

        vm.stopBroadcast();

        console.log("deployer / router owner:", deployer);
        console.log("PortfolioManagerStrategyValidator:", address(validator));
        console.log("PortfolioManagerRouter:", address(router));
    }
}
