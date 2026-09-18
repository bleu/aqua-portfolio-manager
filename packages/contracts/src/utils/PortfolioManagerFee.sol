// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title PortfolioManagerFee — 1IP-103's tiered protocol fee, in one place
/// @notice Split out of `PortfolioManagerProgramBuilder` so both it and `PortfolioManagerSwap`
///         (the two real callers) depend on a dedicated fee module instead of one owning the
///         other's constants incidentally.
library PortfolioManagerFee {
    /// @dev 1inch DAO Treasury's main wallet, disclosed in 1IP-103 (the governance proposal
    ///      that activated Aqua's protocol fee): the sole recipient of the protocol fee.
    address internal constant DAO_TREASURY_ADDRESS = 0x7951c7ef839e26F63DA87a42C9a87986507f1c07;

    /// @dev 1IP-103's tier boundary: "≈0.1225%" (the proposal's own hedge, quoted as "the
    ///      geometric midpoint of 0.05% and 0.30%") at `PM_BPS = 1e9` scale.
    uint32 internal constant TIER_THRESHOLD_BPS = 1_225_000;

    /// @notice 1IP-103's tiered protocol fee: 1/4 of the LP's own `feeBps` at or below the
    ///         tier threshold, 1/6 above it. Not a flat rate — it scales with whatever the LP
    ///         configured, because that's what the proposal actually specifies ("a slice of
    ///         the LP fee on each strategy"), not an independently-set number. `feeBps == 0`
    ///         correctly yields `0`.
    function daoFeeBps(uint32 feeBps) internal pure returns (uint32) {
        return feeBps <= TIER_THRESHOLD_BPS ? feeBps / 4 : feeBps / 6;
    }
}
