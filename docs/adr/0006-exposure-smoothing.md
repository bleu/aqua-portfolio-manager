# ADR-0006: Price current exposure without smoothing

**Status:** Accepted. Supersedes the EMA/TWAP, tolerance-band, and rate-cap design.

## Context

Smoothing introduces a lag between the real reserve and the reserve used to price a trade.
The curve invariant instead uses the current reserve directly.
The original smoothing design therefore needed another proof without showing greater protection against donations.

## Decision

Price current balances without exponential or time-weighted moving averages (EMA/TWAP).
Do not delay corrections until a minimum deviation (tolerance band) or impose a waiting period (rate cap).
In the simulation, a taker corrects exposure when the trade is profitable after fees and gas.
This rule models when traders choose to act. It is not an on-chain scheduler or gas-price check.

## Evidence and history

An early comparison of parameter settings used a $5 gas-cost assumption and selected a 0.5% band with a one-hour cooldown.
A later comparison used $0.10 and found little cost improvement from either control, with worse tracking.
The design dropped both controls.

The original parameter-comparison notebook was deleted. The retained charts are historical evidence and cannot be regenerated from the current notebooks:

- [Mechanism versus baselines](assets/0006-mechanism-vs-baselines.png).
- [Tolerance and cooldown sweep](assets/0006-tolerance-cooldown-sweep.png).

## Consequences

- The simulation defaults to a 2 bps fee and a $0.10 gas cost. These are model inputs, not fixed production parameters.
- Replace the gas assumption with measured contract costs when available.
- The invariant's scope remains separate from taker profitability. See [ADR-0007](0007-donation-resistance-via-curve-invariant.md).
- Cross-strategy restrictions belong to [ADR-0011](0011-safe-wallet-with-basket-scope-guard.md).
- The optional deviation breaker in [ADR-0012](0012-price-deviation-circuit-breaker.md) blocks extreme states rather than delaying small corrections.

Current experiments and their results live in the [simulation notebooks](../../simulation/README.md).
