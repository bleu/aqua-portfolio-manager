# ADR-0009: Deploy on Base at launch

**Status:** Accepted — held loosely, open to another L2 if Aqua's own deployment points there

## Context

Cost of rebalancing is one of the two success KPIs (ADR-0008), and gas is a direct input to
it: a solver bearing higher gas to execute a corrective leg demands a larger rebate, which is a
cost the LP pays indirectly. This argues for an L2-first chain choice — cheap execution buys
tighter tracking at a given cost budget — which is the opposite of the mainnet-first framing
used by a sibling Aqua grant application (App #1, IVA), whose economics instead lean on
mainnet LVR dynamics. The two applications are independent (see bleu-brain
`1inch-aqua-incubator/README.md`) and are allowed to reach different chain conclusions.

The choice is also not fully within this project's control: it depends on where Aqua itself
deploys and where 1inch's own routing footprint reaches, since a portfolio strategy with no
taker traffic can't rebalance (critique.md, 1.12).

## Decision

Launch on Base. Kept soft in the grant application — open to another L2 (e.g. Arbitrum) if
Aqua's deployment or 1inch's routing footprint points elsewhere by the time this ships.

## Consequences

- Locks in the L2-first cost assumption used in the Milestone 1 tracking-error/cost frontier
  (ADR-0008) and in any oracle per-update-fee accounting (ADR-0005/0006).
- Explicitly not a hard commitment — if Aqua's actual deployment sequence or 1inch's routing
  reach diverges from Base by the time this reaches M2/M3, the chain choice should revisit
  without treating that as a broken decision, since the application language already flags this
  as conditional.
- Reachability still gates rebalancing regardless of chain: the pool only corrects when a taker
  or solver actually trades through it, directly or via 1inch routing (critique.md, 1.12) — a
  chain choice with no adoption is not sufficient on its own.

## References

- bleu-brain `1inch-aqua-incubator/portfolio-manager/context.md`, "Still open" — chain choice
- bleu-brain `1inch-aqua-incubator/README.md` — independence from App #1 (IVA)
- bleu-brain `1inch-aqua-incubator/portfolio-manager/critique.md`, issue 1.12
