"""Floating-point xy=k model of SwapVM XYCSwap. Independent of PM group weights and the weighted-curve implementation."""

from __future__ import annotations

from dataclasses import dataclass


class DegenerateBalanceError(ValueError):
    """A swap was attempted against a zero (or negative) balance side of the pool."""


@dataclass(frozen=True)
class XYCState:
    """One pool side-pair's state for a plain constant-product curve."""

    balance_in: float
    balance_out: float

    def __post_init__(self) -> None:
        if self.balance_in <= 0 or self.balance_out <= 0:
            raise DegenerateBalanceError(
                f"both balances must be positive, got balance_in={self.balance_in}, "
                f"balance_out={self.balance_out}"
            )


def spot_price(state: XYCState) -> float:
    """Return balance_in / balance_out, in input units per output unit before fees."""
    return state.balance_in / state.balance_out


def invariant(state: XYCState) -> float:
    """k = balance_in * balance_out. Never decreases across a fee-paying trade, same
    proof shape as `curve.py`'s weighted invariant (see `DONATION-RESISTANCE-PROOF.md`)."""
    return state.balance_in * state.balance_out


def exact_in(state: XYCState, amount_in: float, fee: float) -> float:
    """Return output with constant product after deducting the input fee."""
    if not 0 <= fee < 1:
        raise ValueError(f"fee must be in [0, 1), got {fee}")
    if amount_in <= 0:
        raise ValueError(f"amount_in must be positive, got {amount_in}")

    amount_in_eff = amount_in * (1 - fee)
    k = state.balance_in * state.balance_out
    new_balance_out = k / (state.balance_in + amount_in_eff)
    return state.balance_out - new_balance_out


def apply_exact_in(state: XYCState, amount_in: float, fee: float) -> tuple[XYCState, float]:
    """Applies an exact-in trade, returning the resulting `XYCState` and amount_out.

    The *full* `amount_in` (fee included) lands in the real balance, same rationale as
    `curve.py`'s `apply_exact_in`.
    """
    amount_out = exact_in(state, amount_in, fee)
    new_state = XYCState(
        balance_in=state.balance_in + amount_in,
        balance_out=state.balance_out - amount_out,
    )
    return new_state, amount_out
