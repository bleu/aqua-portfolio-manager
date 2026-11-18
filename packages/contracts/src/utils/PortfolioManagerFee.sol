// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

/// @title PortfolioManagerFee
/// @notice DAO protocol fee rates and recipient for the PM instruction.
/// @dev These two recipients are hardcoded `library` constants, not per-deployment
///      configuration -- every caller inlines them at compile time, so a key rotation needs a
///      new `PortfolioManagerSwap`. Making them configurable would mean turning this into a
///      stateful, governance-gated contract, a bigger redesign than this fee math itself.
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
    /// @dev BLEUDEV-454 (Info): `feePmBps` must already be PM_BPS-scaled (1e9 = 100%), not a
    ///      1e4-style bps value -- renamed from the previous `feeBps` to make that explicit. The
    ///      only production caller (`PortfolioManagerSwap`) always passes an already-decoded,
    ///      already-attested strategy's `feeBps`, itself bounded to
    ///      `[MIN_FEE_BPS, PM_BPS)` by `PortfolioManagerArgsCodec.build` (BLEUDEV-453) -- this
    ///      function stays unbounded-input `pure` math, not a second place to repeat that check.
    function daoFeeBps(uint32 feePmBps) internal pure returns (uint32) {
        return feePmBps <= TIER_THRESHOLD_BPS ? feePmBps / 4 : feePmBps / 6;
    }
}
