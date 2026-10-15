// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title IBasketScopeGuard
/// @notice PM-specific Guard interface. Safe interfaces declare the transaction and module hooks.
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

    /// @notice The PM router app address a `ship()` call must target to use the cross-basket
    ///         exemption. The strategy hash alone does not identify which app will run it.
    function TRUSTED_PM_ROUTER() external view returns (address);

    /// @notice `basketOf[token] == 0` means the token is outside the declared universe.
    function basketOf(address token) external view returns (uint256);
}
