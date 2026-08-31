# ADR-0007: Rely on the curve invariant, not internal accounting, for donation-attack resistance

**Status:** Accepted — round-trip proof complete (`../DONATION-RESISTANCE-PROOF.md`)

## Context

Because the exposure reader reads a real wallet's balance (ADR-0002), anyone can transfer tokens into that wallet to skew the reading — the same family of attack as a Uniswap `sync()` donation. Two mitigations were considered:

- **Internal accounting** (the textbook fix: track only what this strategy's own trades moved, ignore the wallet's raw balance). Donation-proof by construction, but it defeats the entire point of this design — it can no longer see the *net* exposure across the LP's other strategies sharing the same wallet, which is the problem being solved (ADR-0002). Rejected.
- **Bound what a donation can extract, rather than preventing the donation.** The constant-mean curve's invariant (ADR-0004) guarantees a closed round-trip trade always ends slightly in the pool's favor — so a donated token isn't something a trader can round-trip back out at a profit.

## Decision

Donation-attack resistance comes entirely from the pricing curve's invariant (no trade sequence can reduce the pool's value), not from tracking only self-attributed balance changes, and not from smoothing (ADR-0006 dropped the EMA/TWAP that earlier drafts of this ADR leaned on — the invariant alone turned out to be unconditionally sufficient, with no dependency on how fast a donation's effect on price shows up).

## Consequences

- The honest residual is pure vandalism: burning your own tokens into someone else's wallet to nudge their weights, for zero extractable gain. Accepted as unpreventable but economically irrational.
- "No donation attack is ever profitable" is proven, not just asserted — see `../DONATION-RESISTANCE-PROOF.md` for the full proof, covering PM's own trades and external donations, with no dependency on smoothing parameters.
- This proof does not, on its own, cover a trade by a *different* strategy sharing the same wallet — that's two-sided (it can remove value from one side while adding to another), unlike a donation. `ADR-0011`'s Basket Scope Guard is what closes that gap, by confining every other strategy to trading within one group — see `../DONATION-RESISTANCE-PROOF.md` for the full reasoning.
- The same round-trip proof also closes the "round-trip drain via the rebate" concern and the near-empty-pool precision concern — one proof obligation, three issues.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Curve invariant component notes
- [`0011-safe-wallet-with-basket-scope-guard.md`](0011-safe-wallet-with-basket-scope-guard.md) — what actually makes this proof's "only PM, or a donation" precondition true for cross-strategy activity
