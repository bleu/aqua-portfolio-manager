"""Regression tests for background market noise, extracted from notebook 02's assertions.

Notebook 02 (`02_exogenous_flow.ipynb`) keeps the narrative/plots; these are the same
checks, moved here so they run without a kernel and so the notebook is scenario
analysis, not the only place this math gets verified.
"""

from __future__ import annotations

import unittest

import numpy as np

from aqua_sim.curve import CurveState
from aqua_sim.flows import ExogenousFlowConfig, maybe_exogenous_trade

DT_YEARS = 1 / (365 * 24 * 60)  # 1-minute steps


class ArrivalRateTest(unittest.TestCase):
    def test_trade_count_matches_poisson_expectation_and_state_stays_valid(self) -> None:
        rng = np.random.default_rng(0)
        config = ExogenousFlowConfig(arrival_rate_per_year=365 * 24, mean_size_fraction=0.01)
        state = CurveState(balance_in=10_000, balance_out=10_000, weight_in=0.5, weight_out=0.5)

        n_steps = 200_000
        n_trades = 0

        for _ in range(n_steps):
            state, amount_in, happened = maybe_exogenous_trade(state, DT_YEARS, config, rng)
            if happened:
                n_trades += 1
            self.assertGreater(state.balance_in, 0, "pool state must stay valid throughout")
            self.assertGreater(state.balance_out, 0, "pool state must stay valid throughout")

        expected_trades = config.arrival_rate_per_year * DT_YEARS * n_steps
        self.assertLess(
            abs(n_trades - expected_trades),
            4 * np.sqrt(expected_trades),
            f"{n_trades} trades far outside Poisson noise band around expected {expected_trades:.1f}",
        )

    def test_trade_sizes_stay_within_cap_and_near_configured_mean(self) -> None:
        rng = np.random.default_rng(0)
        config = ExogenousFlowConfig(arrival_rate_per_year=365 * 24, mean_size_fraction=0.01)
        state = CurveState(balance_in=10_000, balance_out=10_000, weight_in=0.5, weight_out=0.5)

        trade_sizes = []
        for _ in range(200_000):
            state, amount_in, happened = maybe_exogenous_trade(state, DT_YEARS, config, rng)
            if happened:
                trade_sizes.append(amount_in)

        self.assertGreater(len(trade_sizes), 100, "need enough samples to check the distribution")
        size_fractions = np.array(trade_sizes) / 10_000
        self.assertTrue(np.all(size_fractions <= 0.5 + 1e-6), "no trade should exceed the 50%-of-balance cap")
        self.assertLess(
            np.median(size_fractions),
            config.mean_size_fraction * 3,
            "median trade size should be in the same order of magnitude as the configured mean",
        )


class DirectionUnbiasedTest(unittest.TestCase):
    def test_mean_log_drift_across_many_walks_is_consistent_with_zero(self) -> None:
        n_realizations = 300
        n_trades_per_walk = 3_000
        config_high_rate = ExogenousFlowConfig(arrival_rate_per_year=365 * 24 * 10, mean_size_fraction=0.005)

        log_drifts = []
        for realization in range(n_realizations):
            rng = np.random.default_rng(1000 + realization)
            state = CurveState(balance_in=10_000, balance_out=10_000, weight_in=0.5, weight_out=0.5)
            trades_done = 0
            while trades_done < n_trades_per_walk:
                state, _, happened = maybe_exogenous_trade(state, DT_YEARS, config_high_rate, rng)
                trades_done += int(happened)
            log_drifts.append(np.log(state.balance_in / 10_000))

        log_drifts = np.array(log_drifts)
        mean_log_drift = log_drifts.mean()
        standard_error = log_drifts.std(ddof=1) / np.sqrt(n_realizations)

        self.assertLess(
            abs(mean_log_drift),
            3 * standard_error,
            f"mean log-drift {mean_log_drift:.4f} is more than 3 standard errors ({standard_error:.4f}) from "
            "zero -- would suggest a real directional bias, not just random-walk noise",
        )


if __name__ == "__main__":
    unittest.main()
