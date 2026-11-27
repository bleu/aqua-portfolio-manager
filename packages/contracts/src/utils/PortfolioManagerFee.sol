// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {FixedPointMath} from "./FixedPointMath.sol";

/// @title PortfolioManagerFee
/// @notice Pure math for applying a PM_BPS-scaled rate to the LP fee. Rates and recipients
///         themselves are not compiled into this library -- they're constructor-set state on
///         `PortfolioManagerSwap` (the DAO's rate and treasury immutable; 1inch's revenue-share
///         rate/treasury and Bleu/Trim's rate/treasury each mutable by their own admin), since
///         all three can differ per deployment and change independently over the deployment's
///         life.
library PortfolioManagerFee {
    uint256 private constant PM_BPS = 1e9;

    /// @notice Returns `feePmBps`'s share at `rateBps`, both PM_BPS-scaled (1e9 = 100%).
    /// @dev Integer division rounds down. A zero rate or zero LP fee gives a zero share.
    ///      `feePmBps` must already be PM_BPS-scaled, not a 1e4-style bps value -- named to make
    ///      that explicit. The only production caller (`PortfolioManagerSwap`) always passes an
    ///      already-decoded, already-attested strategy's `feeBps`, itself bounded to
    ///      `[MIN_FEE_BPS, PM_BPS)` by `PortfolioManagerArgsCodec.build` -- this function stays
    ///      unbounded-input `pure` math, not a second place to repeat that check.
    function shareBps(uint32 feePmBps, uint32 rateBps) internal pure returns (uint32) {
        return uint32(FixedPointMath.mulDivDown(feePmBps, rateBps, PM_BPS));
    }
}
