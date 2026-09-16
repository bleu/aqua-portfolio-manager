// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title IBasketScopeGuard
/// @notice External interface for `BasketScopeGuard`'s own surface — its inherited
///         `checkTransaction`/`checkAfterExecution`/`checkModuleTransaction`/
///         `checkAfterModuleExecution` functions are already declared by Safe's own `BaseGuard`/
///         `Guard`/`IModuleGuard` interfaces, so they aren't redeclared here. See
///         `BasketScopeGuard` for the full rationale.
interface IBasketScopeGuard {
    error TokenBasketLengthMismatch();
    error BasketIdZeroReserved();
    error EmptyTokenList();
    error TokenNotInAnyBasket(address token);
    error CrossBasketStrategyForbidden(address tokenA, address tokenB);
    error OnboardingNotAttested();
    error OnlySafeCanAttest();
    error AlreadyAttested();

    event OnboardingAttested();

    /// @notice The Aqua core contract this guard watches `ship()` calls to.
    function AQUA() external view returns (address);

    /// @notice The Safe this guard is installed on — the only address allowed to call
    ///         `attestOnboardingClean`.
    function SAFE() external view returns (address);

    /// @notice The exact `keccak256(strategy)` of this LP's already-parameterized PM strategy,
    ///         computed off-chain before this guard is deployed.
    function TRUSTED_PM_STRATEGY_HASH() external view returns (bytes32);

    /// @notice `basketOf[token] == 0` means the token is outside the declared universe.
    function basketOf(address token) external view returns (uint256);

    /// @notice Set once, via `attestOnboardingClean`, after the off-chain onboarding
    ///         pre-existing-strategy check has come back clean for this Safe. PM's own
    ///         strategy cannot ship until this is `true`.
    function onboardingAttested() external view returns (bool);

    /// @notice Records that the off-chain onboarding pre-existing-strategy check (scanning
    ///         `Shipped` events for this Safe) has been run and came back clean. Callable only
    ///         by the Safe itself. Irreversible once set.
    function attestOnboardingClean() external;
}
