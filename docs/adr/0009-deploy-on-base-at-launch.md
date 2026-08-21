# ADR-0009: Deploy on Base at launch

**Status:** Accepted — held loosely, open to another L2 if Aqua's own deployment points there

## Context

Cost of rebalancing is one of the two success KPIs (ADR-0008), and gas is a direct input to
it: a solver bearing higher gas to execute a corrective leg demands a larger rebate, which is a
cost the LP pays indirectly. This argues for an L2-first chain choice — cheap execution buys
tighter tracking at a given cost budget.

Aqua is live in production across 13 EVM chains as of its July 2026 public launch, including
Ethereum, Base, Arbitrum, BNB Chain, and Robinhood Chain — so the choice is no longer gated on
where Aqua itself deploys; the open question is only which of its already-live chains fits this
strategy's cost/reachability goals best. 1inch's own routing footprint on each of those chains
is the remaining unknown, since a portfolio strategy with no taker traffic can't rebalance.

## Decision

Launch on Base — confirmed live in Aqua's current deployment set. Kept soft to another
already-live chain (e.g. Arbitrum) if 1inch's routing footprint favors it by the time this
ships.

## Consequences

- Locks in the L2-first cost assumption used in the Milestone 1 tracking-error/cost frontier
  (ADR-0008) and in any oracle per-update-fee accounting (ADR-0005/0006).
- Not a hard commitment — if 1inch's routing footprint on another already-live chain (e.g.
  Arbitrum) turns out to fit better by M2/M3, revisit the chain choice; the application language
  already flags this as conditional.
- Reachability still gates rebalancing regardless of chain: the pool only corrects when a taker
  or solver actually trades through it, directly or via 1inch routing — a chain choice with no
  adoption is not sufficient on its own.
