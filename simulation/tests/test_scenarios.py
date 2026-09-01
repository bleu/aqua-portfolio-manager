"""Scenario-level regression tests — one per BLEUDEV-334 requirement (R1/R5/R6), matching
what each scenarios/ builder is actually for."""

from __future__ import annotations

import unittest

from aqua_sim.scenarios import basket_with_without_pm, cross_basket_no_pm, guard_enforcement, pm_alone


class PmAloneScenarioTest(unittest.TestCase):
    def test_tracking_error_stays_tight_across_seeds(self) -> None:
        for seed in range(5):
            world = pm_alone.build_world(seed=seed)
            world.run(300)
            mean_te = sum(world.metrics.tracking_error_path) / len(world.metrics.tracking_error_path)
            self.assertLess(mean_te, 0.01, f"seed {seed}: mean tracking error {mean_te:.4%} too loose for PM alone")


class BasketWithWithoutPmScenarioTest(unittest.TestCase):
    def test_pm_presence_tightens_tracking_across_seeds(self) -> None:
        for seed in range(5):
            world_with = basket_with_without_pm.build_world(with_pm=True, seed=seed)
            world_with.run(300)
            world_without = basket_with_without_pm.build_world(with_pm=False, seed=seed)
            world_without.run(300)

            te_with = sum(world_with.metrics.tracking_error_path) / len(world_with.metrics.tracking_error_path)
            te_without = sum(world_without.metrics.tracking_error_path) / len(world_without.metrics.tracking_error_path)

            self.assertLess(
                te_with, te_without, f"seed {seed}: PM presence should tighten tracking (with={te_with:.4%}, without={te_without:.4%})"
            )

    def test_competitor_never_touches_weth_group_directly(self) -> None:
        # The competitor only ever trades USDC<->USDT (within the stables group) -- WETH's
        # balance should only move if PM itself traded it.
        world = basket_with_without_pm.build_world(with_pm=False, seed=1)
        world.run(300)
        self.assertEqual(world.token_balances["WETH"], 10.0)

    def test_rebalancing_costs_value_under_a_forced_uptrend(self) -> None:
        # A driftless price never systematically favors either arm, but a genuine, forced
        # uptrend should: PM sells WETH as it appreciates past target, so NOT rebalancing
        # (letting the initial WETH balance ride) should end with strictly more total
        # portfolio value -- the standard rebalancing-drag-vs-buy-and-hold result.
        for seed in range(5):
            world_with = basket_with_without_pm.build_world(with_pm=True, weth_drift_per_step=0.0006, seed=seed)
            world_with.run(300)
            world_without = basket_with_without_pm.build_world(with_pm=False, weth_drift_per_step=0.0006, seed=seed)
            world_without.run(300)

            value_with = world_with.metrics.value_a_path[-1] + world_with.metrics.value_b_path[-1]
            value_without = world_without.metrics.value_a_path[-1] + world_without.metrics.value_b_path[-1]

            self.assertLess(
                value_with,
                value_without,
                f"seed {seed}: rebalancing should cost value under a forced uptrend (with={value_with:.0f}, without={value_without:.0f})",
            )


class GuardEnforcementScenarioTest(unittest.TestCase):
    """With PM registered and correcting, a separate "rogue" strategy on the same pair
    should never get a trade through -- PM's own corrections are expected and should NOT
    be blocked."""

    def test_guard_blocks_only_the_rogue_strategy_across_seeds(self) -> None:
        for seed in range(5):
            world = guard_enforcement.build_world(seed=seed)
            world.run(200)

            self.assertGreater(
                len(world.blocked_trades), 0, f"seed {seed}: rogue strategy never attempted a cross-group trade (test is vacuous)"
            )
            self.assertTrue(
                all(t.strategy_id == "rogue" for t in world.blocked_trades),
                f"seed {seed}: something other than the rogue strategy got blocked -- PM's own trades should never be blocked",
            )
            # PM should still be actively correcting -- not itself blocked into inaction.
            self.assertLess(
                sum(world.metrics.tracking_error_path) / len(world.metrics.tracking_error_path),
                0.01,
                f"seed {seed}: PM should still track tight despite the rogue's blocked attempts",
            )


class CrossBasketNoPmScenarioTest(unittest.TestCase):
    """No PM registered -- no Guard, so an unconstrained, fully-connected set of ordinary
    competing strategies CAN move every token, including WETH, unlike
    basket_with_without_pm.py's "without PM" arm (one competitor confined to one pair)."""

    def test_no_trades_blocked_without_pm(self) -> None:
        world = cross_basket_no_pm.build_world(seed=1)
        world.run(300)
        self.assertEqual(world.blocked_trades, [])

    def test_weth_balance_moves_without_any_pm_present(self) -> None:
        # Unlike basket_with_without_pm.py's "without PM" arm, here a competitor is
        # constructed directly on the WETH/USDC and WETH/USDT pairs, so WETH's balance
        # is free to move -- confirming the "no Guard means no confinement" fix.
        world = cross_basket_no_pm.build_world(seed=1)
        initial_weth = world.token_balances["WETH"]
        world.run(300)
        self.assertNotEqual(world.token_balances["WETH"], initial_weth)


if __name__ == "__main__":
    unittest.main()
