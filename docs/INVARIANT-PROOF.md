# Round-trip / donation-resistance proof

A single proof (below) fully discharges ADR-0007's obligation for this strategy's own trades and
for pure donations — no smoothing, no additional bound needed for either. **Cross-strategy
interaction (a different strategy on the same wallet moving the balance) is a separate case this
proof does not cover** — see below. That gap is closed structurally instead, by `ADR-0011`'s
Basket Scope Guard.

## What has to be shown

ADR-0007's claim is: no sequence of trades against this strategy can extract value from the
wallet, whether preceded by an external donation (an unsolicited transfer meant to skew the
price) or ordinary settlement. The pricing formula (`PRICING.md`) reads the wallet's real,
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
included), the donor can never trade their way back to more value than they gave away.

**Why this does not automatically cover cross-strategy interaction.** The proof above (lines
17-40) shows `V` never decreases across a trade that follows *this strategy's own* formula
(`PRICING.md`) — it says nothing about a trade against a *different* strategy's curve, which
follows different math entirely and can move this strategy's `B_i`/`B_o` in a way that decreases
`V` relative to where it stood a moment before. `thoughts/cross-strategy-manipulation.md` found a
concrete, worked exploit through exactly this gap: another strategy's trade can leave this
strategy's curve mispriced relative to true value, and a subsequent trade against *this*
strategy — while still individually invariant-preserving relative to its own immediate input —
extracts real value that was never actually available to begin with.

What closes this instead is `ADR-0011`: a Safe Transaction Guard that prevents any strategy but
this one from ever moving tokens across a group boundary (ADR-0003) or in from outside the
declared universe. That confines any other strategy's activity to *within* one group — and
because ADR-0003 already treats intra-group composition as unpriced (only the group's
oracle-valued total feeds this curve), a within-group trade by another strategy reduces to
exactly the one-sided "donation" case this proof already covers. The proof isn't stronger than it
was; the boundary it needs now actually holds, enforced outside this contract entirely.

## Proof precondition: no smoothing

This proof requires the exposure reader to feed the *raw*, current balance directly, with no
EMA/TWAP averaging — smoothing would mean the price reflects a lagging function of the balance
rather than the balance itself, which the proof above doesn't account for. See ADR-0006 for why
no smoothing is used. With a raw reading, the proof above is unconditionally sufficient for
external donations and ordinary settlement noise (cross-strategy interaction needed a different
fix entirely, not more of this proof — see above and `ADR-0011`).

The tolerance band and rate cap (ADR-0006) stay in scope, but on a different footing now: they're
not load-bearing for this proof (the proof holds with or without them), they exist to reduce
unnecessary rebalancing churn/cost. Neither reopens the lag problem smoothing did — the
tolerance band is a stateless function of the *current* balance (no history to lag), and the
rate cap only limits frequency/size, not what price a trade clears at.
