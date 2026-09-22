"""Synthetic price processes with per-step parameters.

Volatility, drift, and jump probability are not annualized or fitted to market data.
Each next(step) call produces one stateful update."""

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
    """Geometric Brownian motion with per-step log returns.

    log_price[t] = log_price[t-1] + drift_per_step + sigma_per_step * Z, where Z is standard normal.
    Zero drift gives zero expected log return."""

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
    """GBM with Bernoulli jumps at jump_prob_per_step.

    Jump sizes use log-space parameters. Zero jump_mean_log gives symmetric log jumps."""

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
    """Ornstein-Uhlenbeck process in log-price space.

    log_price[t] = log_price[t-1] + kappa * (log(mean_price) - log_price[t-1]) + sigma_per_step * Z.
    kappa in (0, 1] controls reversion speed. One resets to the mean before adding noise."""

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
    """Combine independently seeded token price processes for one BasketWorld."""

    processes: list[PriceProcess]

    def next(self, step: int) -> dict[str, float]:
        prices: dict[str, float] = {}
        for process in self.processes:
            prices.update(process.next(step))
        return prices
