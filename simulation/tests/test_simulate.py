"""Regression test pinning the i/o orientation convention `simulate.py`'s main loop
converts between `market.py`'s `price_a_in_b` and `curve.py`'s `SP(i->o)` -- the exact
convention mismatch that once drove the pool to the reciprocal of fair value (see
`simulate.py`'s inline comment and `simulation/README.md`'s "A bug this work found").
Deliberately run at a price far from 1.0 (2000), since the original bug was masked by
every earlier isolated test happening to use market_price=1.0, its own reciprocal.
"""

from __future__ import annotations

import unittest

import numpy as np

from aqua_sim.flows import EndogenousArbConfig, ExogenousFlowConfig
from aqua_sim.simulate import MechanismSimConfig, run_mechanism_simulation


class ArbOrientationTest(unittest.TestCase):
    def test_arb_converges_toward_target_at_a_price_far_from_one(self) -> None:
        n_steps = 30
        price = 2000.0  # far from 1.0 -- the value that hid the original reciprocal bug

        config = MechanismSimConfig(
            n_steps=n_steps,
            dt_years=1 / (365 * 24 * 60),
            sigma_annual=0.0,
            initial_balance_a=100.0,
            initial_balance_b=100.0,  # value_a=200,000 vs value_b=100 at price=2000 -- badly overweight A
            target_weight_a=0.5,
            exogenous=ExogenousFlowConfig(arrival_rate_per_year=0.0),
            arb=EndogenousArbConfig(fee=0.0002, gas_cost_b=0.10, tolerance_band=0.0, min_steps_between_trades=0),
            seed=0,
            price_path=np.full(n_steps + 1, price),
        )

        result = run_mechanism_simulation(config)

        self.assertGreater(result.n_arb_trades, 0, "arb should have fired at all given a badly overweight start")
        self.assertLess(
            result.tracking_error_path[-1],
            result.tracking_error_path[0] / 10,
            "tracking error should shrink sharply toward target as arb corrects -- if it instead grows or "
            "stays near its start, the arb is very likely being aimed at the reciprocal of the real market price",
        )
        self.assertLess(
            result.tracking_error_path[-1],
            0.05,
            "with continuous arb and no cooldown/tolerance, weights should converge close to target",
        )


if __name__ == "__main__":
    unittest.main()
