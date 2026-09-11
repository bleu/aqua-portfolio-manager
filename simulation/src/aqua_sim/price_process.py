"""Synthetic-only price generation for the basket world.

No historical or live market data anywhere in this module: every price path is a random
process, parametrized by volatility/drift/jump rate directly, never fit to a specific
real dataset. Also step-based, not calendar-based: every parameter here is "per step", not
"per year" — a step's real-world meaning (e.g. "5 minutes") is a label a caller can attach
for reporting, never something this module's math depends on.

Each `PriceProcess` is stateful and step-wise, not a pre-vectorized whole-path array:
`BasketWorld.step()` calls `next(step)` once per step, which matters here because
strategies need to see each step's price before the next one exists — there's no "the
rest of the path" to peek at.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

import numpy as np


class PriceProcess(Protocol):
    """Produces one token's (or a fixed set of tokens') numeraire-denominated price per
    step. Implementations: `GBMPriceProcess`, `JumpDiffusionPriceProcess`,
    `CompositePriceProcess` (combines several single-token processes into one)."""

    def next(self, step: int) -> dict[str, float]:
        """Advances the process by one step and returns every tracked token's new
        price. Stateful — calling this twice for the same `step` produces two
        different draws, same as any other RNG-backed generator."""
        ...


@dataclass
class GBMPriceProcess:
    """Geometric Brownian motion for a single token, denominated in some numeraire.

    `sigma_per_step` / `drift_per_step` are the step-level volatility and drift of the
    log-return — no annualization, no calendar unit. `log_path[t] = log_path[t-1] +
    drift_per_step + sigma_per_step * Z`, `Z ~ N(0, 1)`; `drift_per_step = 0.0` (the
    default) is the standard driftless assumption for a scenario sweep with no
    directional view baked in (same rationale `market.py` used).
    """

    token_id: str
    sigma_per_step: float
    initial_price: float
    drift_per_step: float = 0.0
    seed: int | None = None
    _rng: np.random.Generator = field(init=False, repr=False)
    _price: float = field(init=False, repr=False)

    def __post_init__(self) -> None:
        if self.sigma_per_step < 0:
            raise ValueError(f"sigma_per_step must be non-negative, got {self.sigma_per_step}")
        if self.initial_price <= 0:
            raise ValueError(f"initial_price must be positive, got {self.initial_price}")
        self._rng = np.random.default_rng(self.seed)
        self._price = self.initial_price

    def next(self, step: int) -> dict[str, float]:
        z = self._rng.standard_normal()
        log_return = self.drift_per_step - 0.5 * self.sigma_per_step**2 + self.sigma_per_step * z
        self._price *= np.exp(log_return)
        return {self.token_id: self._price}


@dataclass
class JumpDiffusionPriceProcess:
    """`GBMPriceProcess` plus discrete, sudden jumps (Merton-style) — the standard way to
    add abrupt, discontinuous moves (flash crashes, de-pegs, gap moves) that pure GBM
    structurally cannot produce.

    `jump_prob_per_step` is the per-step probability of a jump (a Bernoulli draw, not an
    annualized rate — no `dt` conversion needed since this is already step-based).
    `jump_mean_log = 0.0` (the default) gives symmetric jump risk; set negative for a
    deliberately crash-biased stress scenario.
    """

    token_id: str
    sigma_per_step: float
    jump_prob_per_step: float
    initial_price: float
    drift_per_step: float = 0.0
    jump_mean_log: float = 0.0
    jump_std_log: float = 0.1
    seed: int | None = None
    _rng: np.random.Generator = field(init=False, repr=False)
    _price: float = field(init=False, repr=False)

    def __post_init__(self) -> None:
        if self.sigma_per_step < 0:
            raise ValueError(f"sigma_per_step must be non-negative, got {self.sigma_per_step}")
        if not 0 <= self.jump_prob_per_step <= 1:
            raise ValueError(f"jump_prob_per_step must be in [0, 1], got {self.jump_prob_per_step}")
        if self.jump_std_log < 0:
            raise ValueError(f"jump_std_log must be non-negative, got {self.jump_std_log}")
        if self.initial_price <= 0:
            raise ValueError(f"initial_price must be positive, got {self.initial_price}")
        self._rng = np.random.default_rng(self.seed)
        self._price = self.initial_price

    def next(self, step: int) -> dict[str, float]:
        z = self._rng.standard_normal()
        diffusion_log_return = self.drift_per_step - 0.5 * self.sigma_per_step**2 + self.sigma_per_step * z

        jump_log_return = 0.0
        if self._rng.random() < self.jump_prob_per_step:
            jump_log_return = self._rng.normal(self.jump_mean_log, self.jump_std_log)

        self._price *= np.exp(diffusion_log_return + jump_log_return)
        return {self.token_id: self._price}


@dataclass
class MeanRevertingPriceProcess:
    """Ornstein-Uhlenbeck in log-price space: pulls the price back toward a long-run
    anchor instead of letting it wander or trend indefinitely (`GBMPriceProcess`).
    `log_price[t] = log_price[t-1] + kappa * (log(mean_price) - log_price[t-1]) +
    sigma_per_step * Z`.

    Exists specifically to demonstrate the flip side of a persistent trend: constant-mix
    rebalancing (what PM does) systematically loses to buy-and-hold under a one-directional
    GBM drift (see `02_basket_with_without_pm.ipynb`'s forced-uptrend/downtrend sections),
    but recovers its edge -- capturing fee revenue on genuine round-trip volatility,
    directly connected to `DONATION-RESISTANCE-PROOF.md`'s invariant never decreasing on a
    round trip -- once the price actually reverts instead of trending forever.

    `kappa` is the per-step mean-reversion speed, in `(0, 1]`: `1.0` snaps fully back to
    `mean_price` every step (pure noise around a fixed level), values near `0` revert very
    slowly (close to a random walk over any short window).
    """

    token_id: str
    sigma_per_step: float
    mean_price: float
    kappa: float
    initial_price: float
    seed: int | None = None
    _rng: np.random.Generator = field(init=False, repr=False)
    _log_price: float = field(init=False, repr=False)
    _log_mean: float = field(init=False, repr=False)

    def __post_init__(self) -> None:
        if self.sigma_per_step < 0:
            raise ValueError(f"sigma_per_step must be non-negative, got {self.sigma_per_step}")
        if not 0 < self.kappa <= 1:
            raise ValueError(f"kappa must be in (0, 1], got {self.kappa}")
        if self.mean_price <= 0:
            raise ValueError(f"mean_price must be positive, got {self.mean_price}")
        if self.initial_price <= 0:
            raise ValueError(f"initial_price must be positive, got {self.initial_price}")
        self._rng = np.random.default_rng(self.seed)
        self._log_price = np.log(self.initial_price)
        self._log_mean = np.log(self.mean_price)

    def next(self, step: int) -> dict[str, float]:
        z = self._rng.standard_normal()
        self._log_price += self.kappa * (self._log_mean - self._log_price) + self.sigma_per_step * z
        return {self.token_id: np.exp(self._log_price)}


@dataclass
class CompositePriceProcess:
    """Combines several single-token `PriceProcess`es (each independently seeded) into
    one, so `BasketWorld` only needs to hold a single `price_process` regardless of how
    many tokens the basket world tracks."""

    processes: list[PriceProcess]

    def next(self, step: int) -> dict[str, float]:
        prices: dict[str, float] = {}
        for process in self.processes:
            prices.update(process.next(step))
        return prices
