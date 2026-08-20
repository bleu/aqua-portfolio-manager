"""Ties market.py + flows.py + metrics.py together into one mechanism simulation run.

Each step: the market price moves (a pre-generated GBM path), an exogenous trade may
arrive (`flows.maybe_exogenous_trade`), then an endogenous arb trade may fire in
whichever orientation is currently profitable (`flows.maybe_arbitrage_trade`, tried both
ways since a single `CurveState` orientation can only ever be profitable one direction at
a time). Tracking error and cost of rebalancing (`metrics.py`) are computed against the
resulting balance path.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from aqua_sim.curve import CurveState
from aqua_sim.flows import EndogenousArbConfig, ExogenousFlowConfig, maybe_arbitrage_trade, maybe_exogenous_trade
from aqua_sim.market import simulate_price_path
from aqua_sim.metrics import cost_of_rebalancing, frictionless_reference_path, portfolio_value, tracking_error


@dataclass(frozen=True)
class MechanismSimConfig:
    n_steps: int
    dt_years: float
    sigma_annual: float
    initial_balance_a: float
    initial_balance_b: float
    target_weight_a: float
    exogenous: ExogenousFlowConfig
    arb: EndogenousArbConfig
    seed: int = 0


@dataclass
class SimulationResult:
    price_path: np.ndarray
    balance_a_path: np.ndarray
    balance_b_path: np.ndarray
    actual_value_path: np.ndarray
    reference_value_path: np.ndarray
    tracking_error_path: np.ndarray
    cost_path: np.ndarray
    n_exogenous_trades: int = 0
    n_arb_trades: int = 0


def run_mechanism_simulation(config: MechanismSimConfig) -> SimulationResult:
    """Runs one Monte Carlo path of the mechanism (this strategy's own curve) end to end."""
    weight_a, weight_b = config.target_weight_a, 1 - config.target_weight_a
    price_path = simulate_price_path(config.n_steps, config.dt_years, config.sigma_annual, seed=config.seed)
    rng = np.random.default_rng(config.seed)

    balance_a, balance_b = config.initial_balance_a, config.initial_balance_b
    balance_a_path = np.empty(config.n_steps + 1)
    balance_b_path = np.empty(config.n_steps + 1)
    balance_a_path[0], balance_b_path[0] = balance_a, balance_b

    n_exogenous_trades = 0
    n_arb_trades = 0
    steps_since_last_arb = config.arb.min_steps_between_trades

    for t in range(1, config.n_steps + 1):
        price = price_path[t]

        state_ab = CurveState(balance_a, balance_b, weight_a, weight_b)
        state_ab, _, exo_happened = maybe_exogenous_trade(state_ab, config.dt_years, config.exogenous, rng)
        balance_a, balance_b = state_ab.balance_in, state_ab.balance_out
        n_exogenous_trades += int(exo_happened)

        # `price` is the conventional "B received per A" (matches metrics.py/baselines.py's
        # `price_a_in_b`). `flows.maybe_arbitrage_trade` expects curve.py's SP(i->o)
        # convention instead ("i paid per o received"), which is the RECIPROCAL: SP(A->B)
        # should equal 1/price (pay 1/price A to receive 1 B, since 1 A = price B), and
        # SP(B->A) should equal price itself. Feeding `price` and `1/price` to the wrong
        # orientations here previously drove the pool to the reciprocal of fair value —
        # caught by the full-simulation tracking-error sanity check blowing up, not by
        # the smaller isolated unit tests (which happened to use market_price=1.0, its
        # own reciprocal, masking the mismatch). See simulation/README.md's flagged fix.
        state_ab = CurveState(balance_a, balance_b, weight_a, weight_b)
        new_state_ab, _, arb_happened_ab = maybe_arbitrage_trade(state_ab, 1 / price, config.arb, steps_since_last_arb)

        if arb_happened_ab:
            balance_a, balance_b = new_state_ab.balance_in, new_state_ab.balance_out
            n_arb_trades += 1
            steps_since_last_arb = 0
        else:
            state_ba = CurveState(balance_b, balance_a, weight_b, weight_a)
            new_state_ba, _, arb_happened_ba = maybe_arbitrage_trade(
                state_ba, price, config.arb, steps_since_last_arb
            )
            if arb_happened_ba:
                balance_b, balance_a = new_state_ba.balance_in, new_state_ba.balance_out
                n_arb_trades += 1
                steps_since_last_arb = 0
            else:
                steps_since_last_arb += 1

        balance_a_path[t] = balance_a
        balance_b_path[t] = balance_b

    actual_value_path = np.array(
        [portfolio_value(a, b, p) for a, b, p in zip(balance_a_path, balance_b_path, price_path)]
    )
    tracking_error_path = np.array(
        [
            tracking_error(a, b, p, config.target_weight_a)
            for a, b, p in zip(balance_a_path, balance_b_path, price_path)
        ]
    )
    reference_value_path = frictionless_reference_path(price_path, actual_value_path[0], config.target_weight_a)
    cost_path = cost_of_rebalancing(actual_value_path, reference_value_path)

    return SimulationResult(
        price_path=price_path,
        balance_a_path=balance_a_path,
        balance_b_path=balance_b_path,
        actual_value_path=actual_value_path,
        reference_value_path=reference_value_path,
        tracking_error_path=tracking_error_path,
        cost_path=cost_path,
        n_exogenous_trades=n_exogenous_trades,
        n_arb_trades=n_arb_trades,
    )
