"""Scenario-level regression tests, one per scenarios/ builder, matching what each one is
actually for."""

from __future__ import annotations

import unittest

from aqua_sim.scenarios import basket_with_without_pm, cross_basket_no_pm, pm_alone


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
        # (letting the initial WETH balance ride) should end with more total portfolio
        # value on average -- the standard rebalancing-drag-vs-buy-and-hold result. Checked
        # on the mean across seeds, not every individual seed: a seed where WETH ends up
        # nearly flat (k~1) sits right where the effect's size crosses zero, so a single
        # such seed can go either way by a hair without contradicting the aggregate claim.
        total_with, total_without = 0.0, 0.0
        for seed in range(5):
            world_with = basket_with_without_pm.build_world(with_pm=True, weth_drift_per_step=0.0006, seed=seed)
            world_with.run(300)
            world_without = basket_with_without_pm.build_world(with_pm=False, weth_drift_per_step=0.0006, seed=seed)
            world_without.run(300)

            total_with += world_with.metrics.value_a_path[-1] + world_with.metrics.value_b_path[-1]
            total_without += world_without.metrics.value_a_path[-1] + world_without.metrics.value_b_path[-1]

        self.assertLess(
            total_with,
            total_without,
            f"rebalancing should cost value under a forced uptrend on average (with={total_with:.0f}, without={total_without:.0f})",
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
