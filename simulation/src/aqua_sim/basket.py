"""Basket-aware pricing, and an independent same-basket agent PM doesn't control.

ADR-0011/BasketScopeGuard forbids any strategy but PM's own from *crossing* a declared
group boundary, but does not forbid another strategy from trading *within* the same group.
`proofs-of-concept/swapvm-multi-token/src/BasketXYCSwap.sol`'s PoC formula augments PM's
quote for tokenIn->tokenOut with a third (basket) token's raw balance --
`effectiveBalanceOut = balanceOut + basketToken's Aqua balance` -- with no price conversion,
which is only correct if the basket token happens to be worth the same as `balance_out`'s
own token. ADR-0003 requires a group's value to be the oracle-valued *sum* of its members
(e.g. a "stables" group of USDC + EURC, where EUR/USD floats) -- raw addition silently
assumes currency parity that a genuinely oracle-valued group can't assume. This module
models the corrected mechanism: the basket balance is converted through its own oracle
price before it's added, and a stale price on that oracle rejects the trade outright
(ADR-0005), rather than pricing off a stale or assumed-parity value. The Solidity PoC still
does the uncorrected raw-add; fixing it is tracked separately, not part of this change.

Also adds a minimal model of the other strategy sharing the basket: an independent noise
process directly on the basket token's balance, since we neither know nor care what that
other strategy's own pricing looks like -- only that it changes the shared balance, which is
one of the two things that perturbs PM (the other now being that token's own oracle price).
This module answers "how does PM react to that" -- not by rebuilding the full multi-token
group routing logic (`BLEUDEV-75`, separate, unbuilt), but by generalizing the PoC's
augmentation to the weighted curve this package already implements (`curve.py`).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from aqua_sim.curve import CurveState, exact_in, spot_price
from aqua_sim.flows import maybe_arbitrage_trade, maybe_exogenous_trade
from aqua_sim.market import simulate_price_path
from aqua_sim.metrics import cost_of_rebalancing, frictionless_reference_path, portfolio_value, tracking_error
from aqua_sim.simulate import MechanismSimConfig, SimulationResult


class StalePriceError(ValueError):
    """A group member's oracle price is older than its configured max age. The trade must be
    rejected outright, not priced against a stale or fallback value (ADR-0005's Decision)."""


def basket_augmented_state(
    state: CurveState,
    basket_balance: float,
    basket_price_in_out: float = 1.0,
    *,
    basket_price_is_stale: bool = False,
) -> CurveState:
    """The oracle-valued augmentation ADR-0003 requires before pricing: `balance_out` is
    replaced by `balance_out + basket_balance * basket_price_in_out` -- `basket_balance`
    converted into `balance_out`'s own token via the basket token's oracle price, not added
    raw. `basket_price_in_out=1.0` (the default) recovers the degenerate case where both
    tokens happen to be worth the same (e.g. two USD stablecoins); anything else (e.g. a
    EUR-pegged basket-mate priced against a USD-numeraire `balance_out`) requires the real
    ratio. `basket_balance` is never itself part of `state` -- it's a separate balance in the
    same declared group, held by the same wallet, managed by some other strategy.

    Raises `StalePriceError` if `basket_price_is_stale` -- the caller is expected to have
    already checked the feed's `updatedAt` against its configured max age (ADR-0005) and pass
    the result in; this function refuses to price at all rather than silently falling back to
    a stale or assumed value.
    """
    if basket_price_is_stale:
        raise StalePriceError(
            f"basket token's oracle price is stale; refusing to price the {state.balance_in}/"
            f"{state.balance_out} pair against it rather than use a stale value"
        )
    if basket_price_in_out <= 0:
        raise ValueError(f"basket_price_in_out must be positive, got {basket_price_in_out}")
    return CurveState(
        state.balance_in, state.balance_out + basket_balance * basket_price_in_out, state.weight_in, state.weight_out
    )


def apply_basket_aware_exact_in(
    balance_in: float,
    balance_out: float,
    basket_balance: float,
    weight_in: float,
    weight_out: float,
    amount_in: float,
    fee: float,
    basket_price_in_out: float = 1.0,
    *,
    basket_price_is_stale: bool = False,
) -> tuple[float, float]:
    """Runs one exact-in trade against the basket-augmented curve, then returns the REAL
    (non-augmented) new `(balance_in, balance_out)` -- `basket_balance` itself never moves
    from this trade; only the two tokens actually being swapped do. Mirrors how
    BasketXYCSwap.sol reads the basket balance for pricing but never pulls/pushes it, plus
    the oracle price conversion and staleness rejection ADR-0003/ADR-0005 require (see
    `basket_augmented_state`) that the Solidity PoC doesn't yet apply.

    The basket token inflates the curve's apparent output-side liquidity without being
    transferable itself, so a quote can come back larger than the real `balance_out` --
    raises `ValueError` rather than returning a negative real balance in that case.
    """
    state = CurveState(balance_in, balance_out, weight_in, weight_out)
    effective_state = basket_augmented_state(
        state, basket_balance, basket_price_in_out, basket_price_is_stale=basket_price_is_stale
    )
    amount_out = exact_in(effective_state, amount_in, fee)
    if amount_out >= balance_out:
        raise ValueError(
            f"basket-aware quote of {amount_out} exceeds the real transferable "
            f"balance_out={balance_out}; the basket token affects pricing but cannot "
            "itself be paid out as the traded token"
        )
    return effective_state.balance_in + amount_in, balance_out - amount_out


def basket_aware_spot_price(
    balance_in: float,
    balance_out: float,
    basket_balance: float,
    weight_in: float,
    weight_out: float,
    basket_price_in_out: float = 1.0,
    *,
    basket_price_is_stale: bool = False,
) -> float:
    state = CurveState(balance_in, balance_out, weight_in, weight_out)
    return spot_price(
        basket_augmented_state(state, basket_balance, basket_price_in_out, basket_price_is_stale=basket_price_is_stale)
    )


@dataclass(frozen=True)
class CoBasketAgentConfig:
    """An independent OTHER strategy trading the shared basket token C -- not PM's own,
    just some other strategy BasketScopeGuard allows to share PM's declared group. Modeled
    as its own Poisson-arrival, lognormal-size noise process directly on C's balance (same
    shape as `flows.ExogenousFlowConfig`), deliberately not routed through any curve of its
    own: PM has no visibility into that strategy's mechanics, only into the balance change
    it leaves behind.
    """

    arrival_rate_per_year: float
    mean_size_fraction: float = 0.01
    size_sigma: float = 0.5


def maybe_cobasket_trade(
    basket_balance: float, dt_years: float, config: CoBasketAgentConfig, rng: np.random.Generator
) -> tuple[float, bool]:
    """With probability `arrival_rate * dt` (Poisson thinning), grows or shrinks the basket
    token's balance by a random fraction, in a random direction. Returns
    `(new_basket_balance, happened)`.
    """
    if rng.random() >= config.arrival_rate_per_year * dt_years:
        return basket_balance, False

    size_fraction = rng.lognormal(mean=np.log(config.mean_size_fraction), sigma=config.size_sigma)
    size_fraction = min(size_fraction, 0.5)

    if rng.random() < 0.5:
        new_balance = basket_balance * (1 + size_fraction)
    else:
        new_balance = basket_balance * (1 - size_fraction)

    return max(new_balance, 1e-9), True


@dataclass
class BasketSimulationResult(SimulationResult):
    """Same fields as `simulate.SimulationResult`, plus the basket token's own balance path
    and how many times the independent co-basket agent actually traded (0 if
    `cobasket_config=None`)."""

    basket_balance_path: np.ndarray = None
    n_cobasket_trades: int = 0


def run_basket_simulation(
    config: MechanismSimConfig,
    initial_basket_balance: float,
    cobasket_config: CoBasketAgentConfig | None,
    basket_price_path: np.ndarray | None = None,
) -> BasketSimulationResult:
    """Runs the same simulation as `simulate.run_mechanism_simulation` (same background
    noise, same corrective-arb logic, same price path), except every trade against the A/B
    pair is priced through the basket-augmented curve (B is declared grouped with basket
    token C): `effective_balance_b = balance_b + basket_balance * basket_price_path[t]`,
    where `basket_price_path[t]` is C's oracle price denominated in B at step `t`
    (`basket_augmented_state`; ADR-0003/ADR-0005). Defaulting `basket_price_path` to a
    constant `1.0` array recovers the degenerate same-value-token case; pass a real path
    (e.g. a EUR/USD-style series) to model a basket-mate that doesn't track B 1:1. This
    function doesn't model oracle staleness itself -- `basket_price_path` is assumed
    already-fresh at every step; see `basket_augmented_state`'s `basket_price_is_stale` for
    where a staleness check would reject a trade instead. If `cobasket_config` is given, an
    independent OTHER strategy also trades C every step, per its own arrival process --
    changing what PM quotes for A<->B without PM doing anything. Passing
    `cobasket_config=None` holds C's balance constant, isolating the effect of basket
    AUGMENTATION alone from the effect of another strategy actively MOVING it.

    Tracking error and cost are computed on `(balance_a, balance_b)` alone, matching
    `simulate.run_mechanism_simulation` exactly -- C is not part of PM's own declared
    target; it belongs to whatever other strategy manages it. This is deliberate: the
    question this answers is how PM's OWN metrics react to something it doesn't control,
    not the combined wallet's total value.
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
    if basket_price_path is None:
        basket_price_path = np.ones(config.n_steps + 1)
    elif len(basket_price_path) != config.n_steps + 1:
        raise ValueError(
            f"basket_price_path must have length n_steps+1={config.n_steps + 1}, got {len(basket_price_path)}"
        )
    rng = np.random.default_rng(config.seed)

    balance_a, balance_b = config.initial_balance_a, config.initial_balance_b
    basket_balance = initial_basket_balance
    balance_a_path = np.empty(config.n_steps + 1)
    balance_b_path = np.empty(config.n_steps + 1)
    basket_balance_path = np.empty(config.n_steps + 1)
    balance_a_path[0], balance_b_path[0], basket_balance_path[0] = balance_a, balance_b, basket_balance

    n_exogenous_trades = 0
    n_arb_trades = 0
    n_cobasket_trades = 0
    steps_since_last_arb = config.arb.min_steps_between_trades  # seed past cooldown so step 1 is eligible

    for t in range(1, config.n_steps + 1):
        price = price_path[t]

        if cobasket_config is not None:
            basket_balance, cobasket_happened = maybe_cobasket_trade(basket_balance, config.dt_years, cobasket_config, rng)
            n_cobasket_trades += int(cobasket_happened)

        # basket_value: the basket balance converted through its own oracle price into B's
        # numeraire (ADR-0003) -- what actually augments B's effective balance, not the raw
        # token amount tracked in basket_balance_path.
        basket_value = basket_balance * basket_price_path[t]

        effective_ab = CurveState(balance_a, balance_b + basket_value, weight_a, weight_b)
        effective_ab, _, exo_happened = maybe_exogenous_trade(effective_ab, config.dt_years, config.exogenous, rng)
        balance_a, balance_b = effective_ab.balance_in, effective_ab.balance_out - basket_value
        n_exogenous_trades += int(exo_happened)

        effective_ab = CurveState(balance_a, balance_b + basket_value, weight_a, weight_b)
        new_effective_ab, _, arb_happened_ab = maybe_arbitrage_trade(
            effective_ab, 1 / price, config.arb, steps_since_last_arb, gas_cost_in=config.arb.gas_cost_b / price
        )

        if arb_happened_ab:
            balance_a, balance_b = new_effective_ab.balance_in, new_effective_ab.balance_out - basket_value
            n_arb_trades += 1
            steps_since_last_arb = 0
        else:
            effective_ba = CurveState(balance_b + basket_value, balance_a, weight_b, weight_a)
            new_effective_ba, _, arb_happened_ba = maybe_arbitrage_trade(
                effective_ba, price, config.arb, steps_since_last_arb, gas_cost_in=config.arb.gas_cost_b
            )
            if arb_happened_ba:
                balance_b, balance_a = new_effective_ba.balance_in - basket_value, new_effective_ba.balance_out
                n_arb_trades += 1
                steps_since_last_arb = 0
            else:
                steps_since_last_arb += 1

        balance_a_path[t] = balance_a
        balance_b_path[t] = balance_b
        basket_balance_path[t] = basket_balance

    actual_value_path = np.array(
        [portfolio_value(a, b, p) for a, b, p in zip(balance_a_path, balance_b_path, price_path)]
    )
    tracking_error_path = np.array(
        [tracking_error(a, b, p, config.target_weight_a) for a, b, p in zip(balance_a_path, balance_b_path, price_path)]
    )
    reference_value_path = frictionless_reference_path(price_path, actual_value_path[0], config.target_weight_a)
    cost_path = cost_of_rebalancing(actual_value_path, reference_value_path)

    return BasketSimulationResult(
        price_path=price_path,
        balance_a_path=balance_a_path,
        balance_b_path=balance_b_path,
        actual_value_path=actual_value_path,
        reference_value_path=reference_value_path,
        tracking_error_path=tracking_error_path,
        cost_path=cost_path,
        n_exogenous_trades=n_exogenous_trades,
        n_arb_trades=n_arb_trades,
        basket_balance_path=basket_balance_path,
        n_cobasket_trades=n_cobasket_trades,
    )
