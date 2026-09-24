// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @dev `Currency` is `address` under the hood (Solidity user-defined value types encode as their
///      underlying type), so this is ABI-compatible with the real PoolManager's own `Currency`
///      without pulling in v4-core as a dependency -- same reasoning as `AggregatorV3Interface.sol`.
type Currency is address;

/// @title IUnlockCallback — Uniswap V4's PoolManager unlock callback interface
/// @notice Re-declared locally rather than pulled in via a `lib/` submodule, same reasoning as
///         `AggregatorV3Interface.sol`: this is the whole surface `Arbitrageur` needs, matching
///         the real `IUnlockCallback` in `Uniswap/v4-core` exactly.
interface IUnlockCallback {
    /// @dev Called by the PoolManager synchronously, inside its own `unlock` execution -- every
    ///      currency `take`n during the call must be fully repaid (`sync` then transferred then
    ///      `settle`d) before this returns, or the whole `unlock` call reverts with
    ///      `CurrencyNotSettled`.
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

/// @title IUniswapV4PoolManager — the subset of Uniswap V4's PoolManager needed for flash loans
/// @notice Same canonical address (`0x498581fF718922c3f8e6A244956aF099B2652b2b`) on every EVM
///         chain Uniswap V4 is deployed to, Base included. V4 charges no flash-loan fee at all --
///         unlike Balancer's Vault, this isn't a configurable rate that could change, it's a
///         structural property of the unlock/take/settle accounting model (a `take`n amount is
///         just a negative balance delta that `settle` must zero out, nothing more).
interface IUniswapV4PoolManager {
    /// @notice Unlocks the manager and invokes `IUnlockCallback(msg.sender).unlockCallback(data)`.
    function unlock(bytes calldata data) external returns (bytes memory);

    /// @notice Transfers `amount` of `currency` out of the manager to `to`, recording a debt
    ///         against the caller that `settle` must repay before `unlock` returns.
    function take(Currency currency, address to, uint256 amount) external;

    /// @notice Snapshots the manager's own balance of `currency` so a later `settle()` can
    ///         compute how much was actually paid in. Must be called before transferring the
    ///         repayment to the manager, not after.
    function sync(Currency currency) external;

    /// @notice Reconciles the manager's balance of whatever currency `sync` last snapshotted
    ///         against what's actually been transferred in, zeroing out the caller's debt.
    function settle() external payable returns (uint256 paid);
}
