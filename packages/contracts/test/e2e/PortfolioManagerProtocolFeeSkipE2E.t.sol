// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Vm} from "forge-std/Vm.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {Fee} from "swap-vm/instructions/Fee.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";

/// @notice Insufficient fee authorization skips both the DAO and Bleu transfers independently,
/// emits ProtocolFeeSkipped once per recipient, and preserves swap execution.
contract PortfolioManagerProtocolFeeSkipE2ETest is PortfolioManagerE2EBase {
    uint256 internal constant TRADE_AMOUNT = 1_000e18;

    /// @dev Distinct fee gives this order a distinct strategy hash.
    uint32 internal constant FEE_SKIP_TEST_BPS = LOW_TIER_FEE_BPS + 3;

    function test_ProtocolFeeSkipsWithoutBlockingTheSwap() public {
        ISwapVM.Order memory order = _buildOrder(FEE_SKIP_TEST_BPS);
        // Fund the wallet but give none of the three fee pulls any tokenA ledger authorization.
        _fundAndShip(order, 0);

        uint256 protocolBalanceBefore = pmTokenA.balanceOf(router.PROTOCOL_TREASURY());
        uint256 bleuBalanceBefore = pmTokenA.balanceOf(router.operatorTreasury());
        uint256 revenueShareBalanceBefore = pmTokenA.balanceOf(router.revenueShareTreasury());

        vm.recordLogs();
        (uint256 amountIn,) = _swapExactIn(order, address(pmTokenA), address(pmTokenB), TRADE_AMOUNT);
        assertEq(amountIn, TRADE_AMOUNT, "swap still completes even though all three fee pulls were skipped");

        assertEq(
            pmTokenA.balanceOf(router.PROTOCOL_TREASURY()),
            protocolBalanceBefore,
            "DAO Treasury balance must be unchanged when its pull is skipped"
        );
        assertEq(
            pmTokenA.balanceOf(router.operatorTreasury()),
            bleuBalanceBefore,
            "Bleu Treasury balance must be unchanged when its pull is skipped"
        );
        assertEq(
            pmTokenA.balanceOf(router.revenueShareTreasury()),
            revenueShareBalanceBefore,
            "1inch's revenue-share treasury balance must be unchanged when its pull is skipped"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 protocolSkipped = 0;
        uint256 bleuSkipped = 0;
        uint256 revenueShareSkipped = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == Fee.ProtocolFeeSkipped.selector) {
                (, address token, address to, uint256 skippedAmount) =
                    abi.decode(logs[i].data, (bytes32, address, address, uint256));
                assertEq(token, address(pmTokenA));
                assertGt(skippedAmount, 0);
                if (to == router.PROTOCOL_TREASURY()) {
                    protocolSkipped++;
                } else if (to == router.operatorTreasury()) {
                    bleuSkipped++;
                } else if (to == router.revenueShareTreasury()) {
                    revenueShareSkipped++;
                }
            }
        }
        assertEq(protocolSkipped, 1, "exactly one ProtocolFeeSkipped for the DAO's cut");
        assertEq(bleuSkipped, 1, "exactly one ProtocolFeeSkipped for Bleu's cut");
        assertEq(revenueShareSkipped, 1, "exactly one ProtocolFeeSkipped for 1inch's revenue-share cut");
    }
}
