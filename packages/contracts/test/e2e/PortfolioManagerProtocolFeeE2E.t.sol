// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerFee} from "../../src/utils/PortfolioManagerFee.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";

/// @notice The DAO's and Bleu/Trim's independently-configured rates (agreed separately between
/// Bleu and 1inch, outside 1IP-103) are pulled to the real 1inch DAO Treasury and Bleu's treasury
/// after a real swap against the actually deployed router.
contract PortfolioManagerProtocolFeeE2ETest is PortfolioManagerE2EBase {
    uint256 internal constant TRADE_AMOUNT = 1_000e18;

    /// @dev Distinct fee gives this order a distinct strategy hash.
    uint32 internal constant FEE_TEST_BPS = LOW_TIER_FEE_BPS + 2;

    function test_ProtocolFeeSplitsBetweenDaoAndBleuTreasuries() public {
        ISwapVM.Order memory order = _buildOrder(FEE_TEST_BPS);
        _fundAndShip(order, INITIAL_BALANCE);

        uint256 daoBalanceBefore = pmTokenA.balanceOf(router.DAO_TREASURY());
        uint256 bleuBalanceBefore = pmTokenA.balanceOf(router.trimTreasury());

        (uint256 amountIn,) = _swapExactIn(order, address(pmTokenA), address(pmTokenB), TRADE_AMOUNT);
        assertEq(amountIn, TRADE_AMOUNT, "taker pays the exact amount they specified");

        uint256 expectedDaoAmount =
            TRADE_AMOUNT * PortfolioManagerFee.shareBps(FEE_TEST_BPS, FEE_RATE_BPS) / FEE_BPS_SCALE;
        uint256 expectedBleuAmount = expectedDaoAmount;

        uint256 daoBalanceAfter = pmTokenA.balanceOf(router.DAO_TREASURY());
        uint256 bleuBalanceAfter = pmTokenA.balanceOf(router.trimTreasury());

        assertGt(expectedDaoAmount, 0, "sanity: this fee/amount must produce a nonzero DAO fee");
        assertEq(
            daoBalanceAfter - daoBalanceBefore,
            expectedDaoAmount,
            "the real DAO Treasury address must receive exactly its configured rate"
        );
        assertEq(
            bleuBalanceAfter - bleuBalanceBefore,
            expectedBleuAmount,
            "the real Bleu Treasury address must receive exactly its own configured rate, independently of the DAO's cut"
        );
    }
}
