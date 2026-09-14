// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerProgramBuilder} from "../../src/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";

/// @notice The 1IP-103 tiered protocol fee lands in the real 1inch DAO Treasury
/// address after a real swap against the actually deployed router.
contract PortfolioManagerProtocolFeeE2ETest is PortfolioManagerE2EBase {
    uint256 internal constant TRADE_AMOUNT = 1_000e18;

    /// @dev Distinct from `LOW_TIER_FEE_BPS`/`LOW_TIER_FEE_BPS + 1` (already used by
    ///      `PortfolioManagerShipE2E.t.sol`'s two ships) so this suite's order -- otherwise
    ///      identical `pmSafe`/universe/weights -- doesn't collide on `strategyHash` with
    ///      theirs; see `PortfolioManagerSkewWorseningE2E.t.sol`'s note on the same hazard.
    uint32 internal constant FEE_TEST_BPS = LOW_TIER_FEE_BPS + 2;

    function test_ProtocolFeeLandsInRealDaoTreasury() public {
        ISwapVM.Order memory order = _buildOrder(FEE_TEST_BPS);
        _fundAndShip(order, INITIAL_BALANCE);

        uint256 daoBalanceBefore = pmTokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);

        (uint256 amountIn,) = _swapExactIn(order, address(pmTokenA), address(pmTokenB), TRADE_AMOUNT);
        assertEq(amountIn, TRADE_AMOUNT, "taker pays the exact amount they specified");

        uint256 expectedDaoAmount =
            TRADE_AMOUNT * PortfolioManagerProgramBuilder.daoFeeBps(FEE_TEST_BPS) / FEE_BPS_SCALE;
        uint256 daoBalanceAfter = pmTokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);

        assertGt(expectedDaoAmount, 0, "sanity: this tier/amount must produce a nonzero fee");
        assertEq(
            daoBalanceAfter - daoBalanceBefore,
            expectedDaoAmount,
            "the real DAO Treasury address must receive exactly the 1/4-tier amount"
        );
    }
}
