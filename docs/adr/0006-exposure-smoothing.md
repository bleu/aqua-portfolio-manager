# ADR-0006: Exposure guardrails — a tolerance band and rate caps (no EMA/TWAP)

**Status:** Accepted — revised 2026-08-18 to drop the EMA/TWAP moving average

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
during convergence — a genuinely harder, still-unresolved proof obligation (the abandoned "Part
2", see that file's git history) that the plain, un-smoothed curve never needed in the first
place. **Cross-strategy interaction turned out to need its own, separate fix** (`ADR-0011`'s
Basket Scope Guard) — dropping smoothing didn't close that gap by itself; see the correction in
`../INVARIANT-PROOF.md`.

## Decision

No moving average. The exposure reading feeds the pricing engine directly off the current real
balance. Two guardrails remain, kept for cost/UX reasons, not security:

- **Tolerance band** — small deviations from target are priced as neutral, not corrective.
- **Rate cap** — a ceiling on rebalancing frequency and amount per period.

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
- Still introduces parameters — band width, rate-cap thresholds — with no fixed values yet;
  picking them is still a Milestone 1 simulation deliverable, benchmarked against a
  tracking-error/cost-of-rebalancing frontier (see ADR-0008), just no longer a security-critical
  choice.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Exposure Smoothing component notes
