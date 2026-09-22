"""Floating-point weighted-curve model. Contract rounding guarantees are tested separately in Forge."""

from __future__ import annotations

from dataclasses import dataclass


class DegenerateBalanceError(ValueError):
    """A reserve is zero or negative."""


@dataclass(frozen=True)
class CurveState:
    """Balances and weights for the two sides of a weighted-curve swap."""

    balance_in: float
    balance_out: float
    weight_in: float
    weight_out: float

    def __post_init__(self) -> None:
        if self.balance_in <= 0 or self.balance_out <= 0:
            raise DegenerateBalanceError(
                f"both balances must be positive, got balance_in={self.balance_in}, "
                f"balance_out={self.balance_out}"
            )
        if self.weight_in <= 0 or self.weight_out <= 0:
            raise ValueError(
                f"both weights must be positive, got weight_in={self.weight_in}, "
                f"weight_out={self.weight_out}"
            )


def spot_price(state: CurveState) -> float:
    """Return (balance_in / weight_in) / (balance_out / weight_out), in input units per output unit before fees."""
    return (state.balance_in / state.weight_in) / (state.balance_out / state.weight_out)


def invariant(state: CurveState) -> float:
    """Return balance_in**weight_in * balance_out**weight_out for numerical invariant checks."""
    return state.balance_in**state.weight_in * state.balance_out**state.weight_out


def exact_in(state: CurveState, amount_in: float, fee: float) -> float:
    """Return output for an exact input using the formula in docs/PRICING.md. Floating-point arithmetic does not enforce directed rounding."""
    if not 0 <= fee < 1:
        raise ValueError(f"fee must be in [0, 1), got {fee}")
    if amount_in <= 0:
        raise ValueError(f"amount_in must be positive, got {amount_in}")

    amount_in_eff = amount_in * (1 - fee)
    ratio = state.balance_in / (state.balance_in + amount_in_eff)
    return state.balance_out * (1 - ratio ** (state.weight_in / state.weight_out))


def exact_out(state: CurveState, amount_out: float, fee: float) -> float:
    """Return fee-inclusive input for exact output using docs/PRICING.md. Floating-point arithmetic does not enforce directed rounding."""
    if not 0 <= fee < 1:
        raise ValueError(f"fee must be in [0, 1), got {fee}")
    if not 0 < amount_out < state.balance_out:
        raise ValueError(
            f"amount_out must be in (0, balance_out), got amount_out={amount_out}, "
            f"balance_out={state.balance_out}"
        )

    ratio = state.balance_out / (state.balance_out - amount_out)
    amount_in_eff = state.balance_in * (ratio ** (state.weight_in / state.weight_out) - 1)
    return amount_in_eff / (1 - fee)


def apply_exact_in(state: CurveState, amount_in: float, fee: float) -> tuple[CurveState, float]:
    """Return the updated CurveState and output amount. Add the full input, including the retained fee, to the input reserve."""
    amount_out = exact_in(state, amount_in, fee)
    new_state = CurveState(
        balance_in=state.balance_in + amount_in,
        balance_out=state.balance_out - amount_out,
        weight_in=state.weight_in,
        weight_out=state.weight_out,
    )
    return new_state, amount_out


def donate(state: CurveState, amount: float, *, into: str) -> CurveState:
    """Increase one reserve without an output leg. Set into to "in" or "out"."""
    if into == "in":
        return CurveState(
            balance_in=state.balance_in + amount,
            balance_out=state.balance_out,
            weight_in=state.weight_in,
            weight_out=state.weight_out,
        )
    if into == "out":
        return CurveState(
            balance_in=state.balance_in,
            balance_out=state.balance_out + amount,
            weight_in=state.weight_in,
            weight_out=state.weight_out,
        )
    raise ValueError(f'into must be "in" or "out", got {into!r}')
