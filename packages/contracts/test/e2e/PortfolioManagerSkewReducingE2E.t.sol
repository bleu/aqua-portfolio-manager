// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.sol";

/// @notice Trades that move the wallet's exposure toward its declared 50/50
/// target — confirm the curve's own price impact rewards this direction, matching PRICING.md's
/// prediction, against the actually deployed router.
contract PortfolioManagerSkewReducingE2ETest is PortfolioManagerE2EBase {
    /// @dev A direct donation of extra tokenA — simulates external skew (a large incoming
    ///      trade elsewhere, or an outright donation per DONATION-RESISTANCE-PROOF.md), not a
    ///      PM trade. Real ERC20 balance, so the curve's own real-balance read (ADR-0002)
    ///      picks it up automatically on the next quote, no PM-side bookkeeping involved.
    uint256 internal constant SKEW_AMOUNT = 20_000e18;
    uint256 internal constant TRADE_AMOUNT = 100e18;

    function test_SkewReducingTradeGetsRewardedRate() public {
        // feeBps = 0 isolates the curve's own price-impact reward from any fee distortion.
        // Full ledger on both sides -- this test isn't exercising the fee-skip ledger-starving
        // scenario, and settlement pulls tokenA (tokenOut here) from it.
        ISwapVM.Order memory order = _buildOrder(0);
        _fundAndShip(order, INITIAL_BALANCE);

        // Wallet starts perfectly balanced (INITIAL_BALANCE each, per _fundAndShip); skew it by
        // donating extra tokenA so the wallet is now overweight tokenA relative to target.
        deal(address(pmTokenA), address(pmSafe), INITIAL_BALANCE + SKEW_AMOUNT);

        // Skew-reducing: the wallet SHEDS the overweight token (tokenA is tokenOut here), i.e.
        // the taker brings in tokenB and receives tokenA -- moving the wallet back toward 50/50.
        (uint256 amountIn, uint256 amountOut) = _swapExactIn(order, address(pmTokenB), address(pmTokenA), TRADE_AMOUNT);

        // At perfect 50/50 with equal weights the fair rate is 1:1 (no fee here to distort it);
        // correcting an existing skew must beat that, per PRICING.md's own prediction.
        assertGt(amountOut, amountIn, "a skew-reducing trade must receive more than the fair 1:1 rate");
    }
}
