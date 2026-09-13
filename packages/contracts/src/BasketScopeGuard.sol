// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {BaseGuard} from "safe-smart-account/contracts/examples/guards/BaseGuard.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {IAqua} from "aqua/interfaces/IAqua.sol";

/// @title BasketScopeGuard
/// @notice A Safe Transaction Guard (ADR-0011) installed on the LP's dedicated maker wallet.
///         Every outgoing `AQUA.ship(app, strategy, tokens, amounts)` call is inspected before
///         the Safe executes it: PM's own, exact strategy is allowed once onboarding has been
///         attested (see `attestOnboardingClean`) — it is the trusted mechanism meant to price
///         across groups; any other strategy must keep every token it declares inside a single
///         group, and every token must belong to *some* declared group.
/// @dev Trust is anchored to `keccak256(strategy)`, not to the router address passed as `app`.
///      A swapVM router is a general-purpose opcode dispatcher — the same router can run PM's
///      strategy and any other strategy built from the same opcode set, each with its own
///      `strategyHash`. Checking `app` alone would trust every strategy that happens to share
///      PM's router, not just PM itself (see ADR-0011).
///
///      Both the group-membership mapping and the trusted strategy hash are fixed at
///      construction, with no setter anywhere in this contract — neither can be loosened later
///      by whoever controls the Safe.
///
///      This Guard cannot see or undo `ship()` calls made before it was installed — a Solidity
///      contract has no way to scan historical event logs. `attestOnboardingClean` closes the
///      resulting gap not by detecting a pre-existing forbidden strategy automatically (not
///      possible on-chain), but by requiring the Safe to explicitly attest, via its own signed
///      transaction, that the off-chain onboarding pre-existing-strategy check
///      (BLEUDEV-321, `packages/onboarding-check`) has been run and came back clean. Until that
///      attestation happens, PM's own strategy cannot ship at all — closing the gap where
///      shipping PM was previously unconditional regardless of whether that check was ever run.
contract BasketScopeGuard is BaseGuard {
    /// @notice The Aqua core contract this guard watches `ship()` calls to.
    address public immutable AQUA;

    /// @notice The Safe this guard is installed on — the only address allowed to call
    ///         `attestOnboardingClean`.
    address public immutable SAFE;

    /// @notice The exact `keccak256(strategy)` of this LP's already-parameterized PM strategy,
    ///         computed off-chain before this guard is deployed.
    bytes32 public immutable TRUSTED_PM_STRATEGY_HASH;

    /// @notice `basketOf[token] == 0` means the token is outside the declared universe.
    mapping(address token => uint256 basketId) public basketOf;

    /// @notice Set once, via `attestOnboardingClean`, after the off-chain onboarding
    ///         pre-existing-strategy check has come back clean for this Safe. PM's own
    ///         strategy cannot ship until this is `true`.
    bool public onboardingAttested;

    error TokenBasketLengthMismatch();
    error BasketIdZeroReserved();
    error EmptyTokenList();
    error TokenNotInAnyBasket(address token);
    error CrossBasketStrategyForbidden(address tokenA, address tokenB);
    error OnboardingNotAttested();
    error OnlySafeCanAttest();
    error AlreadyAttested();

    event OnboardingAttested();

    constructor(
        address aqua,
        address safe_,
        bytes32 trustedPmStrategyHash,
        address[] memory tokens,
        uint256[] memory basketIds
    ) {
        if (tokens.length != basketIds.length) revert TokenBasketLengthMismatch();

        AQUA = aqua;
        SAFE = safe_;
        TRUSTED_PM_STRATEGY_HASH = trustedPmStrategyHash;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (basketIds[i] == 0) revert BasketIdZeroReserved();
            basketOf[tokens[i]] = basketIds[i];
        }
    }

    /// @notice Records that the off-chain onboarding pre-existing-strategy check (scanning
    ///         `Shipped` events for this Safe) has been run and came back clean. Callable only
    ///         by the Safe itself, via a normal signed Safe transaction — the same authority
    ///         required for `setGuard`. Irreversible once set (no un-attest path) and required
    ///         exactly once: PM's own strategy is immutable after `ship()`, so there is nothing
    ///         further to attest to after this Guard's one PM strategy has shipped.
    function attestOnboardingClean() external {
        if (msg.sender != SAFE) revert OnlySafeCanAttest();
        if (onboardingAttested) revert AlreadyAttested();
        onboardingAttested = true;
        emit OnboardingAttested();
    }

    /// @dev see ITransactionGuard/IModuleGuard
    function checkTransaction(
        address to,
        uint256, /* value */
        bytes memory data,
        Enum.Operation, /* operation */
        uint256, /* safeTxGas */
        uint256, /* baseGas */
        uint256, /* gasPrice */
        address, /* gasToken */
        address payable, /* refundReceiver */
        bytes memory, /* signatures */
        address /* msgSender */
    ) external view override {
        _check(to, data);
    }

    /// @dev see ITransactionGuard/IModuleGuard
    function checkAfterExecution(bytes32, bool) external override {}

    /// @dev see ITransactionGuard/IModuleGuard
    function checkModuleTransaction(
        address to,
        uint256, /* value */
        bytes memory data,
        Enum.Operation, /* operation */
        address /* module */
    )
        external
        view
        override
        returns (bytes32)
    {
        _check(to, data);
        return bytes32(0);
    }

    /// @dev see ITransactionGuard/IModuleGuard
    function checkAfterModuleExecution(bytes32, bool) external override {}

    /// @dev The actual check, shared by both the normal multisig path and the module path.
    ///      Reverts on a disallowed `ship()`; returns silently for everything else (any other
    ///      target, any other Aqua function, or PM's own trusted strategy).
    function _check(address to, bytes memory data) internal view {
        if (to != AQUA) return;
        if (data.length < 4 || _selector(data) != IAqua.ship.selector) return;

        (, bytes memory strategy, address[] memory tokens,) =
            abi.decode(_stripSelector(data), (address, bytes, address[], uint256[]));

        if (keccak256(strategy) == TRUSTED_PM_STRATEGY_HASH) {
            if (!onboardingAttested) revert OnboardingNotAttested();
            return;
        }

        if (tokens.length == 0) revert EmptyTokenList();
        uint256 basketId = basketOf[tokens[0]];
        if (basketId == 0) revert TokenNotInAnyBasket(tokens[0]);
        for (uint256 i = 1; i < tokens.length; i++) {
            uint256 tokenBasketId = basketOf[tokens[i]];
            if (tokenBasketId == 0) revert TokenNotInAnyBasket(tokens[i]);
            if (tokenBasketId != basketId) revert CrossBasketStrategyForbidden(tokens[0], tokens[i]);
        }
    }

    function _selector(bytes memory data) private pure returns (bytes4 sel) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sel := mload(add(data, 0x20))
        }
    }

    /// @dev Deliberately a plain byte-copy loop, not assembly — this guard runs far off the
    ///      hot path (only on `ship()`, never on a taker swap), so auditability wins over gas.
    function _stripSelector(bytes memory data) private pure returns (bytes memory out) {
        uint256 len = data.length - 4;
        out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            out[i] = data[i + 4];
        }
    }
}
