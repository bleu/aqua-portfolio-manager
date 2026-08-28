"""Regression tests for basket-aware pricing."""

from __future__ import annotations

import unittest

from aqua_sim.basket import StalePriceError, apply_basket_aware_exact_in, basket_aware_spot_price


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


class BasketPriceConversionTest(unittest.TestCase):
    def test_a_basket_mate_priced_below_parity_augments_by_less_than_its_raw_balance(self) -> None:
        """USDC + EURC: if the basket token (EURC) is worth 0.9 of balance_out's own token
        (USDC), 100 EURC must augment balance_out by 90, not by 100 -- catches the exact
        currency-parity assumption raw balance addition made silently."""
        price_at_parity = basket_aware_spot_price(
            balance_in=1_000.0, balance_out=1_000.0, basket_balance=100.0, weight_in=0.5, weight_out=0.5,
            basket_price_in_out=1.0,
        )
        price_below_parity = basket_aware_spot_price(
            balance_in=1_000.0, balance_out=1_000.0, basket_balance=100.0, weight_in=0.5, weight_out=0.5,
            basket_price_in_out=0.9,
        )
        # A cheaper basket token augments balance_out by less, so SP(i->o) -- units of "in"
        # paid per unit of "out" received -- must be HIGHER (out is scarcer in effective terms).
        self.assertGreater(price_below_parity, price_at_parity)

    def test_default_price_of_one_reproduces_raw_addition_for_equal_value_tokens(self) -> None:
        """Two USD stablecoins (basket_price_in_out=1.0, the default): behavior must match
        the old raw-balance-addition special case exactly."""
        price_default = basket_aware_spot_price(
            balance_in=1_000.0, balance_out=1_000.0, basket_balance=100.0, weight_in=0.5, weight_out=0.5,
        )
        price_explicit_parity = basket_aware_spot_price(
            balance_in=1_000.0, balance_out=1_000.0, basket_balance=100.0, weight_in=0.5, weight_out=0.5,
            basket_price_in_out=1.0,
        )
        self.assertEqual(price_default, price_explicit_parity)

    def test_stale_basket_price_rejects_the_trade(self) -> None:
        """ADR-0005: a stale oracle read rejects the trade outright, not a fallback price."""
        with self.assertRaises(StalePriceError):
            apply_basket_aware_exact_in(
                balance_in=1_000.0,
                balance_out=1_000.0,
                basket_balance=100.0,
                weight_in=0.5,
                weight_out=0.5,
                amount_in=10.0,
                fee=0.0,
                basket_price_is_stale=True,
            )


if __name__ == "__main__":
    unittest.main()
