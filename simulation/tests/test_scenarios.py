"""Scenario-level regression tests — one per BLEUDEV-334 requirement (R1/R5/R6), matching
what each scenarios/ builder is actually for."""

from __future__ import annotations

import unittest

from aqua_sim.scenarios import basket_with_without_pm, guard_enforcement, pm_alone


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


class GuardEnforcementScenarioTest(unittest.TestCase):
    def test_guard_blocks_every_cross_group_attempt_across_seeds(self) -> None:
        for seed in range(5):
            world = guard_enforcement.build_world(seed=seed)
            initial_balances = dict(world.token_balances)
            world.run(200)

            self.assertEqual(
                world.token_balances, initial_balances, f"seed {seed}: guard failed to block a cross-group trade"
            )
            self.assertGreater(
                len(world.blocked_trades), 0, f"seed {seed}: rogue strategy never attempted a cross-group trade (test is vacuous)"
            )


if __name__ == "__main__":
    unittest.main()
