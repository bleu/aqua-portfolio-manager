// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ExposureReader — real, wallet-wide balance reads for the Portfolio Manager
/// @notice Reads plain `balanceOf(maker)`, never `AQUA.rawBalances`/`safeBalances`. Per
///         ADR-0002: those two are the same underlying per-`(maker, app, strategyHash)` ledger
///         entry — populated once at `ship()` with no check against real holdings, and moved
///         only by that same strategy's own `pull`/`push` — not a settled, wallet-wide reading.
///         A different strategy shipped from the very same maker wallet never touches that
///         ledger, so pricing off it would miss real exposure. `balanceOf` is the only reading
///         that is actually real and shared across every strategy the maker runs from that
///         wallet (ADR-0002's whole reason for requiring a dedicated wallet in the first
///         place).
library ExposureReader {
    error ExposureReaderTokenOutsideDeclaredUniverse(address token);

    /// @notice Real balance of `token` in `maker`'s wallet, gated to the declared universe.
    /// @dev ADR-0002 requires filtering to the declared universe here, not just by callers
    ///      remembering to check first — an accidental transfer or donation outside the universe
    ///      must be ignored by the reading itself. Reverting (rather than returning a stale/zero
    ///      balance) makes an out-of-universe read a loud caller bug, not a silent mispricing.
    function balanceOf(address token, address maker, address[] memory universe) internal view returns (uint256) {
        bool inUniverse = false;
        for (uint256 i = 0; i < universe.length; i++) {
            if (universe[i] == token) {
                inUniverse = true;
                break;
            }
        }
        require(inUniverse, ExposureReaderTokenOutsideDeclaredUniverse(token));

        return IERC20(token).balanceOf(maker);
    }
}
