"""Two-tier flow model: exogenous (organic) trades and endogenous (arbitrage) trades.

Per ADR-0008's own framing: "model flow in two tiers, endogenous rebalancing/arb flow +
exogenous organic flow." This module implements both tiers as trades against a `CurveState`
(see `curve.py`); `simulate.py` runs them together against a market-price path.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from aqua_sim.curve import CurveState, apply_exact_in, spot_price


@dataclass(frozen=True)
class ExogenousFlowConfig:
    """Poisson-arrival trades unrelated to the pool's own skew — pure noise flow.

    `arrival_rate_per_year` — expected number of organic trades per year (Poisson rate).
    `mean_size_fraction` / `size_sigma` — trade size as a fraction of `balance_in` at the
    time of the trade, drawn lognormally (always positive, right-skewed — most trades
    small, a few large, matching typical trade-size distributions).
    """

    arrival_rate_per_year: float
    mean_size_fraction: float = 0.01
    size_sigma: float = 0.5
    fee: float = 0.0002  # 2 bps, ADR-0008


def maybe_exogenous_trade(
    state: CurveState,
    dt_years: float,
    config: ExogenousFlowConfig,
    rng: np.random.Generator,
) -> tuple[CurveState, float, bool]:
    """With probability `arrival_rate * dt` (Poisson thinning), executes one organic trade
    in a random direction, sized as a random fraction of the current `balance_in` side.

    Returns `(new_state, amount_in, happened)` — `new_state is state` and `amount_in == 0.0`
    when no trade happened this step.
    """
    if rng.random() >= config.arrival_rate_per_year * dt_years:
        return state, 0.0, False

    size_fraction = rng.lognormal(mean=np.log(config.mean_size_fraction), sigma=config.size_sigma)
    size_fraction = min(size_fraction, 0.5)  # cap a single organic trade at 50% of balance_in

    if rng.random() < 0.5:
        amount_in = state.balance_in * size_fraction
        new_state, _ = apply_exact_in(state, amount_in, config.fee)
    else:
        flipped = CurveState(state.balance_out, state.balance_in, state.weight_out, state.weight_in)
        amount_in = flipped.balance_in * size_fraction
        flipped_new, _ = apply_exact_in(flipped, amount_in, config.fee)
        new_state = CurveState(flipped_new.balance_out, flipped_new.balance_in, flipped_new.weight_out, flipped_new.weight_in)

    return new_state, amount_in, True


@dataclass(frozen=True)
class EndogenousArbConfig:
    """Arbitrageur/solver-driven corrective flow — the mechanism's actual rebalancing path.

    `tolerance_band` — ADR-0006: deviations from the market-implied price smaller than
    this fraction are priced as neutral, not corrective; no arb fires inside it.
    `min_steps_between_trades` — ADR-0006's rate cap, expressed as a step count here
    (converted from a real time interval by the caller).

    Defaults are the values notebook 10 (`10_parameter_decision.ipynb`) picked: every
    dimension that notebook measured (cost, tracking error, shock-recovery time,
    stale-quote exploit exposure) gets monotonically worse as either knob loosens, so
    tighter is always better *in-model* — these defaults are a deliberate step back from
    that mathematical optimum (`tolerance_band=0.001`, `min_steps_between_trades=1`)
    to bound correction frequency (and so, real gas cost, not modeled here) until
    `BLEUDEV-265`'s real benchmark exists to make that trade-off precisely.
    """

    tolerance_band: float = 0.005
    fee: float = 0.0002
    min_steps_between_trades: int = 12


def _target_balance_in_for_price(
    invariant_value: float, weight_in: float, weight_out: float, target_price: float
) -> float:
    """Closed-form, fee-free sizing helper: the `balance_in` a curve with invariant
    `invariant_value` would have if its spot price were exactly `target_price`.

    Derived by solving `{B_i^wi * B_o^wo = V, (B_i/wi)/(B_o/wo) = target_price}` for `B_i`:
    `B_o = (wo/wi) * B_i / target_price`, substitute into the invariant, solve for `B_i`.
    This sizes the trade an arbitrageur *would* need in the frictionless (fee=0) case; the
    actual trade is then executed through `apply_exact_in` with the real fee, so realized
    balances always come from the one true (fee-inclusive) formula in `curve.py` — this
    helper only decides "how much", never "what happens when you trade that much".
    """
    ratio = weight_in * target_price / weight_out
    return invariant_value * ratio**weight_out


def maybe_arbitrage_trade(
    state: CurveState,
    market_price: float,
    config: EndogenousArbConfig,
    steps_since_last_trade: int,
) -> tuple[CurveState, float, bool]:
    """Fires a corrective trade against `state` if the pool's spot price has drifted from
    `market_price` by more than `tolerance_band`, and the rate cap allows it.

    `market_price` and `spot_price(state)` must use the same convention: both "units of
    `balance_in`'s token paid per unit of `balance_out`'s token received" (`curve.py`'s
    `SP(i->o)`). The caller is responsible for presenting `state` with the correct
    `in`/`out` orientation for the direction that would currently be profitable — see
    `simulate.py`, which tries both orientations each step.

    Returns `(new_state, amount_in, happened)`.
    """
    if steps_since_last_trade < config.min_steps_between_trades:
        return state, 0.0, False

    pool_price = spot_price(state)
    # Pool is CHEAPER than market for this i->o direction (pay less `in` per `out` than the
    # market would charge) once past the fee + tolerance-band buffer — an arbitrageur can
    # buy `out` here and profit reselling at the market rate.
    threshold = market_price * (1 - config.tolerance_band - config.fee)
    if pool_price >= threshold:
        return state, 0.0, False

    target_price = market_price * (1 - config.tolerance_band)
    v = state.balance_in**state.weight_in * state.balance_out**state.weight_out
    target_balance_in = _target_balance_in_for_price(v, state.weight_in, state.weight_out, target_price)
    amount_in = target_balance_in - state.balance_in
    if amount_in <= 0:
        return state, 0.0, False

    new_state, _ = apply_exact_in(state, amount_in, config.fee)
    return new_state, amount_in, True
