# ADR-0004: Use a constant-mean weighted curve

**Status:** Accepted. Supersedes the oracle-price-plus-bounded-spread design.

## Context

The original design added a capped rebalancing discount or surcharge to an oracle price.
It needed a separate proof that traders could not extract the discount through a round trip.
A weighted curve derives price impact from an invariant.

## Decision

Independently implement the published Balancer weighted-pool formula.
Use oracles for relative token valuation and the curve for pricing.
See [pricing](../PRICING.md) for formulas and rounding.

## Alternatives considered

- **Oracle price plus spread:** requires a separate bound on extractable rebates.
- **Import Balancer Solidity:** rejected because its GPL license conflicts with the project's chosen license. See [ADR-0001](0001-license-under-aqua-source-not-mit.md).

## Consequences

- The implementation must establish its own invariant and rounding guarantees.
- Round in the pool's favor and reject trades that drain the output reserve.
- Reject unsupported power ranges. A nonzero reserve alone does not ensure supported arithmetic.
- Group targets, wallet-wide exposure, and oracle valuation provide the portfolio behavior above the curve.

See [ADR-0007](0007-donation-resistance-via-curve-invariant.md) for the proof obligation.
