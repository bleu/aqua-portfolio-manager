// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title PortfolioManagerFee
/// @notice DAO protocol fee rates and recipient for the PM instruction.
library PortfolioManagerFee {
    /// @dev DAO treasury address disclosed in 1IP-103.
    address internal constant DAO_TREASURY_ADDRESS = 0x7951c7ef839e26F63DA87a42C9a87986507f1c07;

    /// @dev Implements 1IP-103's approximate 0.1225% tier boundary with a 1e9 scale.
    uint32 internal constant TIER_THRESHOLD_BPS = 1_225_000;

    /// @notice Returns one quarter of the LP fee at or below the threshold, or one sixth above it.
    /// @dev Integer division rounds down. Zero LP fee gives zero DAO fee.
    function daoFeeBps(uint32 feeBps) internal pure returns (uint32) {
        return feeBps <= TIER_THRESHOLD_BPS ? feeBps / 4 : feeBps / 6;
    }
}
