"""Deliberately hostile trading agents — not relabeled noise.

Every trader modeled elsewhere in this simulation (`flows.py`) is either pure background
noise (no preference for hurting the LP) or a rational-but-benign arbitrageur (only ever
correcting genuine drift). Neither one is *trying* to make things worse for the LP. This
module models two agents that are: one that deliberately times its trades to force more
corrective activity than organic drift would (a griefing/cost-inflation angle), and one
that deliberately exploits the gap between a sudden price jump and the mechanism's next
correction (a staleness-arbitrage angle — the simulated version of a "flash-crash
exploit").

Neither agent can ever violate the round-trip invariant proven in
`docs/INVARIANT-PROOF.md` — that proof holds for *any* trade against this curve,
adversarial or not, as long as it goes through the real, fee-inclusive formula
(`curve.exact_in`/`apply_exact_in`), which both agents here use, same as every other
trader in this simulation. What these agents test is not "can the invariant be broken"
(it can't — that's already proven algebraically) but "does the *mechanism's own* cost and
tracking-error behavior stay reasonable when the trading pattern is actively hostile,
rather than merely random."
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from aqua_sim.curve import CurveState, apply_exact_in, exact_in
from aqua_sim.flows import maybe_arbitrage_trade, maybe_exogenous_trade
from aqua_sim.market import simulate_price_path
from aqua_sim.metrics import cost_of_rebalancing, frictionless_reference_path, portfolio_value, tracking_error
from aqua_sim.simulate import MechanismSimConfig, SimulationResult


@dataclass
class GriefingSimulationResult(SimulationResult):
    """Same fields as `simulate.SimulationResult`, plus a count of how many griefing
    nudges the hostile agent actually landed (0 if `griefing_config=None` was passed)."""

    n_griefing_trades: int = 0


@dataclass(frozen=True)
class GriefingAdversaryConfig:
    """A persistent, one-directional attacker: sells the same side, at the same fixed
    size, on EVERY step, all simulation long — regardless of whether the pool is
    currently on-target, inside the tolerance band, or already drifted. This is
    deliberately the more aggressive of the two "amplify drift" designs considered here:
    an earlier, narrower version only nudged the pool while it was inside the tolerance
    band, and turned out to have almost no measurable effect (it fired rarely, since the
    pool spends little time in that narrow window — see `thoughts`/notebook 07's own
    write-up). A patient, well-funded real attacker isn't limited to that narrow window
    either, so testing the more aggressive, unconditional version is the fairer worst
    case. The adversary still pays the same real fee as anyone else on every single
    trade — nothing here bypasses the pricing formula.
    """

    fee: float = 0.0002
    size_fraction: float = 0.001  # fraction of the CURRENT balance sold, every single step
    sell_token_in: bool = True  # True: always sells the "in" side; False: always sells "out"


def apply_griefing_trade(state: CurveState, config: GriefingAdversaryConfig) -> tuple[CurveState, float]:
    """Applies one persistent-pressure trade, unconditionally (this adversary doesn't
    check drift or the tolerance band at all — it just always sells the configured side).
    Returns `(new_state, amount_in)`.
    """
    if config.sell_token_in:
        amount_in = state.balance_in * config.size_fraction
        new_state, _ = apply_exact_in(state, amount_in, config.fee)
        return new_state, amount_in

    flipped = CurveState(state.balance_out, state.balance_in, state.weight_out, state.weight_in)
    amount_in = flipped.balance_in * config.size_fraction
    new_flipped, _ = apply_exact_in(flipped, amount_in, config.fee)
    new_state = CurveState(new_flipped.balance_out, new_flipped.balance_in, new_flipped.weight_out, new_flipped.weight_in)
    return new_state, amount_in


@dataclass(frozen=True)
class StaleQuoteExploitConfig:
    fee: float = 0.0002
    max_trade_fraction: float = 0.9  # never try to trade away more than this share of a balance
    search_steps: int = 60  # resolution of the profit-maximizing search below


def best_stale_quote_trade(
    state: CurveState,
    real_market_price: float,
    config: StaleQuoteExploitConfig,
) -> tuple[float, float]:
    """Finds the trade size that maximizes an adversary's profit, trading against a pool
    still quoting its OLD price after the real market has already jumped —
    `real_market_price` and `spot_price(state)` in the same `SP(i->o)` convention
    (`curve.py`: "units of `i` paid per unit of `o` received").

    Profit, priced in units of token `o` (`state.balance_out`'s token):
    `profit(a_in) = exact_in(state, a_in, fee) - a_in / real_market_price` — what the
    adversary receives from the stale pool, minus what that same input would have been
    worth trading at the real, current market rate. `exact_in` is concave in `a_in`
    (diminishing returns, same curve-bending property checked in
    `01_pricing_curve.ipynb`), so profit here is concave-minus-linear, i.e. also
    concave — it has one interior maximum, found here by a plain grid-plus-refine
    search over trade size (not a black-box optimizer, so the result stays easy to
    verify by eye against a profit curve).

    Returns `(best_amount_in, best_profit)`. `best_profit <= 0` means there's no
    exploitable gap at all -- the pool's stale quote isn't actually worse than the real
    market for this direction (the caller should check the flipped orientation too, same
    pattern as `flows.maybe_arbitrage_trade`).
    """
    if real_market_price <= 0:
        raise ValueError(f"real_market_price must be positive, got {real_market_price}")

    def profit(amount_in: float) -> float:
        if amount_in <= 0:
            return 0.0
        received = exact_in(state, amount_in, config.fee)
        cost_at_real_price = amount_in / real_market_price
        return received - cost_at_real_price

    lo, hi = 1e-9, state.balance_in * config.max_trade_fraction
    for _ in range(config.search_steps):
        m1 = lo + (hi - lo) / 3
        m2 = hi - (hi - lo) / 3
        if profit(m1) < profit(m2):
            lo = m1
        else:
            hi = m2
    best_amount_in = (lo + hi) / 2
    return best_amount_in, profit(best_amount_in)


def run_griefing_simulation(
    config: MechanismSimConfig, griefing_config: GriefingAdversaryConfig | None
) -> SimulationResult:
    """Runs the same simulation as `simulate.run_mechanism_simulation` (same background
    noise, same corrective-arb logic, same price path), with one addition: if
    `griefing_config` is given, a hostile agent ALSO tries a griefing nudge every single
    step -- unlike our own corrective trades, an adversary isn't bound by our rate cap,
    so this deliberately gives them the most aggressive shot at it we can model.

    Passing `griefing_config=None` reproduces `run_mechanism_simulation` exactly (used as
    the "benign" baseline this notebook compares against) -- same trades, same order, same
    result, so the comparison isolates the griefing agent's effect and nothing else.
    """
    weight_a, weight_b = config.target_weight_a, 1 - config.target_weight_a
    if config.price_path is not None:
        if len(config.price_path) != config.n_steps + 1:
            raise ValueError(
                f"price_path override must have length n_steps+1={config.n_steps + 1}, got {len(config.price_path)}"
            )
        price_path = config.price_path
    else:
        price_path = simulate_price_path(config.n_steps, config.dt_years, config.sigma_annual, seed=config.seed)
    rng = np.random.default_rng(config.seed)

    balance_a, balance_b = config.initial_balance_a, config.initial_balance_b
    balance_a_path = np.empty(config.n_steps + 1)
    balance_b_path = np.empty(config.n_steps + 1)
    balance_a_path[0], balance_b_path[0] = balance_a, balance_b

    n_exogenous_trades = 0
    n_arb_trades = 0
    n_griefing_trades = 0
    steps_since_last_arb = config.arb.min_steps_between_trades

    for t in range(1, config.n_steps + 1):
        price = price_path[t]

        state_ab = CurveState(balance_a, balance_b, weight_a, weight_b)
        state_ab, _, exo_happened = maybe_exogenous_trade(state_ab, config.dt_years, config.exogenous, rng)
        balance_a, balance_b = state_ab.balance_in, state_ab.balance_out
        n_exogenous_trades += int(exo_happened)

        if griefing_config is not None:
            state_ab = CurveState(balance_a, balance_b, weight_a, weight_b)
            state_ab, _ = apply_griefing_trade(state_ab, griefing_config)
            balance_a, balance_b = state_ab.balance_in, state_ab.balance_out
            n_griefing_trades += 1

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

    return GriefingSimulationResult(
        price_path=price_path,
        balance_a_path=balance_a_path,
        balance_b_path=balance_b_path,
        actual_value_path=actual_value_path,
        reference_value_path=reference_value_path,
        tracking_error_path=tracking_error_path,
        cost_path=cost_path,
        n_exogenous_trades=n_exogenous_trades,
        n_arb_trades=n_arb_trades,
        n_griefing_trades=n_griefing_trades,
    )
