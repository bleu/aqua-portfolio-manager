// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title PortfolioManagerFee
/// @notice DAO protocol fee rates and recipient for the PM instruction.
/// @dev BLEUDEV-451: these two recipients are hardcoded `library` constants, not per-deployment
///      configuration, so a key rotation or a deployment on a chain where either address is
///      controlled by someone else would need a new `PortfolioManagerSwap` (every caller inlines
///      these at compile time -- there is no instance to reconfigure). Accepted as-is: making them
///      configurable means turning this from a `library` into a stateful contract with its own
///      governance-gated setter, a bigger redesign than this fee math itself, touching every
///      constructor in the inheritance chain down to `PortfolioManagerRouter`. Revisit only
///      alongside a deliberate multi-chain or key-rotation deployment plan, not in isolation.
library PortfolioManagerFee {
    /// @dev DAO treasury address disclosed in 1IP-103.
    address internal constant DAO_TREASURY_ADDRESS = 0x7951c7ef839e26F63DA87a42C9a87986507f1c07;

    /// @dev Bleu treasury address. Bleu's 50% share of the protocol-fee cut sits outside 1IP-103,
    /// agreed separately between Bleu and 1inch.
    address internal constant BLEU_TREASURY_ADDRESS = 0x5958599c16f6138f2B0fb65040ddEb639FCA5B9A;

    /// @dev Implements 1IP-103's approximate 0.1225% tier boundary with a 1e9 scale.
    uint32 internal constant TIER_THRESHOLD_BPS = 1_225_000;

    /// @notice Returns one quarter of the LP fee at or below the threshold, or one sixth above it.
    /// @dev Integer division rounds down. Zero LP fee gives zero DAO fee.
    function daoFeeBps(uint32 feeBps) internal pure returns (uint32) {
        return feeBps <= TIER_THRESHOLD_BPS ? feeBps / 4 : feeBps / 6;
    }
}
