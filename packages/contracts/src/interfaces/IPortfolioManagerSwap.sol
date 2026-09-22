// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title IPortfolioManagerSwap
/// @notice Errors for the internal PM instruction, exposed separately for tooling.
interface IPortfolioManagerSwap {
    error PortfolioManagerSwapTokenNotDeclared(address token);
    error PortfolioManagerSwapRecomputeDetected();
    /// @dev PM prices only cross-group swaps.
    error PortfolioManagerSwapSameGroupSwap(uint256 groupIndex);
    /// @dev The output token lacks sufficient native units, even if its group has enough aggregate value.
    error PortfolioManagerSwapInsufficientMemberBalance(address token, uint256 requested, uint256 available);
    /// @dev The pair's pre-trade spot price exceeds the deviation limit.
    ///      Corrective trades also fail until external action restores the pair within tolerance.
    error PortfolioManagerSwapExcessivePriceDeviation(uint256 spotPriceWad, uint256 maxDeviationBps);
    /// @dev The validator must attest this order before PM can quote or execute it.
    error PortfolioManagerSwapBuildParametersNotAttested(bytes32 strategyHash);
}
