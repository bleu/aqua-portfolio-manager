// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Test} from "forge-std/Test.sol";
import {Aqua} from "aqua/Aqua.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";

/// @title AquaE2EBase
/// @notice Forks Base's Aqua registry and deploys Safe infrastructure for each fixture.
/// @dev Defaults to a pinned snapshot with fresh feeds. Time-dependent tests use vm.warp.
///      Override BASE_RPC_URL or BASE_RPC_BLOCK as needed. Block zero selects live state.
abstract contract AquaE2EBase is Test {
    string private constant DEFAULT_BASE_RPC_URL = "https://mainnet.base.org";

    /// @dev Pinned Base snapshot with fresh oracle feeds. Update after successful Live Base checks.
    uint256 internal constant DEFAULT_BASE_RPC_BLOCK = 51_609_641;

    /// @dev Aqua registry address on Base.
    address internal constant AQUA_MAINNET = 0x499943E74FB0cE105688beeE8Ef2ABec5D936d31;

    /// @dev Chainlink's L2 sequencer-uptime feed for Base -- https://docs.chain.link/data-feeds/l2-sequencer-feeds
    address internal constant SEQUENCER_UPTIME_FEED_MAINNET = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    /// @dev Public test-only key. Owns fixture Safes and permits pre-approved-hash signatures.
    uint256 internal constant DEFAULT_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    Aqua internal aqua;
    address internal deployer;
    Safe internal safeSingleton;
    SafeProxyFactory internal safeFactory;

    function setUp() public virtual {
        string memory rpcUrl = vm.envOr("BASE_RPC_URL", DEFAULT_BASE_RPC_URL);
        uint256 pinnedBlock = vm.envOr("BASE_RPC_BLOCK", DEFAULT_BASE_RPC_BLOCK);
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

    /// @dev Deploy a threshold-one Safe owned by deployer. Use a distinct saltNonce per fixture.
    function _newSafe(uint256 saltNonce) internal returns (Safe) {
        address[] memory owners = new address[](1);
        owners[0] = deployer;
        bytes memory setupData = abi.encodeWithSelector(
            Safe.setup.selector, owners, 1, address(0), "", address(0), address(0), 0, payable(address(0))
        );
        return Safe(payable(address(safeFactory.createProxyWithNonce(address(safeSingleton), setupData, saltNonce))));
    }

    /// @dev Safe accepts v == 1 when the executor is the owner encoded in r. Callers prank as deployer.
    function _selfApprovedSignature() internal view returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(deployer))), bytes32(0), uint8(1));
    }
}
