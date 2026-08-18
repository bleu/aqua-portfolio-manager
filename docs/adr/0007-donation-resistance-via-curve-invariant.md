# ADR-0007: Rely on the curve invariant, not internal accounting, for donation-attack resistance

**Status:** Accepted — round-trip proof complete (`../INVARIANT-PROOF.md`, 2026-08-18)

## Context

Because the exposure reader reads a real wallet's balance (ADR-0002), anyone can transfer
tokens into that wallet to skew the reading — the same family of attack as a Uniswap `sync()`
donation. Two mitigations were considered:

- **Internal accounting** (the textbook fix: track only what this strategy's own trades moved,
  ignore the wallet's raw balance). Donation-proof by construction, but it defeats the entire
  point of this design — it can no longer see the *net* exposure across the LP's other
  strategies sharing the same wallet, which is the problem being solved (ADR-0002). Rejected.
- **Bound what a donation can extract, rather than preventing the donation.** The constant-mean
  curve's invariant (ADR-0004) guarantees a closed round-trip trade always ends slightly in the
  pool's favor — so a donated token isn't something a trader can round-trip back out at a
  profit.

## Decision

Donation-attack resistance comes entirely from the pricing curve's invariant (no trade sequence
can reduce the pool's value), not from tracking only self-attributed balance changes, and not
from smoothing (ADR-0006 dropped the EMA/TWAP that earlier drafts of this ADR leaned on — the
invariant alone turned out to be unconditionally sufficient, with no dependency on how fast a
donation's effect on price shows up).

## Consequences

- The honest residual is pure vandalism: burning your own tokens into someone else's wallet to
  nudge their weights, for zero extractable gain. Accepted as unpreventable but economically
  irrational.
- "No donation attack is ever profitable" is proven, not just asserted — see
  `../INVARIANT-PROOF.md` for the full proof, including why it holds unconditionally for
  external donations, ordinary settlement, and same-LP cross-strategy interaction (ADR-0002)
  alike, with no dependency on smoothing parameters.
- The same round-trip proof also closes the "round-trip drain via the rebate" concern and the
  near-empty-pool precision concern — one proof obligation, three issues.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Curve invariant component notes
