"""Real market data — loaded from fixed snapshots in `simulation/data/`, not fetched live.

Every other module in this package works on synthetic or caller-supplied data. This one
loads the one real dataset notebooks 08/09 are grounded in: ~180 days of WETH/USDC/WBTC
daily USD prices from CoinGecko, a snapshot of real Balancer weighted-pool fee/volume/TVL
comparables, and a handful of real 1inch aggregator quotes at different trade sizes — all
captured once (see `data/README.md`) and committed as plain CSVs, not re-fetched on every
run. No network access, no API keys, no dependency on any of that staying up.
"""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"


def _load_price_csv(filename: str) -> tuple[list[str], np.ndarray]:
    dates: list[str] = []
    prices: list[float] = []
    with open(_DATA_DIR / filename, newline="") as f:
        for row in csv.DictReader(f):
            dates.append(row["date"])
            prices.append(float(row["price_usd"]))
    return dates, np.array(prices)


def load_weth_usd_daily() -> tuple[list[str], np.ndarray]:
    return _load_price_csv("weth_usd_daily.csv")


def load_usdc_usd_daily() -> tuple[list[str], np.ndarray]:
    return _load_price_csv("usdc_usd_daily.csv")


def load_wbtc_usd_daily() -> tuple[list[str], np.ndarray]:
    return _load_price_csv("wbtc_usd_daily.csv")


def daily_log_returns(prices: np.ndarray) -> np.ndarray:
    return np.diff(np.log(prices))


def realized_annual_volatility(prices: np.ndarray) -> float:
    """Annualized volatility of daily log returns -- `std(log_returns) * sqrt(365)`."""
    return float(daily_log_returns(prices).std() * np.sqrt(365))


def bootstrap_price_path(
    log_returns: np.ndarray,
    n_steps: int,
    dt_years: float,
    p0: float = 1.0,
    seed: int | None = None,
    include_drift: bool = True,
) -> np.ndarray:
    """Monte Carlo price path built by resampling the REAL daily log returns with
    replacement (a standard bootstrap), instead of assuming a parametric (e.g. Gaussian)
    distribution -- preserves whatever fat tails/skew the real ~180-day history actually
    had.

    `log_returns` are daily (`dt_daily = 1/365` years); a simulation stepping at a finer
    resolution (e.g. 5-minute, `dt_years = 1/(365*24*12)`) needs each daily draw split into
    its drift and volatility components and rescaled separately, the same way `market.py`'s
    `simulate_price_path` builds its own per-step shock: the mean (drift) scales LINEARLY
    with `dt_years` (`daily_mean * dt_years/dt_daily`), the demeaned (volatility) part
    scales with `sqrt(dt_years/dt_daily)` (the standard random-walk variance-scales-with-
    time assumption). Scaling the whole draw by a single `sqrt(dt)` factor -- an earlier,
    wrong version of this function did that -- amplifies the drift by `sqrt(1/dt_ratio)`
    instead of preserving it, compounding to an absurd, unbounded price over a year of
    5-minute steps (caught by scratch-verification: a 70%-vol WETH path landed at 4e10x its
    start). This version reproduces `realized_annual_volatility`'s own
    `std * sqrt(365)` convention exactly, so calibration and simulation agree.

    `include_drift=False` zeroes the resampled realized mean and drives the path off pure
    volatility only -- matching `market.py`'s own driftless GBM convention. A single
    ~180-day window's realized average return is a noisy, period-specific number (this
    window happened to have a strong real recovery rally); baking it in as "the" expected
    return would make whatever's being measured mostly about that one trend rather than
    about volatility-driven divergence, which is what tracking error/cost-of-rebalancing
    is actually meant to isolate. Set `True` only when the analysis specifically wants
    trend included (stated explicitly at the call site either way).
    """
    rng = np.random.default_rng(seed)
    dt_daily = 1 / 365
    ratio = dt_years / dt_daily
    daily_mean = log_returns.mean() if include_drift else 0.0
    demeaned = log_returns - log_returns.mean()
    sampled_demeaned = rng.choice(demeaned, size=n_steps, replace=True)
    step_shocks = daily_mean * ratio + sampled_demeaned * np.sqrt(ratio)
    log_path = np.concatenate(([0.0], np.cumsum(step_shocks)))
    return p0 * np.exp(log_path)


def load_balancer_weth_pools() -> list[dict]:
    """Real, live-captured snapshot of mainnet Balancer v3 weighted pools that include
    WETH -- swap fee, 24h volume, TVL, 24h fee revenue. Real-world fee-tier/volume
    comparable for the fee-recommendation analysis (notebook 09)."""
    with open(_DATA_DIR / "balancer_weth_pools.csv", newline="") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        row["swap_fee"] = float(row["swap_fee"])
        row["volume_24h_usd"] = float(row["volume_24h_usd"])
        row["total_liquidity_usd"] = float(row["total_liquidity_usd"])
        row["fees_24h_usd"] = float(row["fees_24h_usd"])
        row["daily_turnover"] = row["volume_24h_usd"] / row["total_liquidity_usd"] if row["total_liquidity_usd"] > 0 else 0.0
    return rows


def load_1inch_weth_usdc_quotes() -> list[dict]:
    """Real, one-time-captured snapshot of 1inch aggregator quotes for WETH->USDC at
    several trade sizes -- the real market's aggregate price-impact curve, used as the
    competitive benchmark our own pool's quote is compared against (notebook 09)."""
    with open(_DATA_DIR / "oneinch_weth_usdc_quotes.csv", newline="") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        row["weth_in"] = float(row["weth_in"])
        row["usdc_out"] = float(row["usdc_out"])
        row["effective_price_usdc_per_weth"] = float(row["effective_price_usdc_per_weth"])
    return rows


def load_1inch_weth_usdc_routes() -> list[dict]:
    """Real, one-time-captured breakdown of which protocols 1inch actually routed each
    WETH->USDC quote through, and what share of the trade each got -- i.e. who our
    strategy would really be competing against for this order flow, at each size, not a
    generic "the market" abstraction. `part_pct` is that protocol's share of ITS route leg
    (legs run in parallel on split routes, so shares within one `weth_in` size don't
    necessarily sum to 100 -- see notebook 09 for how this is aggregated)."""
    with open(_DATA_DIR / "oneinch_weth_usdc_routes.csv", newline="") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        row["weth_in"] = float(row["weth_in"])
        row["part_pct"] = float(row["part_pct"])
    return rows
