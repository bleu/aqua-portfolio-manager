# ADR-0007: Rely on the curve invariant, not internal accounting, for donation-attack resistance

**Status:** Accepted — round-trip proof still owed by Milestone 1

## Context

Because the exposure reader reads a real wallet's balance (ADR-0002), anyone can transfer
tokens into that wallet to skew the reading — the same family of attack as Uniswap `sync()` or
ERC-4626 inflation attacks. Two mitigations were considered:

- **Internal accounting** (the textbook fix: track only what this strategy's own trades moved,
  ignore the wallet's raw balance). Donation-proof by construction, but it defeats the entire
  point of this design — it can no longer see the *net* exposure across the LP's other
  strategies sharing the same wallet, which is the problem being solved (ADR-0002). Rejected.
- **Bound what a donation can extract, rather than preventing the donation.** The constant-mean
  curve's invariant (ADR-0004) guarantees a closed round-trip trade always ends slightly in the
  pool's favor — so a donated token isn't something a trader can round-trip back out at a
  profit. Combined with exposure smoothing (ADR-0006) bounding how fast a donation can move the
  quoted price, the donation becomes an irreversible gift to the wallet rather than an
  extractable griefing vector.

## Decision

Donation-attack resistance comes from the pricing curve's invariant (no trade sequence can
reduce the pool's value) plus smoothing (bounding how fast a donation moves the read), not from
tracking only self-attributed balance changes.

## Consequences

- The honest residual is pure vandalism: burning your own tokens into someone else's wallet to
  nudge their weights, for zero extractable gain. Accepted as unpreventable but economically
  irrational, and further blunted by smoothing (critique.md, 1.5.3).
- This is not automatically true — it's true *given the invariant holds for this specific
  implementation*. Proving "no donation attack is ever profitable" is named a project MUST and
  the headline security deliverable for Milestone 1 (critique.md, 1.5, MoSCoW item 5), combining
  the invariant proof with a bound on smoothed-reading movement. Not yet demonstrated with
  numbers — this ADR records the design intent, not a completed proof.
- The same round-trip proof also closes the "round-trip drain via the rebate" concern
  (critique.md, 1.3) and the near-empty-pool precision concern (1.11) — one proof obligation,
  three issues.

## References

- bleu-brain `1inch-aqua-incubator/portfolio-manager/context.md`, decision 11
- bleu-brain `1inch-aqua-incubator/portfolio-manager/critique.md`, issues 1.3, 1.5, 1.5.2, 1.5.3,
  1.11, and "What M1 must decide or prove" item 5
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Curve invariant component notes
