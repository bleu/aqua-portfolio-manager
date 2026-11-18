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
///      and two different configurations can never collide into one. `deploy` is idempotent:
///      calling it twice with identical arguments (from this factory or, after a front-run, from
///      anyone else) returns the same address both times instead of reverting the second time --
///      see `GuardAlreadyDeployed`'s own doc comment for why a plain CREATE2-occupied revert isn't
///      good enough here.
contract BasketScopeGuardFactory {
    event GuardDeployed(
        address indexed guard, address indexed safe, bytes32 indexed trustedPmStrategyHash, address aqua
    );

    /// @dev BLEUDEV-451: a front-runner who deploys to the same CREATE2 address first (with the
    ///      identical configuration -- the salt is the hash of every constructor argument, so
    ///      nothing else can land there) used to make the real owner's own `deploy()` step revert,
    ///      breaking an atomic "deploy guard" + "Safe.setGuard(predicted)" batch. Emitted instead
    ///      of `GuardDeployed` on that path, since nothing was actually deployed by this call.
    event GuardAlreadyDeployed(
        address indexed guard, address indexed safe, bytes32 indexed trustedPmStrategyHash, address aqua
    );

    /// @notice Deploys a new BasketScopeGuard for the given configuration, or returns the already-
    ///         deployed one at that address if someone (anyone, with the identical configuration)
    ///         already did -- see `GuardAlreadyDeployed`'s own doc comment for why this matters.
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
        guard = _computeAddress(salt, aqua, safe_, trustedPmStrategyHash, trustedPmRouter, tokens, basketIds);
        if (guard.code.length != 0) {
            emit GuardAlreadyDeployed(guard, safe_, trustedPmStrategyHash, aqua);
            return guard;
        }

        address deployed = address(
            new BasketScopeGuard{salt: salt}(aqua, safe_, trustedPmStrategyHash, trustedPmRouter, tokens, basketIds)
        );
        assert(deployed == guard);
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
        return _computeAddress(salt, aqua, safe_, trustedPmStrategyHash, trustedPmRouter, tokens, basketIds);
    }

    function _computeAddress(
        bytes32 salt,
        address aqua,
        address safe_,
        bytes32 trustedPmStrategyHash,
        address trustedPmRouter,
        address[] calldata tokens,
        uint256[] calldata basketIds
    ) private view returns (address) {
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
