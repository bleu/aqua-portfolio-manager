"""Organic background flow — Poisson-arrival, random direction, lognormal size, same
shape as the old `flows.ExogenousFlowConfig`/`basket.CoBasketAgentConfig`, ported to the
`Strategy` interface (BLEUDEV-334 A2: kept separate from the profit-seeking competitor
strategies in `xyc_competitor.py`, not merged into them).

Deliberately does not price against any pool's own curve: this models flow that clears at
close to the fair oracle rate (e.g. via an external venue or aggregator) before settling
into the shared wallet, not flow that specifically targets PM's or a competitor's pool.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from aqua_sim.basket_world import BasketWorldView
from aqua_sim.strategy import Trade


@dataclass
class NoiseTraderStrategy:
    id: str
    token_a: str
    token_b: str
    arrival_prob_per_step: float
    mean_size_fraction: float = 0.01
    size_sigma: float = 0.5
    fee: float = 0.0
    seed: int | None = None
    _rng: np.random.Generator = field(init=False, repr=False)

    def __post_init__(self) -> None:
        if not 0 <= self.arrival_prob_per_step <= 1:
            raise ValueError(f"arrival_prob_per_step must be in [0, 1], got {self.arrival_prob_per_step}")
        self._rng = np.random.default_rng(self.seed)

    def decide_trade(self, world: BasketWorldView) -> Trade | None:
        if self._rng.random() >= self.arrival_prob_per_step:
            return None

        token_in, token_out = (self.token_a, self.token_b) if self._rng.random() < 0.5 else (self.token_b, self.token_a)

        size_fraction = self._rng.lognormal(mean=np.log(self.mean_size_fraction), sigma=self.size_sigma)
        size_fraction = min(size_fraction, 0.5)  # cap a single organic trade at 50% of balance_in

        balance_in = world.token_balances[token_in]
        amount_in = balance_in * size_fraction
        if amount_in <= 0:
            return None

        price_in = world.reference_prices[token_in]
        price_out = world.reference_prices[token_out]
        amount_out = amount_in * (price_in / price_out) * (1 - self.fee)

        return Trade(strategy_id=self.id, token_in=token_in, token_out=token_out, amount_in=amount_in, amount_out=amount_out)
