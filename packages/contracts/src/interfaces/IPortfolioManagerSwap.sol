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
    /// @dev This trade would move the pair's spot price by more than maxDeviationBps in one
    ///      step (ADR-0016), regardless of where the pair started. spotPriceWad is the rejected
    ///      post-trade spot price, not the pre-trade one.
    error PortfolioManagerSwapExcessivePriceDeviation(uint256 spotPriceWad, uint256 maxDeviationBps);
    /// @dev The validator must attest this order before PM can quote or execute it.
    error PortfolioManagerSwapBuildParametersNotAttested(bytes32 strategyHash);
}
