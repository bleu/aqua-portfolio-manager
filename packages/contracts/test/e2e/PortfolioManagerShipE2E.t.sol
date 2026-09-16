// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {IAqua} from "aqua/interfaces/IAqua.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.t.sol";
import {PortfolioManagerStrategyFactory} from "../../src/PortfolioManagerStrategyFactory.sol";

/// @notice Ships a real PM strategy from a fresh dedicated maker wallet (ADR-0002)
/// against the actually deployed router and Aqua registry — see PortfolioManagerE2EBase for the
/// shared setup and why this uses a separate, guard-less Safe from BasketScopeGuardE2ETest's.
contract PortfolioManagerShipE2ETest is PortfolioManagerE2EBase {
    function test_FreshWalletStartsWithNoUniverseTokenBalance() public {
        // "Dedicated" per ADR-0002 means nothing else has touched this wallet yet in a fresh
        // deployment -- Deploy.s.sol deploys a brand new Safe proxy per run. Note this only
        // holds for the very first test to touch pmSafe in a given run: forge doesn't
        // snapshot/revert state between test *contracts* any more than between test functions
        // on a live --rpc-url run, so this assertion is meaningful pre-deploy verification, not
        // a property every test in this suite can independently rely on (the other tests below
        // assert balance deltas instead, for exactly that reason).
        assertEq(pmTokenA.balanceOf(address(pmSafe)), 0, "fresh Safe must start with zero universe-token balance");
        assertEq(pmTokenB.balanceOf(address(pmSafe)), 0, "fresh Safe must start with zero universe-token balance");
    }

    function test_ShipsStrategyFromFreshDedicatedWallet() public {
        uint256 tokenABalanceBefore = pmTokenA.balanceOf(address(pmSafe));
        uint256 tokenBBalanceBefore = pmTokenB.balanceOf(address(pmSafe));

        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS);
        bytes32 strategyHash = _fundAndShip(order, INITIAL_BALANCE);

        // Asserts the delta _fundAndShip itself minted, not pmSafe's absolute balance: pmSafe is
        // shared across this whole E2E suite on a live --rpc-url run (no snapshot/revert between
        // test contracts), so another suite's own _fundAndShip may have already funded it.
        assertEq(pmTokenA.balanceOf(address(pmSafe)), tokenABalanceBefore + INITIAL_BALANCE);
        assertEq(pmTokenB.balanceOf(address(pmSafe)), tokenBBalanceBefore + INITIAL_BALANCE);

        // Aqua's own ledger reflects the real ship() call, not just a locally-computed hash --
        // rawBalances is the actual per-(maker, app, strategyHash) accounting entry the fee
        // pulls and settlement draw against.
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
        // A distinct feeBps (not LOW_TIER_FEE_BPS) so this test's strategyHash never collides
        // with test_ShipsStrategyFromFreshDedicatedWallet's -- forge doesn't snapshot/revert
        // state between test functions when running against a live --rpc-url (only real forks
        // via --fork-url get that), so two tests shipping the byte-identical strategy would
        // otherwise interfere with each other depending on execution order.
        ISwapVM.Order memory order = _buildOrder(LOW_TIER_FEE_BPS + 1);
        _fundAndShip(order, INITIAL_BALANCE);

        // Reuse the allowances _fundAndShip already set and attempt the ship() call alone --
        // Aqua.sol requires balance.tokensCount == 0 per token, so re-shipping the exact same
        // strategy must fail, proving the deployed registry enforces immutability for real, not
        // just in a unit test with a fresh Aqua instance.
        address[] memory tokens = new address[](2);
        tokens[0] = address(pmTokenA);
        tokens[1] = address(pmTokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = INITIAL_BALANCE;
        amounts[1] = INITIAL_BALANCE;

        // _shipOnly contains exactly one external call (execTransaction), so arming
        // vm.expectRevert() immediately before it attaches to the right call. Targets the
        // specific Aqua error, not just any revert, so this only passes for the immutability
        // check -- not e.g. a stray allowance or gas issue elsewhere in the call.
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

        // order declares both pmTokenA and pmTokenB (see _buildOrder), but only pmTokenA is
        // shipped here -- the exact mismatch _shipOnly's MultiSendCallOnly batch exists to catch
        // before it reaches Aqua's ledger, not just in the factory's own isolated unit tests.
        address[] memory tokens = new address[](1);
        tokens[0] = address(pmTokenA);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = INITIAL_BALANCE;

        vm.expectRevert(
            abi.encodeWithSelector(
                PortfolioManagerStrategyFactory.PortfolioManagerStrategyFactoryDeclaredTokenNotShipped.selector,
                address(pmTokenB)
            )
        );
        _shipOnly(order, tokens, amounts);

        // MultiSendCallOnly reverts the whole batch on the first failed leg -- confirm the
        // mismatch never reached Aqua's ledger at all, not just that the call reverted.
        (, uint8 tokensCountA) =
            aqua.rawBalances(address(pmSafe), address(router), router.hash(order), address(pmTokenA));
        assertEq(tokensCountA, 0, "a rejected ship() must never register on Aqua's ledger");
    }
}
