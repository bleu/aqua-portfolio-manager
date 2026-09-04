"""Regression tests for the Strategy implementations (BLEUDEV-334 R1/R3/R4)."""

from __future__ import annotations

import unittest

from aqua_sim.basket_world import BasketGroup, BasketWorldView
from aqua_sim.strategies.noise_trader import NoiseTraderStrategy
from aqua_sim.strategies.portfolio_manager import PortfolioManagerStrategy, protocol_fee_bps
from aqua_sim.strategies.stableswap_competitor import StableSwapCompetitorStrategy
from aqua_sim.strategies.xyc_competitor import XYCCompetitorStrategy


class ProtocolFeeBpsTest(unittest.TestCase):
    """1IP-103's tiered formula, mirrored from `PortfolioManagerProgramBuilder.daoFeeBps`."""

    def test_low_tier_is_one_quarter(self) -> None:
        self.assertAlmostEqual(protocol_fee_bps(0.0005), 0.0005 / 4)

    def test_high_tier_is_one_sixth(self) -> None:
        self.assertAlmostEqual(protocol_fee_bps(0.005), 0.005 / 6)

    def test_threshold_itself_is_low_tier(self) -> None:
        self.assertAlmostEqual(protocol_fee_bps(0.001225), 0.001225 / 4)

    def test_just_above_threshold_is_high_tier(self) -> None:
        self.assertAlmostEqual(protocol_fee_bps(0.0012251), 0.0012251 / 6)

    def test_zero_fee_yields_zero(self) -> None:
        self.assertEqual(protocol_fee_bps(0.0), 0.0)


class PortfolioManagerStrategyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.group_a = BasketGroup("A", ("WETH",))
        self.group_b = BasketGroup("B", ("USDC",))
        self.pm = PortfolioManagerStrategy(
            id="pm", token_a="WETH", token_b="USDC", group_a=self.group_a, group_b=self.group_b, target_weight_a=0.5
        )

    def test_no_trade_when_pool_matches_market(self) -> None:
        # Balanced 50/50 at the exact market price -- nothing to correct.
        view = BasketWorldView(
            token_balances={"WETH": 10.0, "USDC": 20_000.0},
            reference_prices={"WETH": 2000.0, "USDC": 1.0},
            groups=[self.group_a, self.group_b],
        )
        self.assertIsNone(self.pm.decide_trade(view))

    def test_corrects_toward_target_when_skewed(self) -> None:
        # Too much WETH relative to target -- the wallet should shed WETH (token_out)
        # and receive USDC (token_in) to correct back toward 50/50.
        view = BasketWorldView(
            token_balances={"WETH": 15.0, "USDC": 20_000.0},
            reference_prices={"WETH": 2000.0, "USDC": 1.0},
            groups=[self.group_a, self.group_b],
        )
        trade = self.pm.decide_trade(view)
        self.assertIsNotNone(trade)
        self.assertEqual(trade.strategy_id, "pm")
        self.assertEqual(trade.token_in, "USDC")
        self.assertEqual(trade.token_out, "WETH")
        self.assertGreater(trade.amount_in, 0)
        self.assertGreater(trade.amount_out, 0)

    def test_protocol_fee_is_a_tiered_fraction_of_the_lp_curve_fee(self) -> None:
        # BLEUDEV-327 / 1IP-103: the protocol fee is not fixed -- it's 1/4 or 1/6 of
        # whatever `self.fee` (the LP's own curve fee) is, not an independent number.
        view = BasketWorldView(
            token_balances={"WETH": 15.0, "USDC": 20_000.0},
            reference_prices={"WETH": 2000.0, "USDC": 1.0},
            groups=[self.group_a, self.group_b],
        )
        pm_low_tier_fee = PortfolioManagerStrategy(
            id="pm", token_a="WETH", token_b="USDC", group_a=self.group_a, group_b=self.group_b,
            target_weight_a=0.5, fee=0.0002,  # 2bps, below the 0.1225% tier threshold
        )
        trade = pm_low_tier_fee.decide_trade(view)
        self.assertIsNotNone(trade)
        self.assertGreater(trade.protocol_fee_amount, 0)
        self.assertAlmostEqual(trade.protocol_fee_amount, trade.amount_in * protocol_fee_bps(0.0002))
        self.assertAlmostEqual(protocol_fee_bps(0.0002), 0.0002 / 4)

    def test_zero_lp_fee_means_zero_protocol_fee(self) -> None:
        view = BasketWorldView(
            token_balances={"WETH": 15.0, "USDC": 20_000.0},
            reference_prices={"WETH": 2000.0, "USDC": 1.0},
            groups=[self.group_a, self.group_b],
        )
        pm_zero_fee = PortfolioManagerStrategy(
            id="pm", token_a="WETH", token_b="USDC", group_a=self.group_a, group_b=self.group_b,
            target_weight_a=0.5, fee=0.0,
        )
        trade = pm_zero_fee.decide_trade(view)
        self.assertIsNotNone(trade)
        self.assertEqual(trade.protocol_fee_amount, 0.0)

    def test_reacts_to_basket_mate_moving_without_pm_trading(self) -> None:
        # A basket-mate (USDT) in the same group as USDC grew -- PM's quote should move
        # even though only WETH/USDC balances are directly PM's own (R5).
        group_stables = BasketGroup("B", ("USDC", "USDT"))
        pm = PortfolioManagerStrategy(
            id="pm", token_a="WETH", token_b="USDC", group_a=self.group_a, group_b=group_stables, target_weight_a=0.5
        )
        balanced_view = BasketWorldView(
            token_balances={"WETH": 10.0, "USDC": 20_000.0, "USDT": 0.0},
            reference_prices={"WETH": 2000.0, "USDC": 1.0, "USDT": 1.0},
            groups=[self.group_a, group_stables],
        )
        self.assertIsNone(pm.decide_trade(balanced_view))

        skewed_by_basket_mate_view = BasketWorldView(
            token_balances={"WETH": 10.0, "USDC": 20_000.0, "USDT": 4_000.0},
            reference_prices={"WETH": 2000.0, "USDC": 1.0, "USDT": 1.0},
            groups=[self.group_a, group_stables],
        )
        trade = pm.decide_trade(skewed_by_basket_mate_view)
        self.assertIsNotNone(trade)
        self.assertEqual(trade.token_in, "WETH")
        self.assertEqual(trade.token_out, "USDC")


