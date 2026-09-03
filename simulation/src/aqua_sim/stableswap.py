"""StableSwap-style pricing for near-pegged pairs (e.g. USDC/USDT) — a constant-product
curve like `xyc.py`'s XYCSwap is a poor fit for two assets expected to trade near parity:
it has real slippage even for small trades near the peg, whereas Curve Finance's
StableSwap invariant (Egorov, 2019) blends a constant-sum curve (flat, near-zero slippage
near the peg) with a constant-product curve (only kicking in as balances diverge, for
stability at the extremes) via an amplification coefficient `A`.

n = 2 only: this module models exactly the two-stablecoin case this suite needs, not a
general n-asset StableSwap pool.
"""

from __future__ import annotations

from dataclasses import dataclass

_N = 2
_MAX_NEWTON_ITERATIONS = 255
_NEWTON_TOLERANCE = 1e-10


class DegenerateBalanceError(ValueError):
    """A swap was attempted against a zero (or negative) balance side of the pool."""


@dataclass(frozen=True)
class StableSwapState:
    """One pair's state for a 2-asset StableSwap pool. `amplification` (Curve's `A`)
    controls how flat the curve is near the 1:1 peg — higher `A` means lower slippage
    near parity, at the cost of more slippage once balances diverge far from 1:1.
    `A` near `0` degenerates toward `xyc.py`'s plain constant product; very large `A`
    degenerates toward a flat constant-sum curve.
    """

    balance_in: float
    balance_out: float
    amplification: float

    def __post_init__(self) -> None:
        if self.balance_in <= 0 or self.balance_out <= 0:
            raise DegenerateBalanceError(
                f"both balances must be positive, got balance_in={self.balance_in}, "
                f"balance_out={self.balance_out}"
            )
        if self.amplification <= 0:
            raise ValueError(f"amplification must be positive, got {self.amplification}")


def invariant_d(balance_in: float, balance_out: float, amplification: float) -> float:
    """Solves Curve's StableSwap invariant for `D` (the pool's notional total balance at
    perfect balance) via Newton's method — the standard iterative solve, n=2:
    `A*n^n*S + D = A*D*n^n + D^(n+1) / (n^n * P)`, `S = sum(balances)`, `P = prod(balances)`.
    """
    s = balance_in + balance_out
    ann = amplification * _N**_N
    d = s
    for _ in range(_MAX_NEWTON_ITERATIONS):
        d_p = d ** (_N + 1) / (_N**_N * balance_in * balance_out)
        d_prev = d
        d = (ann * s + d_p * _N) * d / ((ann - 1) * d + (_N + 1) * d_p)
        if abs(d - d_prev) <= _NEWTON_TOLERANCE * max(d, 1.0):
            break
    return d


def _solve_other_balance(balance_known: float, d: float, amplification: float) -> float:
    """Given one side's balance and the invariant `D` held constant, solves for the
    other side's balance via Newton's method — the standard `get_y`, n=2."""
    ann = amplification * _N**_N
    c = d ** (_N + 1) / (_N**_N * balance_known) / ann
    b = balance_known + d / ann
    y = d
    for _ in range(_MAX_NEWTON_ITERATIONS):
        y_prev = y
        y = (y * y + c) / (2 * y + b - d)
        if abs(y - y_prev) <= _NEWTON_TOLERANCE * max(y, 1.0):
            break
    return y


def spot_price(state: StableSwapState) -> float:
    """SP(i->o) = units of i paid per unit of o received, at the current balances,
    matching `xyc.py`'s `spot_price` convention exactly. Computed via a tiny numerical
    trade rather than the closed-form marginal price — simpler to verify correct, and a
    1e-6-relative trade is small enough that quoting/gating logic never notices the
    difference."""
    epsilon = state.balance_in * 1e-6
    amount_out = exact_in(state, epsilon, fee=0.0)
    return epsilon / amount_out


def exact_in(state: StableSwapState, amount_in: float, fee: float) -> float:
    """Amount of token o received for a given amount of token i sent in, holding the
    invariant `D` constant through the trade (net of fee) — same fee convention as
    `xyc.py`'s `exact_in`."""
    if not 0 <= fee < 1:
        raise ValueError(f"fee must be in [0, 1), got {fee}")
    if amount_in <= 0:
        raise ValueError(f"amount_in must be positive, got {amount_in}")

    amount_in_eff = amount_in * (1 - fee)
    d = invariant_d(state.balance_in, state.balance_out, state.amplification)
    new_balance_in = state.balance_in + amount_in_eff
    new_balance_out = _solve_other_balance(new_balance_in, d, state.amplification)
    return state.balance_out - new_balance_out


def apply_exact_in(state: StableSwapState, amount_in: float, fee: float) -> tuple[StableSwapState, float]:
    """Applies an exact-in trade, returning the resulting `StableSwapState` and amount_out.

    The *full* `amount_in` (fee included) lands in the real balance, same rationale as
    `xyc.py`'s `apply_exact_in`.
    """
    amount_out = exact_in(state, amount_in, fee)
    new_state = StableSwapState(
        balance_in=state.balance_in + amount_in,
        balance_out=state.balance_out - amount_out,
        amplification=state.amplification,
    )
    return new_state, amount_out
