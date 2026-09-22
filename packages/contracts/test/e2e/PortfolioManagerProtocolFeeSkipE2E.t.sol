// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Vm} from "forge-std/Vm.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {Fee} from "swap-vm/instructions/Fee.sol";
import {PortfolioManagerFee} from "../../src/utils/PortfolioManagerFee.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";

/// @notice Insufficient fee authorization skips the DAO transfer, emits ProtocolFeeSkipped, and preserves swap execution.
contract PortfolioManagerProtocolFeeSkipE2ETest is PortfolioManagerE2EBase {
    uint256 internal constant TRADE_AMOUNT = 1_000e18;

    /// @dev Distinct fee gives this order a distinct strategy hash.
    uint32 internal constant FEE_SKIP_TEST_BPS = LOW_TIER_FEE_BPS + 3;

    function test_ProtocolFeeSkipsWithoutBlockingTheSwap() public {
        ISwapVM.Order memory order = _buildOrder(FEE_SKIP_TEST_BPS);
        // Fund the wallet but give the DAO pull no tokenA ledger authorization.
        _fundAndShip(order, 0);

        uint256 daoBalanceBefore = pmTokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS);

        vm.recordLogs();
        (uint256 amountIn,) = _swapExactIn(order, address(pmTokenA), address(pmTokenB), TRADE_AMOUNT);
        assertEq(amountIn, TRADE_AMOUNT, "swap still completes even though the fee pull was skipped");

        assertEq(
            pmTokenA.balanceOf(PortfolioManagerFee.DAO_TREASURY_ADDRESS),
            daoBalanceBefore,
            "DAO Treasury balance must be unchanged when the pull is skipped"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 skippedEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == Fee.ProtocolFeeSkipped.selector) {
                skippedEvents++;
                (, address token, address to, uint256 skippedAmount) =
                    abi.decode(logs[i].data, (bytes32, address, address, uint256));
                assertEq(token, address(pmTokenA));
                assertEq(to, PortfolioManagerFee.DAO_TREASURY_ADDRESS);
                assertGt(skippedAmount, 0);
            }
        }
        assertEq(skippedEvents, 1, "exactly one ProtocolFeeSkipped against the real deployed router");
    }
}
