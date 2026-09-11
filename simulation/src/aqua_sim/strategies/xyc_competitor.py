"""A competing swapVM strategy — plain constant-product (`xyc.py`, swapVM's `XYCSwap`
opcode), profit-seeking against the world's reference prices. Not PM's own strategy:
`GroupBoundaryGuard` never exempts it, so it can only ever trade within one declared
group, same as any other non-PM strategy.
"""

from __future__ import annotations

from dataclasses import dataclass

from aqua_sim.basket_world import BasketWorldView
from aqua_sim.strategy import Trade
from aqua_sim.xyc import XYCState, apply_exact_in, spot_price


@dataclass
class XYCCompetitorStrategy:
    """Quotes and trades one fixed token pair on its own plain `xy=k` pool.

    Prices and sizes off `virtual_balance_a`/`virtual_balance_b` — its own private reserve
    pair, seeded at construction and updated only by this instance's own trades — never
    the shared wallet's real balance. This is what an independent pool actually is: two
    separate `XYCCompetitorStrategy` instances on overlapping pairs (e.g. one on WETH/USDC,
    another on WETH/USDT) must not see or affect each other's reserves, the same way two
    unrelated Uniswap pools don't. PM is the one strategy meant to run on the wallet's real
    balance (`BasketGroup.virtual_balance`); everything else, including this strategy,
    prices off its own private state.

    Settlement is unchanged: a decided trade still moves the real, shared wallet balance
    via `BasketWorld.apply()` — these are still other strategies shipped from the same
    dedicated wallet, so the actual on-chain settlement is real regardless of how a
    strategy privately prices itself. Because this strategy's own reserves aren't
    resynced from the real wallet, they can drift from the real balance over a long run
    (other strategies' settlements move the real balance without updating this instance's
    private view) — the same way an independent pool's own price is whatever its own
    reserves say, decoupled from anything else happening elsewhere. An occasional
    resulting trade can get rejected by `BasketWorld.apply()`'s real-liquidity check; that's
    accepted, not treated as a bug.
    """

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
