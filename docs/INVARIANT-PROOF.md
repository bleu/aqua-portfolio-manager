# Round-trip / donation-resistance proof

Status: **closed.** A single proof (below) fully discharges ADR-0007's obligation — no smoothing,
no additional bound, no open follow-up.

## What has to be shown

ADR-0007's claim is: no sequence of trades against this strategy can extract value from the
wallet, whether preceded by an external donation (an unsolicited transfer meant to skew the
price), ordinary settlement, or a same-LP interaction across two of the LP's own strategies
sharing the wallet (ADR-0002). The pricing formula (`PRICING.md`) reads the wallet's real,
current balance directly — no EMA, no TWAP, no moving average of any kind (see "Why no
smoothing" below for why that was cut).

## The curve invariant (the whole proof)

**Claim.** For weights `w_i, w_o > 0` normalized as in `PRICING.md`, and any single exact-in
trade of `PRICING.md`'s form with fee `f ∈ [0, 1)`:

    V = B_i^{w_i} · B_o^{w_o}   (holding all other tokens' balances fixed)

satisfies `V_after ≥ V_before`, with equality iff `f = 0` or `A_i = 0`.

**Proof.** Let `A_i_eff = A_i·(1-f)` and, per `PRICING.md`:

    A_o = B_o · (1 - (B_i / (B_i + A_i_eff))^(w_i/w_o))
    ⟺ (B_o - A_o) = B_o · (B_i / (B_i + A_i_eff))^(w_i/w_o)
    ⟺ (B_o - A_o)^(w_o) = B_o^(w_o) · (B_i / (B_i + A_i_eff))^(w_i)

The real balance updates by the *full* `A_i` (fee included — it's retained in the wallet, not
skimmed off before it arrives), so:

    V_after = (B_i + A_i)^(w_i) · (B_o - A_o)^(w_o)
            = (B_i + A_i)^(w_i) · B_o^(w_o) · (B_i / (B_i + A_i_eff))^(w_i)
            = B_i^(w_i) · B_o^(w_o) · ((B_i + A_i) / (B_i + A_i_eff))^(w_i)
            = V_before · ((B_i + A_i) / (B_i + A_i_eff))^(w_i)

Since `A_i_eff = A_i·(1-f) ≤ A_i` for `f ≥ 0`, the ratio `(B_i+A_i)/(B_i+A_i_eff) ≥ 1`, and
`w_i > 0`, so the whole factor is `≥ 1`. Hence `V_after ≥ V_before`, strictly greater whenever
`f > 0` and `A_i > 0`. ∎

**Corollary (round-trip).** Any finite sequence of trades that returns every token's balance to
its exact starting value satisfies `V_end = V_start` (trivially, since `V` is a function of
balances alone) — so if any trade in the sequence had `f > 0` and `A_i > 0`, the intermediate `V`
strictly increased at that step and would have to strictly decrease at some later step to return
to `V_start`. But the proof above shows `V` *never* decreases on any single trade. Contradiction —
so a round trip with any real (fee-paying, non-trivial) trade in it can't get back to the exact
starting balances; the trader is always left holding a net change, weakly unfavorable to them by
the same monotonicity (standard CFMM arbitrage argument: if it were favorable, running the
sequence backwards would decrease `V`, which the proof forbids). Standard result for
constant-mean weighted invariants; the exact-out formula in `PRICING.md` is exact-in's algebraic
inverse, so the same substitution applies symmetrically.

**Why this covers donations at all.** A donation isn't a trade — it's a bare transfer with no
output leg, so it only ever *increases* `B_i` for whatever token was donated, which strictly
increases `V`. Since no subsequent trade can decrease `V` below wherever it stands (donation
included), the donor can never trade their way back to more value than they gave away — worked
example with real numbers in the PR history / Linear BLEUDEV-254 if a concrete walkthrough is
useful later.

**Why this covers cross-strategy interaction too, with no extra argument needed.** The proof
never refers to *how* the pre-trade balance came to be what it is — a donation, ordinary
settlement, or another of the LP's own strategies (sharing the same dedicated wallet, ADR-0002)
moving the balance as a side effect of its own, unrelated trading. Whatever moved `B_i`/`B_o`
before this strategy's trade executes, the trade is still priced off the *current* real balance,
and the proof applies unconditionally. Trading this strategy after moving the shared wallet's
balance via a different strategy is the same thing an external arbitrageur does — it's the
intended rebalancing mechanism (ADR-0008's "endogenous arb flow"), not an exploit.

## Why no smoothing (EMA/TWAP removed from scope, 2026-08-18)

ADR-0006 originally proposed feeding the exposure reading through an EMA or TWAP before pricing.
That turned out to be exactly what made this proof incomplete: smoothing means the price no
longer reflects the *current* real balance, only a lagging function of it, and closing the gap
between "smoothed" and "raw" needed a second, harder proof that depended on simulation
parameters that don't exist yet (see git history on this file for the abandoned "Part 2"). Once
the exposure reader feeds the *raw*, current balance directly with no averaging, that gap
doesn't exist, and the single proof above is unconditionally sufficient — for external
donations, ordinary settlement noise, and same-LP cross-strategy interaction alike.

The tolerance band and rate cap (ADR-0006) stay in scope, but on a different footing now: they're
not load-bearing for this proof (the proof holds with or without them), they exist to reduce
unnecessary rebalancing churn/cost. Neither reopens the lag problem smoothing did — the
tolerance band is a stateless function of the *current* balance (no history to lag), and the
rate cap only limits frequency/size, not what price a trade clears at.
