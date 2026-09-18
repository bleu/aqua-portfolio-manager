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

    /// @notice The Aqua core contract this guard watches `ship()` calls to.
    function AQUA() external view returns (address);

    /// @notice The Safe this guard is installed on.
    function SAFE() external view returns (address);

    /// @notice The exact `keccak256(strategy)` of this LP's already-parameterized PM strategy,
    ///         computed off-chain before this guard is deployed.
    function TRUSTED_PM_STRATEGY_HASH() external view returns (bytes32);

    /// @notice `basketOf[token] == 0` means the token is outside the declared universe.
    function basketOf(address token) external view returns (uint256);
}
