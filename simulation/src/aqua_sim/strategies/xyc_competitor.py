"""A competing swapVM strategy — plain constant-product (`xyc.py`, swapVM's `XYCSwap`
opcode), profit-seeking against the world's reference prices (BLEUDEV-334 R3/R4). Not
PM's own strategy: `GroupBoundaryGuard` never exempts it, so it can only ever trade
within one declared group, same as any other non-PM strategy.
"""

from __future__ import annotations

from dataclasses import dataclass

from aqua_sim.basket_world import BasketWorldView
from aqua_sim.strategy import Trade
from aqua_sim.xyc import XYCState, apply_exact_in, spot_price


@dataclass
class XYCCompetitorStrategy:
    """Quotes and trades one fixed token pair on its own plain `xy=k` pool, sized directly
    off the pair's own raw balances — no group augmentation, since a plain xy=k strategy
    has no concept of an oracle-valued basket, only the two tokens it actually holds.
    """

    id: str
    token_a: str
    token_b: str
    fee: float = 0.003
    gas_cost: float = 0.10

    def decide_trade(self, world: BasketWorldView) -> Trade | None:
        price_a = world.reference_prices[self.token_a]
        price_b = world.reference_prices[self.token_b]

        candidates = [
            (self.token_a, self.token_b, price_a, price_b),
            (self.token_b, self.token_a, price_b, price_a),
        ]
        for token_in, token_out, price_in, price_out in candidates:
            balance_in = world.token_balances[token_in]
            balance_out = world.token_balances[token_out]
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

            return Trade(strategy_id=self.id, token_in=token_in, token_out=token_out, amount_in=amount_in, amount_out=amount_out)

        return None
