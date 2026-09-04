// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua/blob/main/LICENSES/Aqua-Source-1.1.txt

import {Aqua} from "aqua/Aqua.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {ISwapVM} from "swap-vm/interfaces/ISwapVM.sol";
import {PortfolioManagerE2EBase} from "./base/PortfolioManagerE2EBase.sol";

/// @notice BLEUDEV-286: ships a real PM strategy from a fresh dedicated maker wallet (ADR-0002)
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

        // Deliberately NOT routed through _shipOnly: that helper bundles the (non-reverting)
        // getTransactionHash view call together with the (reverting) execTransaction call in a
        // single internal function, and vm.expectRevert() attaches to the next *external* call
        // regardless of which internal function it's nested inside -- arming it immediately
        // before calling _shipOnly would actually attach to getTransactionHash, not
        // execTransaction. Computing the signed calldata inline, entirely outside the armed
        // window, keeps vm.expectRevert() pointed at the one call that's actually expected to
        // revert.
        bytes memory shipData = abi.encodeCall(Aqua.ship, (address(router), abi.encode(order), tokens, amounts));
        bytes32 txHash = pmSafe.getTransactionHash(
            address(aqua), 0, shipData, Enum.Operation.Call, 0, 0, 0, address(0), address(0), pmSafe.nonce()
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DEPLOYER_KEY, txHash);

        // execTransaction bubbles the inner revert rather than swallowing it into a `false`
        // return on this Safe version -- confirmed empirically against the real deployed Safe.
        vm.expectRevert();
        pmSafe.execTransaction(
            address(aqua),
            0,
            shipData,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            abi.encodePacked(r, s, v)
        );
    }
}
