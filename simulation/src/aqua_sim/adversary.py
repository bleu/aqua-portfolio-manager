"""A deliberately hostile trading agent — not relabeled noise.

Every trader modeled elsewhere in this simulation (`flows.py`) is either pure background
noise (no preference for hurting the LP) or a rational-but-benign arbitrageur (only ever
correcting genuine drift). Neither one is *trying* to make things worse for the LP. This
module models an agent that deliberately exploits the gap between a sudden price jump and
the mechanism's next correction (a staleness-arbitrage angle — the simulated version of a
"flash-crash exploit").

This agent can never violate the round-trip invariant proven in `docs/INVARIANT-PROOF.md`
— that proof holds for *any* trade against this curve, adversarial or not, as long as it
goes through the real, fee-inclusive formula (`curve.exact_in`), same as every other trader
in this simulation. What it tests is not "can the invariant be broken" (it can't — that's
already proven algebraically) but "does the *mechanism's own* cost and tracking-error
behavior stay reasonable when a trade is deliberately timed to exploit staleness."
"""

from __future__ import annotations

from dataclasses import dataclass

from aqua_sim.curve import CurveState, exact_in


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
    concave — it has one interior maximum, found here by a plain ternary search
    over trade size (not a black-box optimizer, so the result stays easy to
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
