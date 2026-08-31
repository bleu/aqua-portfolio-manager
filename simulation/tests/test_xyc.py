"""Regression tests for the plain constant-product curve, mirroring test_curve.py's style."""

from __future__ import annotations

import random
import unittest

from aqua_sim.xyc import DegenerateBalanceError, XYCState, apply_exact_in, invariant, spot_price


class ExactInTest(unittest.TestCase):
    def test_matches_plain_xyk_formula(self) -> None:
        state = XYCState(balance_in=100, balance_out=100)
        amount_in = 10.0

        amount_out = apply_exact_in(state, amount_in, fee=0.0)[1]
        xyk_expected = state.balance_out - (state.balance_in * state.balance_out) / (state.balance_in + amount_in)

        self.assertAlmostEqual(amount_out, xyk_expected, places=9)


class SpotPriceTest(unittest.TestCase):
    def test_matches_ratio_of_balances(self) -> None:
        state = XYCState(balance_in=200, balance_out=100)
        self.assertAlmostEqual(spot_price(state), 2.0, places=9)


class DegenerateBalanceTest(unittest.TestCase):
    def test_zero_balance_in_rejects_trade(self) -> None:
        with self.assertRaises(DegenerateBalanceError):
            XYCState(balance_in=0, balance_out=100)

    def test_zero_balance_out_rejects_trade(self) -> None:
        with self.assertRaises(DegenerateBalanceError):
            XYCState(balance_in=100, balance_out=0)


class InvariantTest(unittest.TestCase):
    def test_never_decreases_across_random_trades(self) -> None:
        rng = random.Random(0)
        violations = []

        for _ in range(50_000):
            b_i = rng.uniform(1, 1_000_000)
            b_o = rng.uniform(1, 1_000_000)
            fee = rng.uniform(0, 0.2)
            a_in = rng.uniform(1e-6, b_i * 0.3)

            state = XYCState(b_i, b_o)
            v_before = invariant(state)
            try:
                new_state, _ = apply_exact_in(state, a_in, fee)
            except DegenerateBalanceError:
                continue
            v_after = invariant(new_state)

            if v_after < v_before - 1e-6 * max(v_before, 1.0):
                violations.append((b_i, b_o, fee, a_in, v_before, v_after))

        self.assertEqual(violations, [], f"{len(violations)} invariant violations found: {violations[:3]}")

    def test_unchanged_at_zero_fee(self) -> None:
        state = XYCState(100, 100)
        v_before = invariant(state)
        new_state, _ = apply_exact_in(state, 10, fee=0.0)
        v_after = invariant(new_state)

        self.assertAlmostEqual(v_after, v_before, places=6)


if __name__ == "__main__":
    unittest.main()
