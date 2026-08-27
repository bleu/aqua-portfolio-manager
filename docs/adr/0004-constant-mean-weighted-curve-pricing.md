# ADR-0004: Price with an independently-implemented constant-mean weighted curve

**Status:** Accepted — supersedes the original oracle-anchored ± bounded-spread design

## Context

Two pricing designs were on the table:

- **Design B (original):** execute at the oracle reference price ± a capped, explicitly
  computed rebalancing spread — a discount for skew-reducing trades, a surcharge for
  skew-worsening ones, bounded at `C_rebate`. This requires proving, separately, that the
  rebate can never be gamed into a round-trip profit — not automatically safe, since the
  rebate is a payment layered on top of a reference price, not a property of an invariant.
- **Design A (adopted):** a constant-mean weighted curve — Balancer's weighted-pool math — where
  the oracle only sets *relative* token value, and the curve's own invariant does the pricing.
  Big trades get worse prices on their own (price impact), and a closed round-trip can never
  reduce the pool's value, by construction of the invariant — the round-trip-profit proof
  reduces to a standard weighted-pool proof instead of a bespoke one.

Importing Balancer's actual Solidity (rather than reimplementing the formula) was considered
and rejected: `lib/balancer-v3-monorepo` ships under GPL-3.0, incompatible with shipping this
repo's code under Aqua-Source-1.1 ([`ADR-0001`](0001-license-under-aqua-source-not-mit.md)) —
GPL's copyleft would force either relicensing this repo's own code or ring-fencing the imported
files under a second, conflicting license. The formula itself is public (Balancer's 2019
whitepaper) and unpatented as far as known, so this repo implements it from scratch instead —
same math, no license conflict. `lib/balancer-v3-monorepo` stays reference-only, never imported
from `src/` (`THIRD_PARTY_NOTICES.md`). This is new territory for Aqua either way: swapVM
currently ships xy=k, concentrated, pegged, and stable-swap curves, not constant-mean.

The best-known public example of this math: Balancer's 80/20 BAL/WETH pool.

## Decision

Pricing uses a constant-mean weighted curve (Balancer-style weighted-pool math), reimplemented
independently from the published formula — not Balancer's code (see Context above for why
copying it directly isn't available: GPL-3.0 vs. this repo's Aqua-Source-1.1), and not the
oracle ± spread design.

## Consequences

- The round-trip-always-favors-the-pool property becomes a proof obligation for this specific
  implementation (Milestone 1's headline security deliverable — see ADR-0007), not something
  inherited for free just by citing Balancer's whitepaper.
- Reframes what "the innovation" is: not the curve itself (that's the settlement engine), but
  the layer above it — group targets, the declared-universe exposure read (ADR-0002/0003), and
  Chainlink-anchored valuation (ADR-0005).
- Team has prior Balancer-contributor experience, which strengthens the implementation and
  audit story for M3/M4 — but this ADR's decision doesn't depend on that continuing to be true.
- Precision/edge behavior near an empty pool needs the same handling as any weighted pool
  (minimum-liquidity floor, round in the pool's favor).

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Pricing Engine component notes
