# ADR-0005: Use Chainlink-style push oracles, bluechip-first, not Pyth pull

**Status:** Accepted — supersedes the original Pyth-based decision

## Context

The original design (bleu-brain context.md decision 7) chose Pyth: a pull oracle, verified
on-chain via signature/staleness/confidence checks, with broader longtail coverage than push
feeds. The 1inch Spot Price Aggregator was ruled out early (off-chain-only, manipulable) and
Chainlink was initially rejected for weak longtail coverage.

The threat-model review (critique.md, issue 1.1) reversed this: with a pull oracle, the trader
who submits the swap also submits the price update, and can pick the most favorable
still-valid price within the staleness window — a direct gaming vector on a design where the
oracle sets relative token value for pricing. Push oracles remove trader-supplied prices
entirely. The cost accepted: no trustworthy longtail coverage at launch (addressed by GTM
sequencing, not by the oracle choice) and some residual staleness-driven LVR between updates,
judged acceptable since it's bounded by the pricing curve's price impact (ADR-0004) and is, in
effect, the same cost any AMM pays for using an oracle at all.

This also closes 1.5.1 (critique.md): a single mispriced token distorts every cross-group
valuation, and reliable feeds on bluechip tokens make that unlikely, whereas thin longtail feeds
would not.

## Decision

Oracle = Chainlink-style push feeds only. No trader-supplied price updates. Launch universe
restricted to tokens with trustworthy Chainlink (or equivalent push) coverage; longtail
expansion is a later GTM step, not a launch requirement.

## Consequences

- Closes the pull-oracle gaming vector (critique.md 1.1) and the one-bad-price contagion risk
  (1.5.1) outright, by removing the attack surface rather than bounding it.
- Caps the initial addressable universe to bluechip pairs — a real GTM constraint, not just a
  technical footnote (bleu-brain critique.md, "GTM = bluechip pairs first, longtail later").
- Leaves residual staleness LVR between Chainlink updates as an accepted, bounded cost
  (critique.md, 1.2) rather than something this ADR eliminates.
- A dead or bad oracle has no on-chain pause path today (strategies are immutable) — the only
  recourse is `dock()`ing the strategy. An admin/circuit-breaker pause is deferred future scope
  (critique.md, 1.10, marked WOULD, not MUST).

## References

- bleu-brain `1inch-aqua-incubator/portfolio-manager/context.md`, decision 7 (superseded)
- bleu-brain `1inch-aqua-incubator/portfolio-manager/critique.md`, "Decisions locked", issues
  1.1, 1.5.1, 1.10
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Oracle Adapter component notes
