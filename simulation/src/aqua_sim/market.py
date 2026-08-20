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
