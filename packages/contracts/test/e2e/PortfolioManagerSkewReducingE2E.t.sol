// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";

contract PortfolioManagerSkewReducingE2ETest is PortfolioManagerE2EBase {
    /// @dev Donate tokenA directly to create an external balance change.
    uint256 internal constant SKEW_AMOUNT = 20_000e18;
    uint256 internal constant TRADE_AMOUNT = 100e18;

    function test_SkewReducingTradeGetsRewardedRate() public {
        // Disable fees to isolate price impact.
        ISwapVM.Order memory order = _buildOrder(0);
        _fundAndShip(order, INITIAL_BALANCE);

        // Make tokenA overweight by donation.
        deal(address(pmTokenA), address(pmSafe), INITIAL_BALANCE + SKEW_AMOUNT);

        // The taker removes overweight tokenA from the wallet.
        (uint256 amountIn, uint256 amountOut) = _swapExactIn(order, address(pmTokenB), address(pmTokenA), TRADE_AMOUNT);

        assertGt(amountOut, amountIn, "a skew-reducing trade must receive more than the fair 1:1 rate");
    }
}
