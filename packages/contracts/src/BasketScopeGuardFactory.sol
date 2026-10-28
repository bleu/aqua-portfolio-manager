// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {BasketScopeGuard} from "./BasketScopeGuard.sol";

/// @title BasketScopeGuardFactory
/// @notice Deploys a BasketScopeGuard at a CREATE2 address computable off-chain before deployment,
///         so a caller can batch "deploy the Guard" and "Safe.setGuard(that address)" into one
///         atomic transaction without needing the deployment to finish first and report back.
/// @dev The salt is the hash of the full constructor argument set, not a caller-supplied value --
///      the same (Safe, strategy, token/group mapping) tuple always lands at the same address,
///      and two different configurations can never collide into one. This also makes `deploy`
///      naturally idempotent: calling it twice with identical arguments reverts the second time
///      (CREATE2 cannot redeploy to an occupied address) exactly when there is nothing left to do,
///      which a caller can detect in advance with `computeAddress` instead of simulating first.
contract BasketScopeGuardFactory {
    event GuardDeployed(
        address indexed guard, address indexed safe, bytes32 indexed trustedPmStrategyHash, address aqua
    );

    /// @notice Deploys a new BasketScopeGuard for the given configuration.
    /// @return guard The deployed Guard's address -- always equal to `computeAddress`'s own
    ///         result for the same arguments, computed ahead of time.
    function deploy(
        address aqua,
        address safe_,
        bytes32 trustedPmStrategyHash,
        address trustedPmRouter,
        address[] calldata tokens,
        uint256[] calldata basketIds
    ) external returns (address guard) {
        bytes32 salt = _salt(aqua, safe_, trustedPmStrategyHash, trustedPmRouter, tokens, basketIds);
        guard = address(
            new BasketScopeGuard{salt: salt}(aqua, safe_, trustedPmStrategyHash, trustedPmRouter, tokens, basketIds)
        );
        emit GuardDeployed(guard, safe_, trustedPmStrategyHash, aqua);
    }

    /// @notice The address `deploy` will produce for the given configuration, before deploying it.
    /// @dev Mirrors this exactly off-chain (e.g. viem's `getContractAddress` with `opcode:
    ///      'CREATE2'`) to build `Safe.setGuard(address)` as a later step in the same batch as
    ///      the `deploy` call -- both this function and that off-chain computation must stay
    ///      byte-for-byte in sync with BasketScopeGuard's actual constructor and creation code;
    ///      a compiler or constructor-signature change on either side breaks the prediction.
    function computeAddress(
        address aqua,
        address safe_,
        bytes32 trustedPmStrategyHash,
        address trustedPmRouter,
        address[] calldata tokens,
        uint256[] calldata basketIds
    ) external view returns (address) {
        bytes32 salt = _salt(aqua, safe_, trustedPmStrategyHash, trustedPmRouter, tokens, basketIds);
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(BasketScopeGuard).creationCode,
                abi.encode(aqua, safe_, trustedPmStrategyHash, trustedPmRouter, tokens, basketIds)
            )
        );
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }

    function _salt(
        address aqua,
        address safe_,
        bytes32 trustedPmStrategyHash,
        address trustedPmRouter,
        address[] calldata tokens,
        uint256[] calldata basketIds
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(aqua, safe_, trustedPmStrategyHash, trustedPmRouter, tokens, basketIds));
    }
}
