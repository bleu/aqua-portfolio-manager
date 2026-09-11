"""A competing strategy specialized for near-pegged pairs (e.g. USDC/USDT) — Curve-style
StableSwap (`stableswap.py`) instead of the plain constant-product `xyc.py` used for
unrelated-asset pairs. Not PM's own strategy: `GroupBoundaryGuard` never exempts it, same
confinement as `XYCCompetitorStrategy`.

Used by `scenarios/basket_with_without_pm.py`'s stables competitor (`COMPETITOR_ID`) — a
plain constant-product pool is a poor fit for two tokens meant to trade near parity, real
slippage even for small trades near the peg.
"""

from __future__ import annotations

from dataclasses import dataclass

from aqua_sim.basket_world import BasketWorldView
from aqua_sim.stableswap import StableSwapState, apply_exact_in, spot_price
from aqua_sim.strategy import Trade

_BISECTION_ITERATIONS = 60
_MAX_TRADE_FRACTION = 0.9  # never propose draining more than this fraction of one side


def _size_correction_trade(state: StableSwapState, target_rate: float, fee: float) -> float:
    """StableSwap has no closed-form "target balance for a given price" solve like
    `xyc.py`'s `sqrt(k * rate)` shortcut — bisects on `amount_in` instead, the same
    tolerance-driven approach a real arbitrageur uses against a curve with no closed
    form. Pool rate is monotonically increasing in `amount_in`, so bisection is exact.
    """
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
    """Quotes and trades one fixed near-pegged pair on its own StableSwap pool.

    Prices and sizes off `virtual_balance_a`/`virtual_balance_b` — its own private reserve
    pair, seeded at construction and updated only by this instance's own trades — never
    the shared wallet's real balance, same rationale as `XYCCompetitorStrategy` (see its
    docstring for the full reasoning: independent pools don't share reserves, PM is the
    one strategy meant to run on the wallet's real balance, settlement is unchanged).
    `amplification=100` and `fee=0.0004` (4bps) match Curve's typical parameters for a
    deep stablecoin pool.
    """

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
