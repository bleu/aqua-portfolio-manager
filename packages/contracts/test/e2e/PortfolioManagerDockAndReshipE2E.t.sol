// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IAqua} from "aqua/interfaces/IAqua.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";

/// @notice Covers ship -> dock -> reship: Aqua.dock() never clears a strategyHash back to
///         reusable, so reshipping identical params after docking must still revert, while
///         changing even one order parameter must succeed, since it hashes to a new strategy.
contract PortfolioManagerDockAndReshipE2ETest is PortfolioManagerE2EBase {
    /// @dev Aqua.dock()'s private "docked" sentinel for a token's tokensCount slot.
    uint8 private constant DOCKED_TOKENS_COUNT = type(uint8).max;

    function _universeTokens() private view returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = address(pmTokenA);
        tokens[1] = address(pmTokenB);
    }

    function test_ReshippingIdenticalParamsAfterDockingStillReverts() public {
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS + 10);
        bytes32 strategyHash = _fundAndShip(order, INITIAL_BALANCE);

        _dock(strategyHash, _universeTokens());

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = INITIAL_BALANCE;
        amounts[1] = INITIAL_BALANCE;

        vm.expectRevert(abi.encodeWithSelector(IAqua.StrategiesMustBeImmutable.selector, address(router), strategyHash));
        _shipOnly(order, _universeTokens(), amounts);
    }

    function test_ReshippingWithOneChangedParamAfterDockingSucceeds() public {
        ISwapVM.Order memory firstOrder = _buildOrder(LOW_TIER_FEE_BPS + 11);
        bytes32 firstStrategyHash = _fundAndShip(firstOrder, INITIAL_BALANCE);

        _dock(firstStrategyHash, _universeTokens());

        // Same tokens and groups, one differing parameter (the LP fee) -- must hash to a new strategy.
        ISwapVM.Order memory secondOrder = _buildOrder(LOW_TIER_FEE_BPS + 12);
        bytes32 secondStrategyHash = _fundAndShip(secondOrder, INITIAL_BALANCE);

        assertTrue(secondStrategyHash != firstStrategyHash, "a changed parameter must produce a new strategy hash");

        (, uint8 tokensCountFirst) =
            aqua.rawBalances(address(pmSafe), address(router), firstStrategyHash, address(pmTokenA));
        assertEq(tokensCountFirst, DOCKED_TOKENS_COUNT, "the docked strategy must stay docked, not reopen");

        (uint248 ledgerSecond, uint8 tokensCountSecond) =
            aqua.rawBalances(address(pmSafe), address(router), secondStrategyHash, address(pmTokenA));
        assertEq(uint256(ledgerSecond), INITIAL_BALANCE, "the new strategy's ledger must reflect the fresh ship");
        assertGt(tokensCountSecond, 0, "the new strategy must be registered as active");
    }
}
