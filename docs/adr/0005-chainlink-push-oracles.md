# ADR-0005: Use Chainlink-style push feeds

**Status:** Accepted.

## Context

An oracle supplies token prices to the contract. With pull feeds, the trader submits the price update alongside the trade.
The trader can choose an update within the allowed time window.
Multi-token groups also require updates for every valued member.
Push feeds publish prices independently of trades, avoiding trader-supplied updates and per-trade update costs.
Coverage of less-common tokens is more limited.

## Decision

Use Chainlink-style push feeds with a configured maximum age per feed.
Launch with tokens that have reliable feed coverage.
Reject a trade if any required price is too old. Do not use a fallback price.

## Alternatives considered

- **Pull feeds:** let traders choose updates and make trade transactions harder to prepare.
- **Combining current market prices:** rejected during design because of manipulation concerns and the integration model.

## Consequences

- Every member of either traded group needs a fresh feed because each contributes to the group total.
- One member with an outdated price blocks trades involving that group.
- Price lag within the permitted age remains an accepted risk. Push feeds do not guarantee price correctness.
- The LP can dock a strategy with a bad feed. Changing its feed configuration requires a new strategy.
- Support for less-common tokens depends on suitable feed coverage.

[OracleAdapter](../../packages/contracts/src/utils/OracleAdapter.sol) also rejects zero or negative prices and prices below `1e-18` in the shared pricing currency.
