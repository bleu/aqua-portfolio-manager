// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.sol";

/// @notice BLEUDEV-291: trades that move the wallet's exposure away from its declared 50/50
/// target — confirm the curve's own price impact penalizes this direction, matching
/// PRICING.md's prediction, against the actually deployed router.
contract PortfolioManagerSkewWorseningE2ETest is PortfolioManagerE2EBase {
    /// @dev See PortfolioManagerSkewReducingE2E.t.sol's identical constant note.
    uint256 internal constant SKEW_AMOUNT = 20_000e18;
    uint256 internal constant TRADE_AMOUNT = 100e18;

    function test_SkewWorseningTradeGetsPenalizedRate() public {
        // feeBps = 0 isolates the curve's own price-impact penalty from any fee distortion.
        // Full ledger on both sides -- this test isn't exercising the fee-skip ledger-starving
        // scenario (that's BLEUDEV-342).
        ISwapVM.Order memory order = _buildOrder(0);
        _fundAndShip(order, INITIAL_BALANCE);

        // Wallet starts perfectly balanced; skew it by donating extra tokenA so the wallet is
        // already overweight tokenA relative to target.
        vm.prank(deployer);
        pmTokenA.mint(address(pmSafe), SKEW_AMOUNT);

        // Skew-worsening: the taker brings in MORE tokenA (already overweight) and receives
        // tokenB -- pushing the wallet further from 50/50, the opposite correction direction.
        (uint256 amountIn, uint256 amountOut) = _swapExactIn(order, address(pmTokenA), address(pmTokenB), TRADE_AMOUNT);

        // At perfect 50/50 with equal weights the fair rate is 1:1 (no fee here to distort it);
        // worsening an existing skew must fall short of that, per PRICING.md's own prediction.
        assertLt(amountOut, amountIn, "a skew-worsening trade must receive less than the fair 1:1 rate");
    }
}
