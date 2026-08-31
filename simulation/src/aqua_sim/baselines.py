"""The two naive baselines ADR-0008 requires the mechanism to beat.

Both baselines trade the LP's own held balances (not a pool the LP is the maker of)
against a "generic DEX" — modeled as a deep, external constant-mean pool (reusing
`curve.py`'s own machinery at equal weights, i.e. plain `xy=k`) so both fee and
price-impact/slippage come from one real formula rather than a hand-fit approximation.
The LP is the *taker* in both baselines, unlike the mechanism itself.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from aqua_sim.curve import CurveState, exact_in
from aqua_sim.market import simulate_price_path
from aqua_sim.metrics import cost_of_rebalancing, frictionless_reference_path, portfolio_value, tracking_error


@dataclass(frozen=True)
class GenericDexConfig:
    """A deep, external market the LP rebalances against.

    `fee` — 30 bps, a typical constant-product DEX fee (Uniswap v2-style), deliberately
    higher than this strategy's own 2 bps (ADR-0008) — a generic DEX has no reason to
    charge this strategy's own rate.
    `depth_b` — both sides of the external pool, in B-numeraire terms; large relative to
    a single LP's rebalance size so slippage stays realistic-but-modest, matching a
    real deep venue rather than a thin one.
    `gas_cost_b` — a flat per-transaction gas cost, in B-numeraire units, based on real
    observed L2 costs (not benchmarked against this specific contract, which doesn't
    exist yet — `BLEUDEV-265` is still open, and no specific launch chain is locked in
    yet either — ADR-0009): a typical L2 DEX swap runs $0.01-$0.10 total (L2 execution +
    L1 data fee), with multi-hop/more-complex swaps around $0.075 (OpenLiquid, a
    representative L2's gas-fee breakdown, Q1 2026 data). $0.10 rounds up from that
    range with margin for this being a curve-math interaction, not a plain swap —
    revisit once the real contract's gas usage is benchmarked.
    """

    fee: float = 0.003
    depth_b: float = 10_000_000.0
    gas_cost_b: float = 0.10


def _external_dex_state(price_a_in_b: float, config: GenericDexConfig) -> CurveState:
    """A fresh, deep xy=k pool priced at exactly `price_a_in_b`, sized by `depth_b`."""
    balance_b = config.depth_b
    balance_a = config.depth_b / price_a_in_b
    return CurveState(balance_in=balance_a, balance_out=balance_b, weight_in=0.5, weight_out=0.5)


def rebalance_to_target(
    balance_a: float,
    balance_b: float,
    price_a_in_b: float,
    target_weight_a: float,
    config: GenericDexConfig,
) -> tuple[float, float]:
    """Executes one rebalancing trade against the external DEX, sizing it to bring A's
    value-weight to `target_weight_a` at the current market price (before this trade's
    own slippage — a real rebalance, like a real trader's, doesn't perfectly land on
    target once its own price impact is accounted for, and neither does this one).

    Also deducts `config.gas_cost_b` from the B balance, modeling the LP paying gas for
    their own transaction (unlike the mechanism itself, where corrective trades are
    submitted — and gas-paid — by an arbitrageur, not the LP).

    Returns the new `(balance_a, balance_b)`.
    """
    current_value = balance_a * price_a_in_b + balance_b
    target_value_a = target_weight_a * current_value
    delta_value_a = target_value_a - balance_a * price_a_in_b

    if abs(delta_value_a) < 1e-12:
        return balance_a, balance_b - config.gas_cost_b

    dex = _external_dex_state(price_a_in_b, config)

    if delta_value_a > 0:
        # Need more A: sell B for A. `dex` is oriented A-in/B-out (see
        # _external_dex_state), so this direction needs the flipped pair.
        amount_b_in = delta_value_a
        flipped = CurveState(dex.balance_out, dex.balance_in, dex.weight_out, dex.weight_in)
        amount_a_out = exact_in(flipped, amount_b_in, config.fee)
        new_balance_a = balance_a + amount_a_out
        new_balance_b = balance_b - amount_b_in
    else:
        # Too much A: sell A for B — `dex`'s natural A-in/B-out orientation already
        # matches this direction, no flip needed.
        amount_a_in = -delta_value_a / price_a_in_b
        amount_b_out = exact_in(dex, amount_a_in, config.fee)
        new_balance_a = balance_a - amount_a_in
        new_balance_b = balance_b + amount_b_out

    return new_balance_a, new_balance_b - config.gas_cost_b


@dataclass(frozen=True)
class PeriodicRebalanceConfig:
    """Rebalance to exact target on a fixed schedule, regardless of how far drifted."""

    period_years: float
    dex: GenericDexConfig


@dataclass(frozen=True)
class ThresholdRebalanceConfig:
    """Rebalance to exact target the moment drift exceeds `threshold`, otherwise do nothing."""

    threshold: float
    dex: GenericDexConfig


@dataclass
class BaselineSimulationResult:
    price_path: np.ndarray
    actual_value_path: np.ndarray
    reference_value_path: np.ndarray
    tracking_error_path: np.ndarray
    cost_path: np.ndarray
    n_rebalances: int


def run_periodic_baseline_simulation(
    n_steps: int,
    dt_years: float,
    sigma_annual: float,
    initial_balance_a: float,
    initial_balance_b: float,
    target_weight_a: float,
    config: PeriodicRebalanceConfig,
    seed: int,
) -> BaselineSimulationResult:
    """Runs the periodic-rebalance baseline against one synthetic GBM price path."""
    price_path = simulate_price_path(n_steps, dt_years, sigma_annual, seed=seed)
    period_steps = max(1, round(config.period_years / dt_years))

    bal_a, bal_b = initial_balance_a, initial_balance_b
    bal_a_path = np.empty(n_steps + 1)
    bal_b_path = np.empty(n_steps + 1)
    bal_a_path[0], bal_b_path[0] = bal_a, bal_b
    n_rebalances = 0

    for t in range(1, n_steps + 1):
        if t % period_steps == 0:
            bal_a, bal_b = rebalance_to_target(bal_a, bal_b, price_path[t], target_weight_a, config.dex)
            n_rebalances += 1
        bal_a_path[t] = bal_a
        bal_b_path[t] = bal_b

    return _finalize_baseline_result(price_path, bal_a_path, bal_b_path, target_weight_a, n_rebalances)


def run_threshold_baseline_simulation(
    n_steps: int,
    dt_years: float,
    sigma_annual: float,
    initial_balance_a: float,
    initial_balance_b: float,
    target_weight_a: float,
    config: ThresholdRebalanceConfig,
    seed: int,
) -> BaselineSimulationResult:
    """Runs the threshold-rebalance baseline against one synthetic GBM price path."""
    price_path = simulate_price_path(n_steps, dt_years, sigma_annual, seed=seed)

    bal_a, bal_b = initial_balance_a, initial_balance_b
    bal_a_path = np.empty(n_steps + 1)
    bal_b_path = np.empty(n_steps + 1)
    bal_a_path[0], bal_b_path[0] = bal_a, bal_b
    n_rebalances = 0

    for t in range(1, n_steps + 1):
        price = price_path[t]
        if tracking_error(bal_a, bal_b, price, target_weight_a) > config.threshold:
            bal_a, bal_b = rebalance_to_target(bal_a, bal_b, price, target_weight_a, config.dex)
            n_rebalances += 1
        bal_a_path[t] = bal_a
        bal_b_path[t] = bal_b

    return _finalize_baseline_result(price_path, bal_a_path, bal_b_path, target_weight_a, n_rebalances)


def _finalize_baseline_result(
    price_path: np.ndarray,
    balance_a_path: np.ndarray,
    balance_b_path: np.ndarray,
    target_weight_a: float,
    n_rebalances: int,
) -> BaselineSimulationResult:
    actual_value_path = np.array(
        [portfolio_value(a, b, p) for a, b, p in zip(balance_a_path, balance_b_path, price_path)]
    )
    tracking_error_path = np.array(
        [tracking_error(a, b, p, target_weight_a) for a, b, p in zip(balance_a_path, balance_b_path, price_path)]
    )
    reference_value_path = frictionless_reference_path(price_path, actual_value_path[0], target_weight_a)
    cost_path = cost_of_rebalancing(actual_value_path, reference_value_path)
    return BaselineSimulationResult(
        price_path=price_path,
        actual_value_path=actual_value_path,
        reference_value_path=reference_value_path,
        tracking_error_path=tracking_error_path,
        cost_path=cost_path,
        n_rebalances=n_rebalances,
    )
