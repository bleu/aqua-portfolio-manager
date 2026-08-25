"""Regression tests for the pricing curve, extracted from notebook 01's assertions.

Notebook 01 (`01_pricing_curve.ipynb`) keeps the narrative/plots; these are the same
checks, moved here so they run without a kernel and so the notebook is scenario
analysis, not the only place this math gets verified.
"""

from __future__ import annotations

import random
import unittest

from aqua_sim.curve import (
    CurveState,
    DegenerateBalanceError,
    apply_exact_in,
    donate,
    exact_in,
    invariant,
    spot_price,
)


class ExactInTest(unittest.TestCase):
    def test_equal_weights_reduces_to_plain_xyk(self) -> None:
        state = CurveState(balance_in=100, balance_out=100, weight_in=0.5, weight_out=0.5)
        amount_in = 10.0

        amount_out = exact_in(state, amount_in, fee=0.0)
        xyk_expected = state.balance_out - (state.balance_in * state.balance_out) / (state.balance_in + amount_in)

        self.assertAlmostEqual(amount_out, xyk_expected, places=9)


class SpotPriceTest(unittest.TestCase):
    def test_doubling_weight_in_halves_price(self) -> None:
        s_even = CurveState(balance_in=100, balance_out=100, weight_in=0.5, weight_out=0.5)
        s_skewed = CurveState(balance_in=100, balance_out=100, weight_in=1.0, weight_out=0.5)

        p_even = spot_price(s_even)
        p_skewed = spot_price(s_skewed)

        self.assertAlmostEqual(p_skewed, p_even / 2, places=9)


class InvariantTest(unittest.TestCase):
    def test_never_decreases_across_200k_random_trades(self) -> None:
        rng = random.Random(0)
        violations = []

        for _ in range(200_000):
            b_i = rng.uniform(1, 1_000_000)
            b_o = rng.uniform(1, 1_000_000)
            w_i = rng.uniform(0.01, 0.99)
            w_o = 1 - w_i
            fee = rng.uniform(0, 0.2)
            a_in = rng.uniform(1e-6, b_i * 0.3)

            state = CurveState(b_i, b_o, w_i, w_o)
            v_before = invariant(state)
            try:
                new_state, _ = apply_exact_in(state, a_in, fee)
            except DegenerateBalanceError:
                continue
            v_after = invariant(new_state)

            if v_after < v_before - 1e-6 * max(v_before, 1.0):
                violations.append((b_i, b_o, w_i, w_o, fee, a_in, v_before, v_after))

        self.assertEqual(violations, [], f"{len(violations)} invariant violations found: {violations[:3]}")

    def test_unchanged_at_zero_fee(self) -> None:
        state = CurveState(100, 100, 0.5, 0.5)
        v_before = invariant(state)
        new_state, _ = apply_exact_in(state, 10, fee=0.0)
        v_after = invariant(new_state)

        self.assertAlmostEqual(v_after, v_before, places=6)

    def test_strictly_increases_on_donation(self) -> None:
        state = CurveState(100, 100, 0.5, 0.5)
        v_before = invariant(state)
        donated_state = donate(state, 10, into="in")
        v_after = invariant(donated_state)

        self.assertGreater(v_after, v_before)


if __name__ == "__main__":
    unittest.main()
