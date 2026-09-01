"""Regression tests for the synthetic-only price processes (BLEUDEV-334 R2)."""

from __future__ import annotations

import unittest

import numpy as np

from aqua_sim.price_process import CompositePriceProcess, GBMPriceProcess, JumpDiffusionPriceProcess, MeanRevertingPriceProcess


class GBMPriceProcessTest(unittest.TestCase):
    def test_deterministic_with_seed(self) -> None:
        a = GBMPriceProcess(token_id="X", sigma_per_step=0.02, initial_price=100.0, seed=42)
        b = GBMPriceProcess(token_id="X", sigma_per_step=0.02, initial_price=100.0, seed=42)

        path_a = [a.next(t)["X"] for t in range(1, 51)]
        path_b = [b.next(t)["X"] for t in range(1, 51)]

        self.assertEqual(path_a, path_b)

    def test_price_always_positive(self) -> None:
        process = GBMPriceProcess(token_id="X", sigma_per_step=0.5, initial_price=100.0, seed=1)
        for t in range(1, 1001):
            price = process.next(t)["X"]
            self.assertGreater(price, 0)

    def test_zero_volatility_holds_price_constant_except_for_drift(self) -> None:
        process = GBMPriceProcess(token_id="X", sigma_per_step=0.0, initial_price=100.0, drift_per_step=0.0, seed=1)
        for t in range(1, 11):
            price = process.next(t)["X"]
        self.assertAlmostEqual(price, 100.0, places=9)


class JumpDiffusionPriceProcessTest(unittest.TestCase):
    def test_zero_jump_probability_matches_manual_diffusion_replication(self) -> None:
        # JumpDiffusionPriceProcess draws an extra random() each step (the jump-occurrence
        # check) even when jump_prob_per_step=0, so its RNG stream diverges from a plain
        # GBMPriceProcess seeded the same -- that's expected, not a bug (the two classes
        # consume their shared-seed RNG differently). Replicate the exact draw sequence
        # by hand instead, to confirm the diffusion math itself is right when jumps never
        # fire.
        rng = np.random.default_rng(7)
        sigma = 0.02
        price = 100.0
        expected = []
        for _ in range(1, 101):
            z = rng.standard_normal()
            log_return = -0.5 * sigma**2 + sigma * z
            _ = rng.random()  # the jump-occurrence draw, always made, never fires here
            price *= np.exp(log_return)
            expected.append(price)

        jump = JumpDiffusionPriceProcess(token_id="X", sigma_per_step=sigma, jump_prob_per_step=0.0, initial_price=100.0, seed=7)
        actual = [jump.next(t)["X"] for t in range(1, 101)]

        for e, a in zip(expected, actual):
            self.assertAlmostEqual(e, a, places=9)

    def test_high_jump_probability_produces_larger_moves_than_pure_gbm(self) -> None:
        gbm = GBMPriceProcess(token_id="X", sigma_per_step=0.01, initial_price=100.0, seed=3)
        jump = JumpDiffusionPriceProcess(
            token_id="X", sigma_per_step=0.01, jump_prob_per_step=0.5, jump_std_log=0.2, initial_price=100.0, seed=3
        )

        gbm_returns = []
        prev = 100.0
        for t in range(1, 501):
            price = gbm.next(t)["X"]
            gbm_returns.append(abs(price / prev - 1))
            prev = price

        jump_returns = []
        prev = 100.0
        for t in range(1, 501):
            price = jump.next(t)["X"]
            jump_returns.append(abs(price / prev - 1))
            prev = price

        self.assertGreater(max(jump_returns), max(gbm_returns))


class MeanRevertingPriceProcessTest(unittest.TestCase):
    def test_price_always_positive(self) -> None:
        process = MeanRevertingPriceProcess(
            token_id="X", sigma_per_step=0.05, mean_price=100.0, kappa=0.05, initial_price=100.0, seed=1
        )
        for t in range(1, 1001):
            price = process.next(t)["X"]
            self.assertGreater(price, 0)

    def test_reverts_toward_mean_from_a_displaced_start(self) -> None:
        process = MeanRevertingPriceProcess(
            token_id="X", sigma_per_step=0.0, mean_price=100.0, kappa=0.1, initial_price=200.0, seed=1
        )
        prices = [process.next(t)["X"] for t in range(1, 101)]
        # Zero volatility -- purely deterministic decay toward the mean, monotonic.
        self.assertTrue(all(a > b for a, b in zip(prices, prices[1:])))
        self.assertLess(abs(prices[-1] - 100.0), abs(prices[0] - 100.0))

    def test_kappa_one_snaps_fully_to_mean_every_step(self) -> None:
        process = MeanRevertingPriceProcess(
            token_id="X", sigma_per_step=0.0, mean_price=100.0, kappa=1.0, initial_price=50.0, seed=1
        )
        price = process.next(1)["X"]
        self.assertAlmostEqual(price, 100.0, places=9)

    def test_stays_much_closer_to_mean_than_gbm_over_a_long_run(self) -> None:
        gbm = GBMPriceProcess(token_id="X", sigma_per_step=0.02, initial_price=100.0, seed=5)
        reverting = MeanRevertingPriceProcess(
            token_id="X", sigma_per_step=0.02, mean_price=100.0, kappa=0.05, initial_price=100.0, seed=5
        )

        gbm_final = None
        reverting_final = None
        for t in range(1, 2001):
            gbm_final = gbm.next(t)["X"]
            reverting_final = reverting.next(t)["X"]

        self.assertLess(abs(reverting_final - 100.0), abs(gbm_final - 100.0))


class CompositePriceProcessTest(unittest.TestCase):
    def test_combines_multiple_single_token_processes(self) -> None:
        composite = CompositePriceProcess(
            [
                GBMPriceProcess(token_id="A", sigma_per_step=0.01, initial_price=100.0, seed=1),
                GBMPriceProcess(token_id="B", sigma_per_step=0.01, initial_price=1.0, seed=2),
            ]
        )
        prices = composite.next(1)
        self.assertIn("A", prices)
        self.assertIn("B", prices)


if __name__ == "__main__":
    unittest.main()
