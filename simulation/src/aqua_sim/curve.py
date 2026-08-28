"""Constant-mean weighted curve pricing — floating-point reimplementation of
``docs/PRICING.md`` for economic simulation.

This is NOT the on-chain source of truth. The real strategy is Solidity,
fixed-point, with rounding that always favors the pool (floor on exact-in output,
ceil throughout exact-out — see ``docs/PRICING.md``'s "Rounding" notes and
``docs/INVARIANT-PROOF.md``). This module trades that rounding discipline for
speed and precision, since a market simulation runs the formula millions of times
across parameter sweeps and rounding-direction bias would not change which
parameters look best — only the on-chain contract's own Forge test suite is the
place that proof-grade rounding behavior gets verified.
"""

from __future__ import annotations

from dataclasses import dataclass


class DegenerateBalanceError(ValueError):
    """A swap was attempted against a zero (or negative) balance side of the curve.

    Mirrors ``docs/PRICING.md``'s "Degenerate cases": "B_i == 0 or B_o == 0: revert."
    """


@dataclass(frozen=True)
class CurveState:
    """One pool side-pair's state: the two balances and weights a swap prices against.

    Field names match ``docs/PRICING.md`` exactly (``B_i``, ``B_o``, ``w_i``, ``w_o``)
    so the formulas below can be read side by side with that document.
    """

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
    """SP(i->o) = (B_i / w_i) / (B_o / w_o) — PRICING.md "Spot price".

    Units of i paid per unit of o received, before fees — i.e. the price of o
    denominated in i.
    """
    return (state.balance_in / state.weight_in) / (state.balance_out / state.weight_out)


def invariant(state: CurveState) -> float:
    """V = B_i^w_i * B_o^w_o — INVARIANT-PROOF.md's round-trip invariant.

    Proven (see that file) to never decrease across a trade priced by this curve,
    and to strictly increase on a pure donation. Used here as a numerical check,
    not as a proof — the proof itself is algebraic, done once, in that document.
    """
    return state.balance_in**state.weight_in * state.balance_out**state.weight_out


def exact_in(state: CurveState, amount_in: float, fee: float) -> float:
    """Amount of token o received for a given amount of token i sent in.

    PRICING.md "Exact-in swap":
        A_i_eff = A_i * (1 - f)
        A_o = B_o * (1 - (B_i / (B_i + A_i_eff))^(w_i / w_o))

    The real contract floors A_o (the pool keeps the remainder). This function
    returns the exact float — callers that need the pool-favoring rounding for a
    specific check should floor the result themselves.
    """
    if not 0 <= fee < 1:
        raise ValueError(f"fee must be in [0, 1), got {fee}")
    if amount_in <= 0:
        raise ValueError(f"amount_in must be positive, got {amount_in}")

    amount_in_eff = amount_in * (1 - fee)
    ratio = state.balance_in / (state.balance_in + amount_in_eff)
    return state.balance_out * (1 - ratio ** (state.weight_in / state.weight_out))


def exact_out(state: CurveState, amount_out: float, fee: float) -> float:
    """Amount of token i that must be sent in for a given amount of token o out.

    PRICING.md "Exact-out swap":
        A_i_eff = B_i * ((B_o / (B_o - A_o))^(w_i / w_o) - 1)
        A_i = A_i_eff / (1 - f)

    The real contract ceils throughout. As with `exact_in`, this returns the exact
    float; callers needing pool-favoring rounding should ceil the result themselves.
    """
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
    """Applies an exact-in trade, returning the resulting `CurveState` and amount_out.

    The *full* `amount_in` (fee included) lands in the real balance — PRICING.md:
    "the full A_i (fee included) is what actually lands in the wallet's real
    balance — this is what lets the fee show up as a strict invariant increase."
    """
    amount_out = exact_in(state, amount_in, fee)
    new_state = CurveState(
        balance_in=state.balance_in + amount_in,
        balance_out=state.balance_out - amount_out,
        weight_in=state.weight_in,
        weight_out=state.weight_out,
    )
    return new_state, amount_out


def donate(state: CurveState, amount: float, *, into: str) -> CurveState:
    """A pure, one-sided balance increase — no output leg (PRICING.md/ADR-0007's
    "donation": an unsolicited transfer meant to skew the reading).

    `into` must be `"in"` or `"out"`, selecting which side of the pair receives it.
    """
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
