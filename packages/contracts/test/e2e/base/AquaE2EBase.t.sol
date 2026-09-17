// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Aqua} from "aqua/Aqua.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

/// @title AquaE2EBase — shared real-chain fixture every E2E test forks and deploys against
/// @notice Forks Base directly (`vm.createSelectFork`) and deploys the pieces every E2E fixture
///         needs regardless of what it's actually testing: the real Aqua registry, a deployer
///         EOA, and a fresh Safe singleton + factory to spin up dedicated maker wallets from
///         (ADR-0002). No external Anvil, no deploy script, no `deployments/local.json` -- the
///         whole fixture lives in the test run itself (Foundry Book: tests should be
///         self-contained and reproducible via `vm.createSelectFork`, not an external deployment
///         pipeline).
/// @dev No fixed fork block *by default*: every concrete E2E fixture reads live feed/balance
///      state and computes its own expectations dynamically, and this whole suite is meant to
///      exercise *current* real protocol state, not a frozen snapshot. `BASE_RPC_URL` is the
///      escape hatch for avoiding public-endpoint rate-limiting.
///      `BASE_RPC_BLOCK` is a narrower escape hatch on top of that: CI resolves and caches a
///      recent block number once per hour (see `.github/workflows/test.yml`) so repeated runs
///      within that hour reuse Foundry's own on-disk RPC cache instead of re-fetching every
///      storage slot from scratch -- still "current" to within an hour, not a permanent snapshot.
///      Unset (0) locally, so a plain `forge test` still forks genuinely live state.
abstract contract AquaE2EBase is Test {
    string private constant DEFAULT_BASE_RPC_URL = "https://mainnet.base.org";

    /// @dev Aqua's real registry address — deterministic, same on every supported chain
    ///      (Ethereum, Base, Optimism, Arbitrum, ... — see `lib/aqua/README.md`'s deployment
    ///      table).
    address internal constant AQUA_MAINNET = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;

    /// @dev A fixed, well-known test-only private key — never a real key. Every fixture's Safe
    ///      is owned solely by this address, purely so `_selfApprovedSignature`'s `v == 1`
    ///      pre-approved-hash trick works without needing a real ECDSA signature anywhere.
    uint256 internal constant DEFAULT_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    Aqua internal aqua;
    address internal deployer;
    Safe internal safeSingleton;
    SafeProxyFactory internal safeFactory;

    function setUp() public virtual {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", DEFAULT_BASE_RPC_URL);
        uint256 pinnedBlock = vm.envOr("BASE_RPC_BLOCK", uint256(0));
        if (pinnedBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, pinnedBlock);
        }

        aqua = Aqua(AQUA_MAINNET);
        deployer = vm.addr(DEFAULT_DEPLOYER_KEY);
        safeSingleton = new Safe();
        safeFactory = new SafeProxyFactory();
    }

    /// @dev A fresh Safe proxy owned solely by `deployer`, threshold 1. `saltNonce` must be
    ///      distinct per fixture within the same test run (each concrete E2E family picks its
    ///      own) so their proxy addresses never collide.
    function _newSafe(uint256 saltNonce) internal returns (Safe) {
        address[] memory owners = new address[](1);
        owners[0] = deployer;
        bytes memory setupData = abi.encodeWithSelector(
            Safe.setup.selector, owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))
        );
        return Safe(payable(address(safeFactory.createProxyWithNonce(address(safeSingleton), setupData, saltNonce))));
    }

    /// @dev Safe's `checkNSignatures` treats `v == 1` as a pre-approved hash (owner address
    ///      packed into `r`) and passes immediately when the executor IS that owner -- no real
    ///      ECDSA signature needed. `deployer` is every fixture's Safe's sole owner, and every
    ///      caller pranks as `deployer` first.
    function _selfApprovedSignature() internal view returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(deployer))), bytes32(0), uint8(1));
    }
}
