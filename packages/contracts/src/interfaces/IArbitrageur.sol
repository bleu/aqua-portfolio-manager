// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {IUniswapV4PoolManager, IUnlockCallback} from "./IUniswapV4PoolManager.sol";

/// @title IArbitrageur
/// @notice Errors, events, and the full external surface of `Arbitrageur.sol`, exposed
///         separately for tooling and off-chain callers -- same convention as
///         `IBasketScopeGuard.sol`/`IPortfolioManagerStrategyValidator.sol`. `IUnlockCallback`
///         is inherited here rather than declared separately on the implementation contract,
///         since implementing `IArbitrageur` already guarantees `unlockCallback` exists.
interface IArbitrageur is IUnlockCallback {
    /// @dev Threaded through `unlockCallback` as the PoolManager's opaque `data`, since the
    ///      callback's own signature is fixed by `IUnlockCallback`. `fyndTarget`/`fyndSpender`
    ///      are kept separate since an aggregator's calldata may target one contract while a
    ///      different one (e.g. a Permit2-style allowance holder) needs the approval.
    struct FlashArbParams {
        ISwapVM.Order order;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minCurveAmountOut;
        address fyndTarget;
        address fyndSpender;
        bytes fyndCalldata;
        uint40 deadline;
    }

    event FlashArbitrageExecuted(
        bytes32 indexed orderHash,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 curveAmountOut,
        uint256 repaid,
        uint256 profit
    );
    event Swept(address indexed token, uint256 amount, address indexed to);

    error ArbitrageurUnauthorizedFlashLoanCallback(address caller);
    error ArbitrageurFyndCallFailed(bytes reason);
    error ArbitrageurInsufficientRepayment(uint256 owed, uint256 actual);

    /// @notice The SwapVM router this contract takes against.
    function ROUTER() external view returns (ISwapVM);

    /// @notice The Uniswap V4 PoolManager `executeFlashArbitrage` borrows from.
    function POOL_MANAGER() external view returns (IUniswapV4PoolManager);

    /// @notice Simulates an exact-in trade against `order` without moving any tokens.
    function quoteExactIn(ISwapVM.Order calldata order, address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);

    /// @notice Executes one real exact-in trade against `order`, borrowing `amountIn` from the
    ///         PoolManager and repaying it within the same transaction.
    function executeFlashArbitrage(FlashArbParams calldata params) external;

    /// @notice Recovers any token balance left on this contract, including flash-arbitrage
    ///         profit (there's no separate profit-forwarding step in that path).
    function sweep(address token, uint256 amount, address to) external;
}
