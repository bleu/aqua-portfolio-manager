# ADR-0004: Price with an independently-implemented constant-mean weighted curve

**Status:** Accepted — supersedes the original oracle-anchored ± bounded-spread design

## Context

Two pricing designs were on the table (bleu-brain context.md, "Design A" vs. the original
decision 5):

- **Design B (original):** execute at the oracle reference price ± a capped, explicitly
  computed rebalancing spread — a discount for skew-reducing trades, a surcharge for
  skew-worsening ones, bounded at `C_rebate`. This requires proving, separately, that the
  rebate can never be gamed into a round-trip profit (critique.md, 1.3) — not automatically
  safe, since the rebate is a payment layered on top of a reference price, not a property of
  an invariant.
- **Design A (adopted):** a constant-mean weighted curve — Balancer's weighted-pool math — where
  the oracle only sets *relative* token value, and the curve's own invariant does the pricing.
  Big trades get worse prices on their own (price impact), and a closed round-trip can never
  reduce the pool's value, by construction of the invariant — the round-trip-profit proof
  reduces to a standard weighted-pool proof instead of a bespoke one.

This reversed the original scope defense (context.md decision 10 was originally "not Balancer's
weighted math") and reopened a scope conflict: the grant's out-of-scope list bans "AMM
formulas/mechanisms licensed by third parties." That conflict is resolved by separating the
*formula* (public, from Balancer's 2019 whitepaper, unpatented as far as known) from Balancer's
*Solidity* (GPL-3.0) — this repo implements the formula from scratch and never imports
Balancer's code (see `lib/balancer-v3-monorepo`'s reference-only status in
[`ADR-0001`](0001-license-under-aqua-source-not-mit.md) / `THIRD_PARTY_NOTICES.md`). 1inch
confirmed (via Tanner) that an independently-implemented, new-to-Aqua weighted curve is in
scope — swapVM currently ships xy=k, concentrated, pegged, and stable-swap curves, not
constant-mean.

The best-known public example of this math: Balancer's 80/20 BAL/WETH pool.

## Decision

Pricing uses a constant-mean weighted curve (Balancer-style weighted-pool math), reimplemented
independently from the published formula — not Balancer's code, and not the oracle ± spread
design.

## Consequences

- The round-trip-always-favors-the-pool property becomes a proof obligation for this specific
  implementation (Milestone 1's headline security deliverable — see ADR-0007), not something
  inherited for free just by citing Balancer's whitepaper.
- Reframes what "the innovation" is: not the curve itself (that's the settlement engine), but
  the layer above it — group targets, the declared-universe exposure read (ADR-0002/0003), and
  Chainlink-anchored valuation (ADR-0005). The scope defense in bleu-brain's
  `application.md`/`context.md` decision 10 was rewritten to argue exactly this.
- Team has prior Balancer-contributor experience, which strengthens the implementation and
  audit story for M3/M4 — but this ADR's decision doesn't depend on that continuing to be true.
- Precision/edge behavior near an empty pool needs the same handling as any weighted pool
  (minimum-liquidity floor, round in the pool's favor — critique.md, 1.11).

## References

- bleu-brain `1inch-aqua-incubator/portfolio-manager/context.md`, decision 5 (superseded) and
  decision 10 (rewritten)
- bleu-brain `1inch-aqua-incubator/portfolio-manager/critique.md`, "Decisions locked" and
  "Design decided: Balancer weighted math" sections, issues 1.2, 1.3, 1.11
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Pricing Engine component notes
