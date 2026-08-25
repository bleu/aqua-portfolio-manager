"""Regression tests for basket-aware pricing."""

from __future__ import annotations

import unittest

from aqua_sim.basket import apply_basket_aware_exact_in


class BasketAwareExactInTest(unittest.TestCase):
    def test_rejects_a_quote_that_exceeds_the_real_output_balance(self) -> None:
        """A basket token may influence pricing but cannot be transferred as output."""
        with self.assertRaises(ValueError):
            apply_basket_aware_exact_in(
                balance_in=1.0,
                balance_out=1.0,
                basket_balance=100.0,
                weight_in=0.5,
                weight_out=0.5,
                amount_in=10.0,
                fee=0.0,
            )


if __name__ == "__main__":
    unittest.main()
