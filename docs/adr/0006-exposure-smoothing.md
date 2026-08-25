# ADR-0006: Exposure guardrails — a tolerance band and rate caps (no EMA/TWAP)

**Status:** Accepted — revised 2026-08-18 to drop the EMA/TWAP moving average, revised
2026-08-24 to pick concrete parameter values

## Context

The exposure reader (ADR-0002) reads a wallet's settled balance, which means it can move
in a single block — either from legitimate strategy settlement, another of the LP's own
strategies sharing the wallet, or from someone transferring tokens in deliberately (a donation,
see ADR-0007). The original version of this ADR fed that reading through an EMA or TWAP before
pricing, reasoning that a single-block change moving the quoted price instantly was a donation
vector.

**That reasoning didn't survive scrutiny — for donations.** ADR-0007's invariant proof
(`../INVARIANT-PROOF.md`) holds regardless of *how* the pre-trade balance got to be what it is,
for this strategy's own trades and for pure donations, as long as pricing reads the *current*
real balance directly. Smoothing didn't add donation resistance; it *cost* some, by introducing a
lag between the real balance and the quoted price that a patient attacker could trade against
during convergence — a harder, still-unresolved proof obligation (the abandoned "Part
2", see that file's git history) that the plain, un-smoothed curve never needed in the first
place. **Cross-strategy interaction turned out to need its own fix** (`ADR-0011`'s
Basket Scope Guard) — dropping smoothing didn't close that gap by itself; see the correction in
`../INVARIANT-PROOF.md`.

## Decision

No moving average. The exposure reading feeds the pricing engine directly off the current real
balance. Two guardrails remain, kept for cost/UX reasons, not security:

- **Tolerance band** — small deviations from target are priced as neutral, not corrective.
  Chosen value: **0.5%**.
- **Rate cap** — a ceiling on rebalancing frequency and amount per period. Chosen value:
  **1 hour minimum between corrective trades**.

Both values come from `simulation/notebooks/10_parameter_decision.ipynb`. Every dimension
that notebook measured — cost, tracking error, shock-recovery time, stale-quote exploit
exposure — gets monotonically worse as either knob loosens, so there's no genuine in-model
trade-off pushing toward these particular numbers over tighter ones; the mathematical
optimum found in that sweep is a 0.1% band with a 5-minute rate cap. The chosen values are a
deliberate, documented step back from that optimum: correction frequency (and so, gas cost —
a placeholder throughout this whole simulation series) scales directly with tightness, and
the chosen values allow up to 8,760 corrective transactions/year worst case versus
105,120/year at the mathematical optimum. Once a gas-per-rebalance number exists
(`BLEUDEV-265`), both knobs should tighten toward that optimum if the cost supports it — this
is a placeholder, not a final answer.

## Consequences

- Donation resistance no longer depends on any parameter choice here — it's fully closed by the
  curve invariant alone (`../INVARIANT-PROOF.md`). Cross-strategy resistance was never this
  ADR's job to close and still isn't — that's `ADR-0011`, enforced at the wallet level, not by
  any parameter picked here.
- The tolerance band and rate cap exist purely to reduce unnecessary rebalancing churn and cost
  from ordinary noise (including intra-group drift from another strategy on the shared wallet,
  which ADR-0003 already accepts by design) — not to bound an attack. Both are stateless
  functions of the *current* balance/timing, so neither reintroduces the lag problem EMA/TWAP
  had.
- Still introduces parameters — band width, rate-cap thresholds — picked from a
  tracking-error/cost-of-rebalancing simulation frontier (see ADR-0008), not a
  security-critical choice. Values above.

## Revised decision — under review, not yet applied to notebooks/other docs (2026-08-25)

The tolerance band and rate cap above are being replaced with a **fee + gas-cost
profitability gate** and nothing else: an arbitrageur's correction only fires if the drift
it captures is worth more than the trading fee plus their own (placeholder) gas cost.
Reasoning:

- A review comment asked whether the tolerance band was doing anything the trading fee
  didn't already do on its own — testing confirmed it wasn't: cost barely moved across the
  entire swept band range.
- Removing the band alone, with no fee for gas, made the mechanism correct on ~94% of all
  simulated 5-minute steps — unrealistic, since it implicitly assumes gas is free.
- Adding a *real* (placeholder) gas cost to the arbitrageur's own profitability check, with
  no separate cooldown, brought that down to ~577 corrections/year on its own — an explicit
  cooldown swept on top of the gas gate (5min through 1 day) changed nothing until set so
  loose it started making tracking *worse*. The gas gate alone already does the job a
  hand-picked cooldown was for.

Net effect: **no more free parameters to pick.** `fee` is fixed by ADR-0008 (2 bps); the gas
placeholder is the same one already used elsewhere in this simulation for un-modeled gas
($5, `BLEUDEV-265` still open). Nothing is left to sweep or tune — the mechanism has exactly
one real operating point.

**What that changes about the M1 comparison:** the old comparison swept the tolerance band
into a 5-point curve and checked whether *some* point on that curve beat each baseline
setting (that's where the "10/10" dominance claim came from). With one operating point
instead of a curve, the mechanism either beats a given baseline setting or it doesn't — no
cherry-picking a favorable point on a range. Checked against the same 10 baseline settings:

![Mechanism (single point) vs. naive baselines](assets/0006-mechanism-vs-baselines.png)

**1 of 10** baseline settings is beaten on both cost and tracking error at once (down from
the previously-claimed 10/10, and down from 2/10 measured right after the underlying
simulation bugs were fixed but before this parameter change). The mechanism's real strength
shows clearly on the chart: it has the *tightest tracking of anything tested* — no baseline
setting gets within 2x its tracking error. What it loses on is cost: several baseline
settings (most clearly threshold=0.05) get noticeably tighter tracking *and* lower cost
than the mechanism at once, because they tolerate more drift than the mechanism's real
economics ever would.

This section is a proposal for review, not yet carried through to `simulation/notebooks/`
(03, 05, 06, 07, 08, 09 all still construct the old tolerance-band/cooldown config, and
`10_parameter_decision.ipynb` — the notebook that picked 0.5%/1hr — still exists), or to
`ARCHITECTURE.md`/`ROADMAP.md`'s "10/10" and "All met" language. Those are a separate,
larger follow-up once this direction is confirmed.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Exposure Smoothing component notes
- [`../../simulation/notebooks/10_parameter_decision.ipynb`](../../simulation/notebooks/10_parameter_decision.ipynb) — the sweep and decision behind the tolerance-band/rate-cap values this ADR is moving away from (see "Revised decision" above)
