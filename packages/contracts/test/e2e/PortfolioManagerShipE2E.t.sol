// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IAqua} from "aqua/interfaces/IAqua.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";
import {PortfolioManagerStrategyValidator} from "../../src/PortfolioManagerStrategyValidator.sol";
import {IPortfolioManagerStrategyValidator} from "../../src/interfaces/IPortfolioManagerStrategyValidator.sol";

/// @notice Tests shipping and validation from the dedicated Safe against the forked Aqua registry.
contract PortfolioManagerShipE2ETest is PortfolioManagerE2EBase {
    function test_FreshWalletStartsWithNoUniverseTokenBalance() public {
        assertEq(pmTokenA.balanceOf(address(pmSafe)), 0, "fresh Safe must start with zero universe-token balance");
        assertEq(pmTokenB.balanceOf(address(pmSafe)), 0, "fresh Safe must start with zero universe-token balance");
    }

    function test_ShipsStrategyFromFreshDedicatedWallet() public {
        uint256 tokenABalanceBefore = pmTokenA.balanceOf(address(pmSafe));
        uint256 tokenBBalanceBefore = pmTokenB.balanceOf(address(pmSafe));

        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        bytes32 strategyHash = _fundAndShip(order, INITIAL_BALANCE);

        // Check the funding delta.
        assertEq(pmTokenA.balanceOf(address(pmSafe)), tokenABalanceBefore + INITIAL_BALANCE);
        assertEq(pmTokenB.balanceOf(address(pmSafe)), tokenBBalanceBefore + INITIAL_BALANCE);

        (uint248 ledgerA, uint8 tokensCountA) =
            aqua.rawBalances(address(pmSafe), address(router), strategyHash, address(pmTokenA));
        assertEq(uint256(ledgerA), INITIAL_BALANCE, "tokenA ledger must match the shipped amount");
        assertGt(tokensCountA, 0, "strategy must be registered as active for tokenA");

        (uint248 ledgerB, uint8 tokensCountB) =
            aqua.rawBalances(address(pmSafe), address(router), strategyHash, address(pmTokenB));
        assertEq(uint256(ledgerB), INITIAL_BALANCE, "tokenB ledger must match the shipped amount");
        assertGt(tokensCountB, 0, "strategy must be registered as active for tokenB");
    }

    function test_ShippedStrategyIsImmutableOnReattempt() public {
        // Use a distinct strategy hash for this shipping test.
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS + 1);
        _fundAndShip(order, INITIAL_BALANCE);

        // Reuse existing approvals and ship the same strategy again.
        address[] memory tokens = new address[](2);
        tokens[0] = address(pmTokenA);
        tokens[1] = address(pmTokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = INITIAL_BALANCE;
        amounts[1] = INITIAL_BALANCE;

        // _shipOnly makes one external call, so expectRevert targets Safe execution.
        vm.expectRevert(
            abi.encodeWithSelector(IAqua.StrategiesMustBeImmutable.selector, address(router), router.hash(order))
        );
        _shipOnly(order, tokens, amounts);
    }

    function test_ShipRevertsAtomicallyOnMismatchedUniverseThroughTheRealMultiSendBatch() public {
        // Distinct feeBps so this order's strategyHash can't collide with any other test's.
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS + 2);

        deal(address(pmTokenA), address(pmSafe), INITIAL_BALANCE);
        vm.prank(address(pmSafe));
        pmTokenA.approve(address(aqua), type(uint256).max);

        // The order declares two tokens, but the shipping list contains only tokenA.
        address[] memory tokens = new address[](1);
        tokens[0] = address(pmTokenA);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = INITIAL_BALANCE;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPortfolioManagerStrategyValidator.PortfolioManagerStrategyValidatorDeclaredTokenNotShipped.selector,
                address(pmTokenB)
            )
        );
        _shipOnly(order, tokens, amounts);

        // A failed validation must leave Aqua's ledger unchanged.
        (, uint8 tokensCountA) =
            aqua.rawBalances(address(pmSafe), address(router), router.hash(order), address(pmTokenA));
        assertEq(tokensCountA, 0, "a rejected ship() must never register on Aqua's ledger");
    }
}
