# ADR-0005: Use Chainlink-style push feeds

**Status:** Accepted.

## Context

A pull-oracle design lets the submitting trader choose an update within the valid time window.
Multi-token groups also require updates for every valued member.
Push feeds avoid trader-supplied updates and per-swap update costs, but offer less coverage for longtail assets.

## Decision

Use Chainlink-style push feeds with a configured maximum age per feed.
Launch with tokens that have reliable feed coverage.
Reject a trade if any required feed is stale. Do not use a fallback price.

## Alternatives considered

- **Pull feeds:** add update selection and transaction-construction risks.
- **Spot-price aggregation:** rejected during design because of manipulation concerns and the integration model.

## Consequences

- Every member of either traded group needs a fresh feed because each contributes to the group total.
- One stale member blocks trades involving that group.
- Price lag within the permitted age remains an accepted risk. Push feeds do not guarantee price correctness.
- The LP can dock a strategy with a bad feed. Changing its feed configuration requires a new strategy.
- Longtail expansion depends on suitable feed coverage.

[OracleAdapter](../../packages/contracts/src/utils/OracleAdapter.sol) also rejects non-positive prices and values below one raw WAD unit.
