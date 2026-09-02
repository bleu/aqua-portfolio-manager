"""Regression tests for BasketGroup, GroupBoundaryGuard, and BasketWorld.apply
(BLEUDEV-334 R5/R6's actual enforcement logic)."""

from __future__ import annotations

import unittest

from aqua_sim.basket_world import BasketGroup, BasketWorld, BasketWorldView, GroupBoundaryGuard, MetricsRecorder, UnknownTokenError
from aqua_sim.price_process import GBMPriceProcess
from aqua_sim.strategy import Trade

PM_ID = "pm"
OTHER_ID = "other"


class BasketGroupTest(unittest.TestCase):
    def test_virtual_balance_sums_oracle_valued_members(self) -> None:
        group = BasketGroup("stables", ("USDC", "USDT"))
        view = BasketWorldView(
            token_balances={"USDC": 1000.0, "USDT": 500.0},
            reference_prices={"USDC": 1.0, "USDT": 0.98},
            groups=[group],
        )
        self.assertAlmostEqual(group.virtual_balance(view), 1000.0 * 1.0 + 500.0 * 0.98, places=9)

    def test_single_member_group_reduces_to_raw_value(self) -> None:
        group = BasketGroup("weth", ("WETH",))
        view = BasketWorldView(token_balances={"WETH": 10.0}, reference_prices={"WETH": 2000.0}, groups=[group])
        self.assertAlmostEqual(group.virtual_balance(view), 20_000.0, places=9)


class GroupBoundaryGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.group_a = BasketGroup("A", ("TOKEN_A",))
        self.group_b = BasketGroup("B", ("TOKEN_B", "TOKEN_C"))
        self.guard = GroupBoundaryGuard(pm_strategy_id=PM_ID)

    def test_same_group_trade_allowed_for_any_strategy_pm_present_or_not(self) -> None:
        trade = Trade(strategy_id=OTHER_ID, token_in="TOKEN_B", token_out="TOKEN_C", amount_in=1.0, amount_out=1.0)
        self.assertTrue(self.guard.check(trade, [self.group_a, self.group_b], pm_present=True))
        self.assertTrue(self.guard.check(trade, [self.group_a, self.group_b], pm_present=False))

    def test_cross_group_trade_blocked_for_non_pm_strategy_when_pm_present(self) -> None:
        trade = Trade(strategy_id=OTHER_ID, token_in="TOKEN_A", token_out="TOKEN_B", amount_in=1.0, amount_out=1.0)
        self.assertFalse(self.guard.check(trade, [self.group_a, self.group_b], pm_present=True))

    def test_cross_group_trade_allowed_for_pm_strategy(self) -> None:
        trade = Trade(strategy_id=PM_ID, token_in="TOKEN_A", token_out="TOKEN_B", amount_in=1.0, amount_out=1.0)
        self.assertTrue(self.guard.check(trade, [self.group_a, self.group_b], pm_present=True))

    def test_trade_touching_an_undeclared_token_blocked_for_non_pm_strategy_when_pm_present(self) -> None:
        trade = Trade(strategy_id=OTHER_ID, token_in="TOKEN_A", token_out="FOREIGN", amount_in=1.0, amount_out=1.0)
        self.assertFalse(self.guard.check(trade, [self.group_a, self.group_b], pm_present=True))

    def test_cross_group_trade_allowed_for_non_pm_strategy_when_pm_absent(self) -> None:
        # The real BasketScopeGuard.sol is installed on PM's own dedicated wallet -- it
        # only exists because PM operates there. No PM means no Guard, so nothing is
        # confined to a single group.
        trade = Trade(strategy_id=OTHER_ID, token_in="TOKEN_A", token_out="TOKEN_B", amount_in=1.0, amount_out=1.0)
        self.assertTrue(self.guard.check(trade, [self.group_a, self.group_b], pm_present=False))

    def test_trade_touching_an_undeclared_token_allowed_when_pm_absent(self) -> None:
        trade = Trade(strategy_id=OTHER_ID, token_in="TOKEN_A", token_out="FOREIGN", amount_in=1.0, amount_out=1.0)
        self.assertTrue(self.guard.check(trade, [self.group_a, self.group_b], pm_present=False))


