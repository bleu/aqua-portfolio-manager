"""Two-asset StableSwap model based on Egorov (2019), with amplification between constant-product and constant-sum behavior."""

from __future__ import annotations

from dataclasses import dataclass

_N = 2
_MAX_NEWTON_ITERATIONS = 255
_NEWTON_TOLERANCE = 1e-10


class DegenerateBalanceError(ValueError):
    """A swap was attempted against a zero (or negative) balance side of the pool."""


@dataclass(frozen=True)
class StableSwapState:
    """Two-asset reserves and amplification. Higher amplification reduces slippage near parity and concentrates it at larger imbalances."""

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
    """Solve for D with Newton iteration at n=2.

    A*n^n*S + D = A*D*n^n + D^(n+1)/(n^n*P), with S=sum(balances) and P=prod(balances)."""
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
    """Approximate the marginal input-per-output price with a trade of 1e-6 times the input reserve."""
    epsilon = state.balance_in * 1e-6
    amount_out = exact_in(state, epsilon, fee=0.0)
    return epsilon / amount_out


def exact_in(state: StableSwapState, amount_in: float, fee: float) -> float:
    """Return output for exact input while holding D constant after deducting the input fee."""
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
