# ADR-0004: Price with an independently-implemented constant-mean weighted curve

**Status:** Accepted — supersedes the original oracle-anchored ± bounded-spread design

## Context

Two pricing designs were on the table:

- **Design B (original):** execute at the oracle reference price ± a capped, explicitly computed rebalancing spread — a discount for skew-reducing trades, a surcharge for skew-worsening ones, bounded at `C_rebate`. This requires proving, separately, that the rebate can never be gamed into a round-trip profit — not automatically safe, since the rebate is a payment layered on top of a reference price, not a property of an invariant.
- **Design A (adopted):** a constant-mean weighted curve — Balancer's weighted-pool math — where the oracle only sets *relative* token value, and the curve's own invariant does the pricing. Big trades get worse prices on their own (price impact), and a closed round-trip can never reduce the pool's value, by construction of the invariant — the round-trip-profit proof reduces to a standard weighted-pool proof instead of a bespoke one.

Importing Balancer's Solidity (rather than reimplementing the formula) was considered and rejected: `lib/balancer-v3-monorepo` ships under GPL-3.0, incompatible with shipping this repo's code under Aqua-Source-1.1 ([`ADR-0001`](0001-license-under-aqua-source-not-mit.md)) — GPL's copyleft would force either relicensing this repo's own code or ring-fencing the imported files under a second, conflicting license. The formula itself is public (Balancer's 2019 whitepaper) and unpatented as far as known, so this repo implements it from scratch instead — same math, no license conflict. `lib/balancer-v3-monorepo` stays reference-only, never imported from `src/` (`THIRD_PARTY_NOTICES.md`). This is new territory for Aqua either way: swapVM currently ships xy=k, concentrated, pegged, and stable-swap curves, not constant-mean.

The best-known public example of this math: Balancer's 80/20 BAL/WETH pool.

## Decision

Pricing uses a constant-mean weighted curve (Balancer-style weighted-pool math), reimplemented independently from the published formula — not Balancer's code (see Context above for why copying it directly isn't available: GPL-3.0 vs. this repo's Aqua-Source-1.1), and not the oracle ± spread design.

## Consequences

- The round-trip-always-favors-the-pool property becomes a proof obligation for this specific implementation (Milestone 1's headline security deliverable — see ADR-0007), not something inherited for free just by citing Balancer's whitepaper.
- Reframes what "the innovation" is: not the curve itself (that's the settlement engine), but the layer above it — group targets, the declared-universe exposure read (ADR-0002/0003), and Chainlink-anchored valuation (ADR-0005).
- Team has prior Balancer-contributor experience, which strengthens the implementation and audit story for M3/M4 — but this ADR's decision doesn't depend on that continuing to be true.
- The invariant proof uses real arithmetic; conservative implementation rounding is established separately. Both quote paths reject zero balances and use `FixedPointMath.powUp`. Exact-in floors the effective input, weight ratio, and output, while ceiling the balance ratio. Its base is at most one, so flooring the exponent also increases the subtracted power. It retains the full-drain guard and, except when its computed exponent equals one, the `poweredRatio >= WAD / 1e9` floor. That floor is separate from a minimum-balance threshold and is no longer the basis for the quote's rounding guarantee.
- Shared `powDown`/`powUp` derive directed bounds from the pinned PRBMath `log2`/`exp2` source and use directed reciprocals below one. Bounds must be rechecked on dependency upgrades. Intermediate reciprocal powers can exceed the supported domain and revert even when the final result would fit. Exact-out ceilings the balance and weight ratios, effective input, and fee gross-up; its conservative bound can overquote tiny trades.
- Native-token/value conversions round down for exact-in and up for exact-out. Shared multiplication/division support WAD or an explicit scale; `scaleDown`/`scaleUp` name rounding direction rather than the direction of decimal conversion. The pricing-library guarantees concern supplied inputs, not arbitrary oracle answers, normalization, or settlement behavior. See [`../PRICING.md`](../PRICING.md) for the rounding rules and guards.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Pricing Engine component notes
