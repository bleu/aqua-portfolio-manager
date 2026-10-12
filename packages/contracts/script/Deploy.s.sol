// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Script, console} from "forge-std/Script.sol";
import {PortfolioManagerRouter} from "../src/PortfolioManagerRouter.sol";
import {PortfolioManagerStrategyValidator} from "../src/PortfolioManagerStrategyValidator.sol";
import {PortfolioManagerTokenRegistry} from "../src/utils/PortfolioManagerTokenRegistry.sol";
import {PortfolioManagerFeedRegistry} from "../src/utils/PortfolioManagerFeedRegistry.sol";

/// @notice Deploys the reusable Portfolio Manager protocol pieces to a live chain: the strategy
///         validator, the router, and the token/feed registries (BLEUDEV-412/ADR-0018). Reuses
///         the chain's existing Aqua registry and WETH predeploy rather than deploying fresh ones.
///         Does not touch Safe infrastructure, MultiSendCallOnly, or BasketScopeGuard -- those are
///         per-strategy setup (the Guard's constructor binds it to one strategy's hash, so it
///         can't exist before a basket is chosen) done in a follow-up.
/// @dev Pre-registers every verified Chainlink push feed on Base mainnet (packages/addresses/
///      base-mainnet-feeds.json) into both registries, so a strategy builder never needs to
///      register a feed itself -- only the owner-gated feed registry step this unlocks. That file
///      is deliberately separate from base-mainnet.json's own curated token list (ADR-0014's
///      narrower arbitrageur allow-list) -- see its own top comment.
contract Deploy is Script {
    function run()
        external
        returns (
            PortfolioManagerRouter router,
            PortfolioManagerStrategyValidator validator,
            PortfolioManagerTokenRegistry tokenRegistry,
            PortfolioManagerFeedRegistry feedRegistry
        )
    {
        // Base mainnet addresses live in packages/addresses/base-mainnet.json, shared with the
        // TypeScript side (packages/addresses/src/index.ts) -- read live, nothing to regenerate.
        // Run this script with `FOUNDRY_PROFILE=deploy forge script ...`: reading outside this
        // project's own root needs foundry.toml's [profile.deploy] fs_permissions.
        string memory addresses = vm.readFile("../addresses/base-mainnet.json");
        address aqua = vm.parseJsonAddress(addresses, ".aqua");
        address weth = vm.parseJsonAddress(addresses, ".tokens.WETH.address");
        address sequencerUptimeFeed = vm.parseJsonAddress(addresses, ".sequencerUptimeFeed");

        // Every verified Chainlink push feed on Base, read separately from base-mainnet.json --
        // see base-mainnet-feeds.json's own top comment for why these two files stay apart.
        string memory feedsJson = vm.readFile("../addresses/base-mainnet-feeds.json");
        uint256 feedCount = vm.parseJsonUint(feedsJson, ".count");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        tokenRegistry = new PortfolioManagerTokenRegistry();
        // Owned by the deployer for now -- transfer ownership to a deployed TimelockController
        // before relying on this in production (ADR-0018: a feed index carries a safety claim,
        // so adding one should go through a public review delay).
        feedRegistry = new PortfolioManagerFeedRegistry(deployer);

        for (uint256 i = 0; i < feedCount; i++) {
            string memory entry = string.concat(".feeds[", vm.toString(i), "]");
            address token = vm.parseJsonAddress(feedsJson, string.concat(entry, ".tokenAddress"));
            address feed = vm.parseJsonAddress(feedsJson, string.concat(entry, ".feedProxy"));
            uint32 maxStaleness = uint32(vm.parseJsonUint(feedsJson, string.concat(entry, ".heartbeatSeconds")));
            tokenRegistry.register(token);
            feedRegistry.register(feed, maxStaleness);
        }

        validator =
            new PortfolioManagerStrategyValidator(sequencerUptimeFeed, address(tokenRegistry), address(feedRegistry));
        router = new PortfolioManagerRouter(
            aqua,
            weth,
            deployer,
            "AquaPortfolioManager",
            "1",
            address(validator),
            sequencerUptimeFeed,
            address(tokenRegistry),
            address(feedRegistry)
        );

        vm.stopBroadcast();

        console.log("deployer / router owner / feed registry owner:", deployer);
        console.log("PortfolioManagerTokenRegistry:", address(tokenRegistry));
        console.log("PortfolioManagerFeedRegistry:", address(feedRegistry));
        console.log("PortfolioManagerStrategyValidator:", address(validator));
        console.log("PortfolioManagerRouter:", address(router));
        console.log("Tokens/feeds pre-registered from base-mainnet-feeds.json:", feedCount);
    }
}
