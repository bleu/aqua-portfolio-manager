"""Synthetic market-price paths for the M1 simulation.

No real historical price data has been acquired for this simulation (flagged explicitly,
not hidden — see `simulation/README.md`). Prices are generated as geometric Brownian
motion (GBM), the standard starting point for this kind of scenario analysis: driftless
(mu=0, a fair assumption for a majors/stablecoin pair with no directional view baked in)
and parametrized only by annualized volatility, which is swept across a few regimes
("calm" to "turbulent" crypto conditions) rather than fit to one specific market period.

**Price convention**: the path returned here is `price_a_in_b`, the conventional
"how many units of B is 1 A worth" (e.g. "1 ETH = 2000 USDC" reads as `price_a_in_b =
2000`). This is the SAME convention `metrics.py` and `baselines.py` use throughout. It is
the RECIPROCAL of `curve.py`'s `spot_price`/`SP(i->o)` convention ("units of i paid per
unit of o received") — `flows.py` and `simulate.py` convert between the two explicitly at
the one point they meet; see the comment in `simulate.py`'s main loop.
"""

from __future__ import annotations

import numpy as np


def simulate_price_path(
    n_steps: int,
    dt_years: float,
    sigma_annual: float,
    *,
    p0: float = 1.0,
    seed: int | None = None,
) -> np.ndarray:
    """Simulates a driftless GBM price path of `A per unit of B` (or any single ratio).

    Returns an array of length `n_steps + 1` (including the starting price `p0`), where
    `path[t+1] = path[t] * exp(-0.5*sigma^2*dt + sigma*sqrt(dt)*Z)`, `Z ~ N(0, 1)`.

    `dt_years` is the simulation step size in years (e.g. `1/(365*24*60)` for
    minute-resolution steps); `sigma_annual` is the annualized volatility (e.g. `0.6` for
    60%/year, roughly a "calm" major-crypto regime; `1.5`+ for a turbulent one).
    """
    if n_steps <= 0:
        raise ValueError(f"n_steps must be positive, got {n_steps}")
    if dt_years <= 0:
        raise ValueError(f"dt_years must be positive, got {dt_years}")
    if sigma_annual < 0:
        raise ValueError(f"sigma_annual must be non-negative, got {sigma_annual}")

    rng = np.random.default_rng(seed)
    z = rng.standard_normal(n_steps)
    log_returns = -0.5 * sigma_annual**2 * dt_years + sigma_annual * np.sqrt(dt_years) * z
    log_path = np.concatenate(([0.0], np.cumsum(log_returns)))
    return p0 * np.exp(log_path)


def simulate_jump_diffusion_price_path(
    n_steps: int,
    dt_years: float,
    sigma_annual: float,
    jump_rate_per_year: float,
    jump_mean_log: float = 0.0,
    jump_std_log: float = 0.1,
    *,
    p0: float = 1.0,
    seed: int | None = None,
) -> np.ndarray:
    """Merton jump-diffusion: the same GBM as `simulate_price_path`, plus discrete,
    sudden jumps layered on top — the standard way to add real markets' abrupt,
    discontinuous moves (flash crashes, de-pegs, gap moves) to an otherwise-smooth
    price model, which pure GBM structurally cannot produce (it only ever moves
    continuously, one small step at a time).

    At each step, independently of the usual diffusion, a jump occurs with
    probability `jump_rate_per_year * dt_years` (a Poisson arrival, same style as
    `flows.py`'s trade-arrival logic). When a jump occurs, the price is multiplied by
    `exp(N(jump_mean_log, jump_std_log))` — a log-normal jump size, so the price can
    never jump to zero or negative, but can jump by a large, sudden percentage in
    either direction.

    `jump_mean_log = 0.0` (the default) gives symmetric jump risk — surprises can go
    either way, matching a market with no directional view baked in, same spirit as
    the driftless diffusion. Set `jump_mean_log` negative for a deliberately
    crash-biased stress scenario (e.g. `-0.3` for jumps centered around a 30% drop).
    """
    if jump_rate_per_year < 0:
        raise ValueError(f"jump_rate_per_year must be non-negative, got {jump_rate_per_year}")
    if jump_std_log < 0:
        raise ValueError(f"jump_std_log must be non-negative, got {jump_std_log}")

    rng = np.random.default_rng(seed)
    z = rng.standard_normal(n_steps)
    diffusion_log_returns = -0.5 * sigma_annual**2 * dt_years + sigma_annual * np.sqrt(dt_years) * z

    jump_occurs = rng.random(n_steps) < jump_rate_per_year * dt_years
    jump_sizes = rng.normal(jump_mean_log, jump_std_log, n_steps)
    jump_log_returns = np.where(jump_occurs, jump_sizes, 0.0)

    log_path = np.concatenate(([0.0], np.cumsum(diffusion_log_returns + jump_log_returns)))
    return p0 * np.exp(log_path)


def apply_price_shock(price_path: np.ndarray, shock_start_step: int, shock_log_return: float) -> np.ndarray:
    """Applies one deterministic, instantaneous shock to an existing price path, from
    `shock_start_step` onward — a clean, reproducible way to ask "what happens right
    after a sudden N% move," layered on top of an otherwise-ordinary path, rather than
    relying on a random jump landing where we want it to for a specific stress test.

    `shock_log_return` is the log-return of the shock itself: use `np.log(0.7)` for an
    instant 30% drop, `np.log(1.3)` for an instant 30% rise.
    """
    if not 0 <= shock_start_step < len(price_path):
        raise ValueError(f"shock_start_step {shock_start_step} out of range for a path of length {len(price_path)}")
    shocked = price_path.copy()
    shocked[shock_start_step:] *= np.exp(shock_log_return)
    return shocked
