"""The two KPIs ADR-0008 measures success by: tracking error and cost of rebalancing.

Cost is defined as value lost relative to a frictionless, costlessly-and-instantly
rebalanced reference portfolio holding the same starting value — a single, standard
metric (the "constant-rebalanced-portfolio" benchmark from portfolio theory) that is
directly comparable between the mechanism and both naive baselines, without having to
hand-attribute fee/slippage/gas/arb-profit-leakage as separate line items for each
approach individually. Loss-Versus-Rebalancing-style value leakage to arbitrageurs
(Milionis et al.) and a naive baseline's own fee+slippage+gas both fall out of the same
one number automatically, because both are just "value the frictionless reference has
that the actual portfolio doesn't."
"""

from __future__ import annotations

import numpy as np


def portfolio_value(balance_a: float, balance_b: float, price_a_in_b: float) -> float:
    """Total portfolio value, denominated in token B."""
    return balance_a * price_a_in_b + balance_b


def weight_a(balance_a: float, balance_b: float, price_a_in_b: float) -> float:
    """Token A's share of total portfolio value (0 to 1)."""
    value = portfolio_value(balance_a, balance_b, price_a_in_b)
    if value <= 0:
        raise ValueError(f"portfolio value must be positive, got {value}")
    return (balance_a * price_a_in_b) / value


def tracking_error(balance_a: float, balance_b: float, price_a_in_b: float, target_weight_a: float) -> float:
    """Absolute deviation of A's realized value-weight from the LP's declared target."""
    return abs(weight_a(balance_a, balance_b, price_a_in_b) - target_weight_a)


def frictionless_reference_path(price_path: np.ndarray, v0: float, target_weight_a: float) -> np.ndarray:
    """Value path of a hypothetical portfolio starting at value `v0`, held EXACTLY at
    `target_weight_a` at every step, with zero fee/slippage/gas — the standard
    "constant-rebalanced-portfolio" benchmark.

    `V_ref(t) = V_ref(t-1) * (target_weight_a * price_ratio(t) + (1 - target_weight_a))`,
    where `price_ratio(t) = price_path[t] / price_path[t-1]` — only A's price moves
    (numeraire is B), and the reference is re-struck to target every single step.
    """
    if not 0 < target_weight_a < 1:
        raise ValueError(f"target_weight_a must be in (0, 1), got {target_weight_a}")
    price_ratios = price_path[1:] / price_path[:-1]
    step_returns = target_weight_a * price_ratios + (1 - target_weight_a)
    return v0 * np.concatenate(([1.0], np.cumprod(step_returns)))


def cost_of_rebalancing(actual_value_path: np.ndarray, reference_value_path: np.ndarray) -> np.ndarray:
    """Cumulative value lost relative to the frictionless reference, at every step.

    Both paths must start from the same `v0` and be the same length — a positive value
    means the actual (real, fee/slippage/gas/arb-paying) portfolio is behind where a free,
    instant rebalance would have left it; this is the "cost" ADR-0008 asks to minimize.
    """
    if actual_value_path.shape != reference_value_path.shape:
        raise ValueError(
            f"paths must be the same shape, got {actual_value_path.shape} vs {reference_value_path.shape}"
        )
    return reference_value_path - actual_value_path
