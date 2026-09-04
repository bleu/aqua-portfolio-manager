// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Vm} from "forge-std/Vm.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {Fee} from "swap-vm/instructions/Fee.sol";
import {PortfolioManagerProgramBuilder} from "../src/PortfolioManagerProgramBuilder.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.sol";

/// @notice BLEUDEV-342: best-effort protocol-fee collection against the actually deployed
/// router — a maker with insufficient Aqua-ledger balance for the DAO pull still completes the
/// swap; only the fee is skipped, reported via `ProtocolFeeSkipped`, not silently absorbed or
/// reverted. Mirrors `Fee.sol`'s documented rationale (OpenZeppelin M-09/Theori #10).
contract PortfolioManagerProtocolFeeSkipE2ETest is PortfolioManagerE2EBase {
    uint256 internal constant TRADE_AMOUNT = 1_000e18;

    /// @dev Distinct from every other `feeBps` this E2E suite ships through the same `pmSafe`
    ///      (`LOW_TIER_FEE_BPS`, `LOW_TIER_FEE_BPS + 1`, `PortfolioManagerProtocolFeeE2E`'s
    ///      `LOW_TIER_FEE_BPS + 2`) so this order's `strategyHash` never collides with theirs;
    ///      see `PortfolioManagerSkewWorseningE2E.t.sol`'s note on the same hazard.
    uint32 internal constant FEE_SKIP_TEST_BPS = LOW_TIER_FEE_BPS + 3;

    function test_ProtocolFeeSkipsWithoutBlockingTheSwap() public {
        ISwapVM.Order memory order = _buildOrder(FEE_SKIP_TEST_BPS);
        // Ship with zero tokenA ledger -- the DAO pull cannot be covered at all, even though
        // the wallet's real balance (what the curve prices off) is fully funded.
        _fundAndShip(order, 0);

        uint256 daoBalanceBefore = pmTokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);

        vm.recordLogs();
        (uint256 amountIn,) = _swapExactIn(order, address(pmTokenA), address(pmTokenB), TRADE_AMOUNT);
        assertEq(amountIn, TRADE_AMOUNT, "swap still completes even though the fee pull was skipped");

        assertEq(
            pmTokenA.balanceOf(PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS),
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
                assertEq(to, PortfolioManagerProgramBuilder.DAO_TREASURY_ADDRESS);
                assertGt(skippedAmount, 0);
            }
        }
        assertEq(skippedEvents, 1, "exactly one ProtocolFeeSkipped against the real deployed router");
    }
}
