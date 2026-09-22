"""Profit-seeking StableSwap competitor for near-pegged pairs. Subject to the world's group restrictions."""

from __future__ import annotations

from dataclasses import dataclass

from aqua_sim.basket_world import BasketWorldView
from aqua_sim.stableswap import StableSwapState, apply_exact_in, spot_price
from aqua_sim.strategy import Trade

_BISECTION_ITERATIONS = 60
_MAX_TRADE_FRACTION = 0.9  # never propose draining more than this fraction of one side


def _size_correction_trade(state: StableSwapState, target_rate: float, fee: float) -> float:
    """Bisect input size to approach the target price within the solver tolerance."""
    lo = 0.0
    hi = state.balance_in * _MAX_TRADE_FRACTION

    def rate_after(amount_in: float) -> float:
        new_state, _ = apply_exact_in(state, amount_in, fee)
        return spot_price(new_state)

    if rate_after(hi) < target_rate:
        return hi  # even the largest allowed trade doesn't reach parity

    for _ in range(_BISECTION_ITERATIONS):
        mid = (lo + hi) / 2
        if rate_after(mid) < target_rate:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


@dataclass
class StableSwapCompetitorStrategy:
    """Price a fixed pair from private StableSwap reserves.

    Update private reserves from this strategy's own decisions, independently of other strategies.
    Settlement uses the shared wallet. See XYCCompetitorStrategy for the reserve distinction."""

    id: str
    token_a: str
    token_b: str
    virtual_balance_a: float
    virtual_balance_b: float
    amplification: float = 100.0
    fee: float = 0.0004
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
            state = StableSwapState(balance_in, balance_out, self.amplification)

            market_rate = price_out / price_in
            pool_rate = spot_price(state)
            if pool_rate >= market_rate * (1 - self.fee):
                continue

            amount_in = _size_correction_trade(state, market_rate, self.fee)
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
