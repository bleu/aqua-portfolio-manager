# ADR-0009: Launch on an L2

**Status:** Accepted. The launch chain remains undecided.

## Context

Gas contributes to rebalancing cost.
Lower execution costs can make smaller corrective trades profitable and improve tracking.
The chain also needs Aqua, suitable oracle feeds, and taker traffic.

## Decision

Launch on an EVM L2 with Aqua support.
Choose the chain during M2/M3 after checking 1inch routing availability and execution costs.

## Consequences

- Simulation gas assumptions represent an L2 rather than a commitment to one chain.
- Base fork tests do not select Base as the launch chain.
- Deployment without taker adoption does not produce rebalancing.
- Independent-router inclusion remains a separate dependency under [ADR-0010](0010-on-chain-form-aquaapp-vs-swapvm-instruction.md).
