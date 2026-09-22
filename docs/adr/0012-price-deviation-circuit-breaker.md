# ADR-0012: Block trades with excessive price deviation

**Status:** Accepted.

## Context

Owners can withdraw tokens without an Aqua `ship()` call.
The Guard does not prevent this, and the curve accepts any supported nonzero starting reserves.
A badly skewed wallet can therefore remain tradable.

## Decision

Add the optional `maxDeviationBps` threshold to the strategy configuration.
Zero disables both checks. Nonzero values enable:

- **Before a swap:** check the traded pair's spot-price deviation from one.
- **During validation:** check every group's relative deviation from its target share of portfolio value.

Both use current balances and the same configured threshold in `PM_BPS` units.
They measure different quantities and are not equally strict for arbitrary weights or group counts.
See [pricing](../PRICING.md) for the formulas.

## Alternatives considered

- **Whole-portfolio check on every swap:** adds reads for groups that the trade does not touch.
- **Post-trade check:** chosen behavior instead rejects an already excessive starting deviation, including on a corrective trade.
- **Smoothed deviation:** delays the response to actual balances.

## Consequences

- A blocked pair cannot correct itself through PM. Deposits, other external balance changes, or replacement of the strategy are needed.
- The check does not constrain the post-trade state.
- Shipping validation must run explicitly. Aqua does not invoke it. [ADR-0013](0013-build-parameter-attestation-gate.md) requires recorded attestation before trading.
- The parameter adds four bytes to the instruction's 255-byte argument budget.
- Zero skips the deviation calculations. Nonzero checks add oracle and balance reads during validation.
- The mismatch between the two deviation metrics remains an open design question.

This is an extreme-state breaker. [ADR-0006](0006-exposure-smoothing.md) separately rejected small-deviation bands intended to reduce correction frequency.
