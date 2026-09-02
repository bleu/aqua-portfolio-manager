"""Regression tests for the StableSwap curve, mirroring test_xyc.py's style."""

from __future__ import annotations

import random
import unittest

from aqua_sim.stableswap import DegenerateBalanceError, StableSwapState, apply_exact_in, invariant_d, spot_price
from aqua_sim.xyc import XYCState, exact_in as xyc_exact_in


class SpotPriceTest(unittest.TestCase):
    def test_balanced_pool_prices_at_parity(self) -> None:
        state = StableSwapState(10_000, 10_000, amplification=100)
        self.assertAlmostEqual(spot_price(state), 1.0, places=4)

    def test_skewed_pool_stays_much_flatter_than_plain_xyk(self) -> None:
        state = StableSwapState(12_000, 8_000, amplification=100)
        self.assertLess(spot_price(state), 1.01, "StableSwap should barely move off parity at a 60/40 skew")


class ExactInTest(unittest.TestCase):
    def test_near_peg_trade_has_far_less_slippage_than_plain_xyk(self) -> None:
        state = StableSwapState(10_000, 10_000, amplification=100)
        amount_out = apply_exact_in(state, 100, fee=0.0)[1]

        xyk_state = XYCState(10_000, 10_000)
        xyk_out = xyc_exact_in(xyk_state, 100, fee=0.0)

        self.assertGreater(amount_out, xyk_out, "StableSwap should return noticeably more than plain xy=k near the peg")
        self.assertAlmostEqual(amount_out, 100, delta=1.0)


class DegenerateBalanceTest(unittest.TestCase):
    def test_zero_balance_rejects_trade(self) -> None:
        with self.assertRaises(DegenerateBalanceError):
            StableSwapState(0, 100, amplification=100)

    def test_non_positive_amplification_rejects(self) -> None:
        with self.assertRaises(ValueError):
            StableSwapState(100, 100, amplification=0)


class InvariantTest(unittest.TestCase):
    def test_d_never_decreases_across_random_fee_paying_trades(self) -> None:
        rng = random.Random(0)
        violations = []

        for _ in range(2_000):
            b_i = rng.uniform(100, 1_000_000)
            b_o = rng.uniform(100, 1_000_000)
            amp = rng.uniform(1, 500)
            fee = rng.uniform(0, 0.01)
            a_in = rng.uniform(1e-3, b_i * 0.3)

            state = StableSwapState(b_i, b_o, amp)
            d_before = invariant_d(state.balance_in, state.balance_out, state.amplification)
            try:
                new_state, _ = apply_exact_in(state, a_in, fee)
            except DegenerateBalanceError:
                continue
            d_after = invariant_d(new_state.balance_in, new_state.balance_out, new_state.amplification)

            if d_after < d_before - 1e-6 * max(d_before, 1.0):
                violations.append((b_i, b_o, amp, fee, a_in, d_before, d_after))

        self.assertEqual(violations, [], f"{len(violations)} invariant violations found: {violations[:3]}")

    def test_unchanged_at_zero_fee(self) -> None:
        state = StableSwapState(10_000, 10_000, amplification=100)
        d_before = invariant_d(state.balance_in, state.balance_out, state.amplification)
        new_state, _ = apply_exact_in(state, 500, fee=0.0)
        d_after = invariant_d(new_state.balance_in, new_state.balance_out, new_state.amplification)

        self.assertAlmostEqual(d_after, d_before, places=4)


if __name__ == "__main__":
    unittest.main()
