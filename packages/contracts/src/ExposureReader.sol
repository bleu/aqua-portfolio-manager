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
    /// @dev ADR-0002's "Consequences" section requires the exposure reader itself to filter to
    ///      the declared universe ("a spec requirement, not a documentation note") — anything
    ///      that lands in the wallet outside that universe (accidental transfer, deliberate
    ///      donation) must be ignored by the reading, not merely by callers remembering to
    ///      check membership first. Reverting here, rather than silently returning a stale or
    ///      zero balance, makes an out-of-universe read a loud caller bug instead of a silent
    ///      mispricing.
    /// @dev BLEUDEV-345: this revert is unreachable through the current router when called from
    ///      `PortfolioManagerSwap` — `SwapVM.swap()` already calls
    ///      `AQUA.safeBalances(maker, app, strategyHash, tokenIn, tokenOut)` before ever
    ///      dispatching to that opcode, and Aqua's own ledger rejects an undeclared token first
    ///      (`IAqua.SafeBalancesForTokenNotInActiveStrategy`). Kept rather than stripped: this is
    ///      a library, not something owned by any one caller — the ADR-0002 requirement above
    ///      applies to `ExposureReader` itself, independent of which instruction ends up calling
    ///      it, including ones that don't route through `SwapVM`'s own gate.
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
