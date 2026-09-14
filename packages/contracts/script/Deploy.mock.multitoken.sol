// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

/// @notice Deploys the test-fixture wallet `PortfolioManagerMultiTokenBasketE2E.t.sol` trades
/// against — a real multi-token oracle-valued universe (ADR-0003/BLEUDEV-347): a "majors" group
/// {WETH, WBTC} and a "stables" group {DAI, USDT, USDC}, each priced through its own real
/// Chainlink feed on Base. Run separately, after Deploy.s.sol, only by whoever needs this suite —
/// mirrors Deploy.mock.sol's own pattern (reuses the real router/Safe infra, extends the same
/// manifest) but for a *third*, separate dedicated Safe (ADR-0002), since this fixture's token
/// count and group shape differ entirely from Deploy.mock.sol's single-group WETH/DAI pair.
///
/// No TokenMock, no mock feeds: every token and every price feed here is a real, live Base
/// mainnet contract — no mint-gated fake token. Funding happens at E2E test time, not here (see
/// `run()`'s own note on why `deal()` doesn't belong in a broadcast script).
contract DeployMockMultiToken is Script {
    address internal constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    /// @dev WBTC on Base — https://basescan.org/token/0x1cea84203673764244e05693e42e6ace62be9ba5
    address internal constant WBTC_BASE = 0x1ceA84203673764244E05693e42E6Ace62bE9BA5;
    /// @dev DAI on Base — https://basescan.org/token/0x50c5725949a6f0c72e6c4a641f24049a917db0cb
    address internal constant DAI_BASE = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    /// @dev USDT on Base — https://basescan.org/token/0xfde4c96c8593536e31f229ea8f37b2ada2699bb2
    address internal constant USDT_BASE = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    /// @dev USDC on Base — https://basescan.org/token/0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
    address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @dev Chainlink ETH/USD on Base — https://basescan.org/address/0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70
    address internal constant ETH_USD_FEED_BASE = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    /// @dev Chainlink BTC/USD on Base — https://basescan.org/address/0x64c911996d3c6ac71f9b455b1e8e7266bcbd848f
    address internal constant BTC_USD_FEED_BASE = 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F;
    /// @dev Chainlink DAI/USD on Base — https://basescan.org/address/0x591e79239a7d679378ec8c847e5038150364c78f
    address internal constant DAI_USD_FEED_BASE = 0x591e79239a7d679378eC8c847e5038150364C78F;
    /// @dev Chainlink USDT/USD on Base — https://basescan.org/address/0xf19d560eb8d2adf07bd6d13ed03e1d11215721f9
    address internal constant USDT_USD_FEED_BASE = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    /// @dev Chainlink USDC/USD on Base — https://basescan.org/address/0x7e860098f58bbfc8648a4311b374b1d669a2bc6b
    address internal constant USDC_USD_FEED_BASE = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;

    /// @dev The packed encoding's maxStaleness field is a uint16 (max ~18.2 hours) -- see
    ///      PortfolioManagerArgsBuilder.sol's MEMBER_ENTRY_SIZE note for why.
    uint256 internal constant DEFAULT_MAX_STALENESS = 12 hours;

    uint256 internal constant DEFAULT_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

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
        address pmStrategyFactory = vm.parseJsonAddress(existing, ".pmStrategyFactory");
        address multiSendCallOnly = vm.parseJsonAddress(existing, ".multiSendCallOnly");

        // Deploy.mock.sol's own fixture fields -- optional here, since this script only strictly
        // depends on Deploy.s.sol and may run before or after Deploy.mock.sol.
        bool hasSingleGroupFixture = vm.keyExists(existing, ".pmSafe");

        uint256 deployerPk = vm.envOr("DEPLOYER_PRIVATE_KEY", DEFAULT_DEPLOYER_KEY);

        vm.startBroadcast(deployerPk);

        // A third, separate dedicated maker wallet (ADR-0002) -- distinct from both Deploy.s.sol's
        // Guard-protected Safe and Deploy.mock.sol's single-group pmSafe, since this fixture's
        // universe (5 tokens, 2 groups) shares nothing with either.
        address[] memory owners = new address[](1);
        owners[0] = deployer;
        bytes memory setupData = abi.encodeWithSelector(
            Safe.setup.selector, owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))
        );
        Safe multiTokenSafe = Safe(
            payable(address(
                    factory.createProxyWithNonce(
                        address(singleton),
                        setupData,
                        2 // different salt nonce than Deploy.s.sol's (0) and Deploy.mock.sol's (1)
                    )
                ))
        );
        console.log("Multi-token PM Safe deployed at", address(multiTokenSafe));

        vm.stopBroadcast();

        // Deliberately NOT funded here: `deal()` only mutates a forge *script*'s own local
        // simulation state, not the live node it broadcasts against -- confirmed empirically
        // (the safe's real on-chain balance is 0 immediately after a deal()-only script like
        // this runs). Real funding happens inside PortfolioManagerMultiTokenBasketE2E.t.sol's
        // own `_shipOnly`, the same way PortfolioManagerE2EBase.t.sol's `_fundAndShip` already
        // (redundantly, but correctly) re-funds Deploy.mock.sol's pmSafe at test time.

        // Re-serializes every field Deploy.s.sol (and, if present, Deploy.mock.sol) already
        // wrote, plus this fixture's own -- vm.writeJson below overwrites the whole file, so any
        // field not explicitly re-added here is silently dropped from the manifest.
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
        vm.serializeAddress(objectKey, "pmStrategyFactory", pmStrategyFactory);
        vm.serializeAddress(objectKey, "multiSendCallOnly", multiSendCallOnly);

        if (hasSingleGroupFixture) {
            vm.serializeAddress(objectKey, "pmSafe", vm.parseJsonAddress(existing, ".pmSafe"));
            vm.serializeAddress(objectKey, "pmTokenA", vm.parseJsonAddress(existing, ".pmTokenA"));
            vm.serializeAddress(objectKey, "pmTokenB", vm.parseJsonAddress(existing, ".pmTokenB"));
            vm.serializeAddress(objectKey, "pmTokenAFeed", vm.parseJsonAddress(existing, ".pmTokenAFeed"));
            vm.serializeAddress(objectKey, "pmTokenBFeed", vm.parseJsonAddress(existing, ".pmTokenBFeed"));
            vm.serializeUint(objectKey, "pmMaxStaleness", vm.parseJsonUint(existing, ".pmMaxStaleness"));
        }

        vm.serializeAddress(objectKey, "multiTokenSafe", address(multiTokenSafe));
        vm.serializeAddress(objectKey, "multiTokenWeth", WETH_BASE);
        vm.serializeAddress(objectKey, "multiTokenWbtc", WBTC_BASE);
        vm.serializeAddress(objectKey, "multiTokenDai", DAI_BASE);
        vm.serializeAddress(objectKey, "multiTokenUsdt", USDT_BASE);
        vm.serializeAddress(objectKey, "multiTokenUsdc", USDC_BASE);
        vm.serializeAddress(objectKey, "multiTokenWethFeed", ETH_USD_FEED_BASE);
        vm.serializeAddress(objectKey, "multiTokenWbtcFeed", BTC_USD_FEED_BASE);
        vm.serializeAddress(objectKey, "multiTokenDaiFeed", DAI_USD_FEED_BASE);
        vm.serializeAddress(objectKey, "multiTokenUsdtFeed", USDT_USD_FEED_BASE);
        vm.serializeAddress(objectKey, "multiTokenUsdcFeed", USDC_USD_FEED_BASE);
        string memory updated = vm.serializeUint(objectKey, "multiTokenMaxStaleness", DEFAULT_MAX_STALENESS);

        vm.writeJson(updated, "deployments/local.json");
        console.log("deployments/local.json extended with multi-token PM E2E fixture addresses");
    }
}
