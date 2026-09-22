# ADR-0008: Measure tracking error and rebalancing cost

**Status:** Accepted. Supersedes the fee-volume and negative-cost framing.

## Context

The product maintains the LP's chosen allocation.
Trading volume is a means of correcting drift, so more volume is not itself a success measure.
Fees paid through maintenance trades are part of the LP's cost.

## Decision

Minimize two metrics:

1. Tracking error: deviation of realized group weights from their targets.
2. Rebalancing cost: rebates, fees, gas, and slippage paid to maintain those targets.

Compare against periodic and threshold-based rebalancing with equivalent cost accounting on both sides.
Include protocol fees in the comparison.

## Consequences

- Simulation results must report tracking error and cost together.
- Mostly one-directional corrective flow can still satisfy the objective.
- The platform-value argument is improved capital management, not fee revenue alone.
- Revenue projections must derive from managed capital and expected corrective volume rather than an unsupported volume assumption.

The simulation's 2 bps fee is a model input. Production LP and DAO fees are defined in [pricing](../PRICING.md).
