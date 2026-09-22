# ADR-0008: Measure tracking error and rebalancing cost

**Status:** Accepted. Supersedes the fee-volume and negative-cost framing.

## Context

The product maintains the LP's chosen allocation.
Trading helps correct changes in the asset mix, so more volume is not itself a success measure.
Fees paid through maintenance trades are part of the LP's cost.

## Decision

Minimize two measurements:

1. Tracking error: how far each group's actual share is from its target.
2. Rebalancing cost: discounts, fees, transaction costs (gas), and losses from worse execution prices (slippage) paid to maintain those targets.

Compare against periodic and threshold-based rebalancing with equivalent cost accounting on both sides.
Include protocol fees in the comparison.

## Consequences

- Simulation results must report tracking error and cost together.
- Corrective trades mostly in one direction can still satisfy the objective.
- The benefit to Aqua is better capital management, not fee revenue alone.
- Revenue projections must derive from managed capital and expected corrective volume rather than an unsupported volume assumption.

The simulation's 2 bps fee is a model input. Production LP and DAO fees are defined in [pricing](../PRICING.md).
