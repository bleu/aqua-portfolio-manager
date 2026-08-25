"""Regression tests for the external-DEX baseline model."""

from __future__ import annotations

import unittest

from aqua_sim.baselines import GenericDexConfig, rebalance_to_target
from aqua_sim.metrics import weight_a


class RebalanceToTargetTest(unittest.TestCase):
    def test_rebalances_to_target_at_non_unit_prices_in_both_directions(self) -> None:
        """The DEX state must be oriented toward the token being sold.

        Price 0.5 needs a B->A swap; price 2 needs an A->B swap.  A price of
        1 is deliberately not used because equal nominal balances hide a
        direction error.
        """
        dex = GenericDexConfig(gas_cost_b=0.0)

        for price_a_in_b in (0.5, 2.0):
            with self.subTest(price_a_in_b=price_a_in_b):
                balance_a, balance_b = rebalance_to_target(
                    balance_a=10_000.0,
                    balance_b=10_000.0,
                    price_a_in_b=price_a_in_b,
                    target_weight_a=0.5,
                    config=dex,
                )

                self.assertAlmostEqual(
                    weight_a(balance_a, balance_b, price_a_in_b),
                    0.5,
                    places=3,
                )


if __name__ == "__main__":
    unittest.main()
