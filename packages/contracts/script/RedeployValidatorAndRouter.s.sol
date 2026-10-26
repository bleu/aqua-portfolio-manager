// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Script, console} from "forge-std/Script.sol";
import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";

/// @notice Redeploys only PortfolioManagerStrategyValidator and PortfolioManagerRouter, reusing
///         the token/feed registries an earlier Deploy.s.sol run already deployed and populated.
/// @dev Both contracts inline OracleAdapter's requireSequencerUp at compile time, so a bug fix
///      there (reading latestRoundData's startedAt from the wrong tuple position) needs a new
///      bytecode deployment of each, not a config change. The registries don't call
///      requireSequencerUp and are unaffected -- redeploying them would only add churn (losing
///      every already-registered token/feed index) with no safety benefit, so this script never
///      touches them. Any strategy already shipped against the OLD router stays tied to it and
///      keeps the old buggy check baked into its own bytecode permanently; this only affects
///      strategies shipped after switching the frontend/integrators to the new router address.
contract RedeployValidatorAndRouter is Script {
    function run() external returns (PortfolioManagerStrategyValidator validator, PortfolioManagerRouter router) {
        string memory addresses = vm.readFile("../addresses/base-mainnet.json");
        address aqua = vm.parseJsonAddress(addresses, ".aqua");
        address weth = vm.parseJsonAddress(addresses, ".tokens.WETH.address");
        address sequencerUptimeFeed = vm.parseJsonAddress(addresses, ".sequencerUptimeFeed");

        // The already-deployed, already-populated registries from the original Deploy.s.sol run --
        // not read from a file, since nothing in this repo persists them outside the frontend's
        // own env vars (NEXT_PUBLIC_PM_TOKEN_REGISTRY_ADDRESS / NEXT_PUBLIC_PM_FEED_REGISTRY_ADDRESS).
        address tokenRegistry = vm.envAddress("TOKEN_REGISTRY_ADDRESS");
        address feedRegistry = vm.envAddress("FEED_REGISTRY_ADDRESS");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        validator = new PortfolioManagerStrategyValidator(sequencerUptimeFeed, tokenRegistry, feedRegistry);
        router = new PortfolioManagerRouter(
            aqua,
            weth,
            deployer,
            "AquaPortfolioManager",
            "1",
            address(validator),
            sequencerUptimeFeed,
            tokenRegistry,
            feedRegistry
        );

        vm.stopBroadcast();

        console.log("deployer / router owner:", deployer);
        console.log("Reused PortfolioManagerTokenRegistry:", tokenRegistry);
        console.log("Reused PortfolioManagerFeedRegistry:", feedRegistry);
        console.log("New PortfolioManagerStrategyValidator:", address(validator));
        console.log("New PortfolioManagerRouter:", address(router));
    }
}
