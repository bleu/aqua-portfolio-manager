# ADR-0006: Smooth the exposure reading with EMA/TWAP, a tolerance band, and rate caps

**Status:** Accepted

## Context

The exposure reader (ADR-0002) reads a wallet's settled balance, which means it can move
in a single block — either from legitimate strategy settlement or from someone transferring
tokens in deliberately (a donation, see ADR-0007). Pricing directly off the raw, latest balance
would let a single-block balance change move the quoted price instantly, which is both a
donation-attack vector and a source of noisy, over-reactive pricing on ordinary settlement
churn.

## Decision

The exposure reading feeds a moving average (EMA or TWAP) before it reaches the pricing engine,
combined with a tolerance band (small deviations from target are priced as neutral, not
corrective) and a rate cap (a ceiling on rebalancing frequency and amount per period).

## Consequences

- A single-block balance change — donation or otherwise — barely moves an EMA'd quote,
  which is necessary but **not sufficient** for donation resistance: a patient
  attacker can wait out the averaging window (critique.md, 1.5.2). The actual profit-prevention
  guarantee comes from the curve invariant (ADR-0007); smoothing only slows the input, it
  doesn't secure the outcome.
- Same-block, cross-strategy interaction on one wallet (ADR-0002) becomes a specific test
  scenario rate caps need to cover, not just single-attacker donation timing (critique.md, 1.7).
- Introduces parameters — EMA window, band width, rate-cap thresholds — with no fixed
  values yet; picking them is explicitly a Milestone 1 simulation deliverable, benchmarked
  against a tracking-error/cost-of-rebalancing frontier (see ADR-0008), not decided here.

## References

- bleu-brain `1inch-aqua-incubator/portfolio-manager/context.md`, decision 5 (smoothing half)
- bleu-brain `1inch-aqua-incubator/portfolio-manager/critique.md`, issues 1.5.2, 1.7
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Exposure Smoothing component notes
