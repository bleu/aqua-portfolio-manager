// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";

/// @title IPortfolioManagerStrategyValidator
/// @notice Parameter checks and attestation for PM strategies.
interface IPortfolioManagerStrategyValidator {
    error PortfolioManagerStrategyValidatorNotAPortfolioManagerStrategy();
    error PortfolioManagerStrategyValidatorDeclaredTokenNotShipped(address token);
    error PortfolioManagerStrategyValidatorShippedTokenNotDeclared(address token);
    /// @dev The maker's group share exceeds the configured relative deviation before shipping.
    error PortfolioManagerStrategyValidatorExcessivePriceDeviation(
        uint256 groupIndex, uint256 actualShareWad, uint256 targetWeightWad
    );
    /// @dev Portfolio shares are undefined when the declared tokens have zero total value.
    error PortfolioManagerStrategyValidatorEmptyPortfolio();

    /// @dev Emitted on every successful attestation, including repeat calls.
    event BuildParametersAttested(bytes32 indexed strategyHash);

    /// @notice Requires matching token membership in the order and supplied list, in both directions.
    /// @dev The program must start with CURVE_OPCODE. This check does not read balances or prices.
    function requireUniverseMatches(ISwapVM.Order calldata order, address[] calldata tokens) external pure;

    /// @notice Requires each group's share to stay within maxDeviationBps of its target, relative to that target.
    /// @dev Zero disables the check. Reads the supplied maker's current balances.
    function requireBalancedWithinTolerance(ISwapVM.Order calldata order, address maker) external view;

    /// @notice Validates parameters and records attestation required by PM quotes and swaps.
    /// @dev Permissionless and idempotent. Does not bind a later ship() token array or guarantee future balances.
    function attestBuildParameters(ISwapVM.Order calldata order, address[] calldata tokens) external;

    /// @notice Whether `attestBuildParameters` has ever succeeded for this `strategyHash`
    ///         (`keccak256(abi.encode(order))` for Aqua-native orders).
    function buildParamsAttested(bytes32 strategyHash) external view returns (bool);
}