class _StubStrategy:
    """A registered strategy that never trades on its own -- just needs an `.id` so
    `BasketWorld.apply` can tell whether PM is present in this world."""

    def __init__(self, id: str) -> None:
        self.id = id

    def decide_trade(self, world):
        return None


class BasketWorldApplyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.group_a = BasketGroup("A", ("TOKEN_A",))
        self.group_b = BasketGroup("B", ("TOKEN_B",))
        self.world = BasketWorld(
            token_balances={"TOKEN_A": 100.0, "TOKEN_B": 100.0},
            groups=[self.group_a, self.group_b],
            strategies=[_StubStrategy(PM_ID)],
            guard=GroupBoundaryGuard(pm_strategy_id=PM_ID),
            price_process=GBMPriceProcess(token_id="TOKEN_A", sigma_per_step=0.0, initial_price=1.0, seed=1),
            metrics=MetricsRecorder(group_a_id="A", group_b_id="B", target_weight_a=0.5),
        )
        self.world.reference_prices = {"TOKEN_A": 1.0, "TOKEN_B": 1.0}

    def test_valid_same_group_trade_moves_balances(self) -> None:
        # A token belongs to exactly one declared group in practice (ADR-0003) -- replace
        # the two single-token groups with one that actually spans both tokens, rather
        # than declaring TOKEN_A/TOKEN_B in two groups at once.
        group_c = BasketGroup("C", ("TOKEN_A", "TOKEN_B"))
        self.world.groups = [group_c]
        trade = Trade(strategy_id=OTHER_ID, token_in="TOKEN_A", token_out="TOKEN_B", amount_in=10.0, amount_out=5.0)
        applied = self.world.apply(trade)
        self.assertTrue(applied)
        self.assertEqual(self.world.token_balances["TOKEN_A"], 110.0)
        self.assertEqual(self.world.token_balances["TOKEN_B"], 95.0)

    def test_blocked_trade_leaves_balances_untouched(self) -> None:
        trade = Trade(strategy_id=OTHER_ID, token_in="TOKEN_A", token_out="TOKEN_B", amount_in=10.0, amount_out=5.0)
        applied = self.world.apply(trade)
        self.assertFalse(applied)
        self.assertEqual(self.world.token_balances, {"TOKEN_A": 100.0, "TOKEN_B": 100.0})
        self.assertEqual(self.world.blocked_trades, [trade])

    def test_cross_group_trade_allowed_when_no_pm_registered(self) -> None:
        # No PM in this world -- the Guard's own reason to exist -- so a non-PM strategy
        # crossing a group boundary is not blocked.
        self.world.strategies = []
        trade = Trade(strategy_id=OTHER_ID, token_in="TOKEN_A", token_out="TOKEN_B", amount_in=10.0, amount_out=5.0)
        applied = self.world.apply(trade)
        self.assertTrue(applied)
        self.assertEqual(self.world.token_balances["TOKEN_A"], 110.0)
        self.assertEqual(self.world.token_balances["TOKEN_B"], 95.0)
        self.assertEqual(self.world.blocked_trades, [])

    def test_insufficient_liquidity_rejected_even_for_pm(self) -> None:
        trade = Trade(strategy_id=PM_ID, token_in="TOKEN_A", token_out="TOKEN_B", amount_in=10.0, amount_out=1000.0)
        applied = self.world.apply(trade)
        self.assertFalse(applied)
        self.assertEqual(self.world.token_balances, {"TOKEN_A": 100.0, "TOKEN_B": 100.0})

    def test_unknown_token_raises(self) -> None:
        trade = Trade(strategy_id=PM_ID, token_in="TOKEN_A", token_out="NONEXISTENT", amount_in=10.0, amount_out=1.0)
        with self.assertRaises(UnknownTokenError):
            self.world.apply(trade)


if __name__ == "__main__":
    unittest.main()