class XYCCompetitorStrategyTest(unittest.TestCase):
    def test_corrects_toward_market_rate_when_profitable(self) -> None:
        # Excess USDC relative to USDT -- the pool should shed USDC (token_out) and
        # receive USDT (token_in) to move back toward the 1:1 market rate.
        competitor = XYCCompetitorStrategy(id="c", token_a="USDC", token_b="USDT", fee=0.001, gas_cost=0.01)
        view = BasketWorldView(
            token_balances={"USDC": 12_000.0, "USDT": 8_000.0},
            reference_prices={"USDC": 1.0, "USDT": 1.0},
            groups=[BasketGroup("stables", ("USDC", "USDT"))],
        )
        trade = competitor.decide_trade(view)
        self.assertIsNotNone(trade)
        self.assertEqual(trade.token_in, "USDT")
        self.assertEqual(trade.token_out, "USDC")

    def test_no_trade_when_balanced(self) -> None:
        competitor = XYCCompetitorStrategy(id="c", token_a="USDC", token_b="USDT", fee=0.001, gas_cost=0.01)
        view = BasketWorldView(
            token_balances={"USDC": 10_000.0, "USDT": 10_000.0},
            reference_prices={"USDC": 1.0, "USDT": 1.0},
            groups=[BasketGroup("stables", ("USDC", "USDT"))],
        )
        self.assertIsNone(competitor.decide_trade(view))


class StableSwapCompetitorStrategyTest(unittest.TestCase):
    def test_corrects_toward_market_rate_when_profitable(self) -> None:
        competitor = StableSwapCompetitorStrategy(id="c", token_a="USDC", token_b="USDT", fee=0.0004, gas_cost=0.01)
        view = BasketWorldView(
            token_balances={"USDC": 12_000.0, "USDT": 8_000.0},
            reference_prices={"USDC": 1.0, "USDT": 1.0},
            groups=[BasketGroup("stables", ("USDC", "USDT"))],
        )
        trade = competitor.decide_trade(view)
        self.assertIsNotNone(trade)
        self.assertEqual(trade.token_in, "USDT")
        self.assertEqual(trade.token_out, "USDC")

    def test_no_trade_when_balanced(self) -> None:
        competitor = StableSwapCompetitorStrategy(id="c", token_a="USDC", token_b="USDT", fee=0.0004, gas_cost=0.01)
        view = BasketWorldView(
            token_balances={"USDC": 10_000.0, "USDT": 10_000.0},
            reference_prices={"USDC": 1.0, "USDT": 1.0},
            groups=[BasketGroup("stables", ("USDC", "USDT"))],
        )
        self.assertIsNone(competitor.decide_trade(view))

    def test_smaller_price_impact_than_plain_xyc_for_the_same_trade_size(self) -> None:
        # StableSwap's flatter curve near the peg means a given trade size moves the
        # pool's own price much less than the same trade against a plain constant-product
        # pool -- the actual point of using it for a pegged pair.
        view = BasketWorldView(
            token_balances={"USDC": 11_000.0, "USDT": 9_000.0},
            reference_prices={"USDC": 1.0, "USDT": 1.0},
            groups=[BasketGroup("stables", ("USDC", "USDT"))],
        )
        stable_trade = StableSwapCompetitorStrategy(id="s", token_a="USDC", token_b="USDT", fee=0.0004, gas_cost=0.0).decide_trade(view)
        xyc_trade = XYCCompetitorStrategy(id="x", token_a="USDC", token_b="USDT", fee=0.0004, gas_cost=0.0).decide_trade(view)
        self.assertIsNotNone(stable_trade)
        self.assertIsNotNone(xyc_trade)
        # StableSwap resists the price move harder, so it takes *more* volume to reach
        # the same target rate -- the flatter curve, not a smaller correction, is the point.
        self.assertGreater(stable_trade.amount_in, xyc_trade.amount_in)


class NoiseTraderStrategyTest(unittest.TestCase):
    def test_never_trades_at_zero_arrival_probability(self) -> None:
        trader = NoiseTraderStrategy(id="n", token_a="A", token_b="B", arrival_prob_per_step=0.0, seed=0)
        view = BasketWorldView(
            token_balances={"A": 100.0, "B": 100.0}, reference_prices={"A": 1.0, "B": 1.0}, groups=[]
        )
        for _ in range(50):
            self.assertIsNone(trader.decide_trade(view))

    def test_always_trades_at_full_arrival_probability(self) -> None:
        trader = NoiseTraderStrategy(id="n", token_a="A", token_b="B", arrival_prob_per_step=1.0, seed=0)
        view = BasketWorldView(
            token_balances={"A": 100.0, "B": 100.0}, reference_prices={"A": 1.0, "B": 1.0}, groups=[]
        )
        for _ in range(20):
            trade = trader.decide_trade(view)
            self.assertIsNotNone(trade)
            self.assertGreater(trade.amount_in, 0)
            self.assertGreater(trade.amount_out, 0)


if __name__ == "__main__":
    unittest.main()
