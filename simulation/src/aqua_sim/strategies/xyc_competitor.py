"""Profit-seeking constant-product competitor, subject to the world's group restrictions."""

from __future__ import annotations

from dataclasses import dataclass

from aqua_sim.basket_world import BasketWorldView
from aqua_sim.strategy import Trade
from aqua_sim.xyc import XYCState, apply_exact_in, spot_price


@dataclass
class XYCCompetitorStrategy:
    """Price a fixed pair from private xy=k reserves.

    Other strategies do not update these reserves, but settlement uses the shared wallet.
    Private reserves can diverge from available wallet balances.
    BasketWorld.apply may reject a proposed trade for insufficient real liquidity."""

    id: str
    token_a: str
    token_b: str
    virtual_balance_a: float
    virtual_balance_b: float
    fee: float = 0.003
    gas_cost: float = 0.10

    def decide_trade(self, world: BasketWorldView) -> Trade | None:
        price_a = world.reference_prices[self.token_a]
        price_b = world.reference_prices[self.token_b]

        candidates = [
            (self.token_a, self.token_b, price_a, price_b, True),
            (self.token_b, self.token_a, price_b, price_a, False),
        ]
        for token_in, token_out, price_in, price_out, in_is_a in candidates:
            balance_in = self.virtual_balance_a if in_is_a else self.virtual_balance_b
            balance_out = self.virtual_balance_b if in_is_a else self.virtual_balance_a
            state = XYCState(balance_in, balance_out)

            market_rate = price_out / price_in
            pool_rate = spot_price(state)
            if pool_rate >= market_rate * (1 - self.fee):
                continue

            k = balance_in * balance_out
            target_balance_in = (k * market_rate) ** 0.5
            amount_in = target_balance_in - balance_in
            if amount_in <= 0:
                continue

            _, amount_out = apply_exact_in(state, amount_in, self.fee)
            profit_in_value = (amount_out * price_out) - (amount_in * price_in)
            if profit_in_value < self.gas_cost:
                continue

            if in_is_a:
                self.virtual_balance_a += amount_in
                self.virtual_balance_b -= amount_out
            else:
                self.virtual_balance_b += amount_in
                self.virtual_balance_a -= amount_out

            return Trade(strategy_id=self.id, token_in=token_in, token_out=token_out, amount_in=amount_in, amount_out=amount_out)

        return None
