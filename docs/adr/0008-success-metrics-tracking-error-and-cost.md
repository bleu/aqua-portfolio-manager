# ADR-0008: Measure success by tracking error and cost of rebalancing, not fee/volume/PnL

**Status:** Accepted — supersedes the original "cost can go negative" framing

## Context

The original design (bleu-brain context.md decision 8) framed a north star where surcharges on
skew-worsening flow could fund rebates on skew-reducing flow enough that "cost can go negative"
— implicitly, a fee/volume product. The threat-model review (critique.md, 1.4) challenged this:
this strategy doesn't need much two-way flow to succeed. Its job is holding
the LP's declared target near the LP's own chosen allocation, cheaply — not generating trading
volume. Flow arrives when it's more profitable for a taker/solver than any other venue; that's
expected to be mostly one-directional, and that's fine.

The business critique (critique.md, B1, B3, B7) sharpened why the fee/volume framing actively
hurts the pitch: revenue capped at a 2 bps protocol fee on corrective volume is negligible on
its own (B1) and inverted — the product's job is to keep corrective volume *small*, so revenue
is capped by drift the product doesn't control and mildly penalized by the product working well
(B7). Worse, the protocol fee is paid economically by the LP's own maintenance trades, so it
must sit inside the same cost model the mechanism is judged against, or the frontier comparison
against naive rebalancing baselines is silently rigged (B3).

## Decision

Success is measured by two KPIs, both minimized: (1) tracking error — how far realized weights
drift from the LP's declared target; (2) cost of rebalancing — rebates + fees (protocol fee
included) + gas + slippage the LP pays to stay on target, benchmarked against naive baselines
(periodic manual rebalance, threshold rebalance via a generic aggregator). This is a portfolio
*maintenance* tool, not a fee or volume product, and the pitch is written accordingly.

## Consequences

- The Milestone 1 simulation must produce a tracking-error/cost frontier with the protocol fee
  included on this side, compared all-in against fee-inclusive baselines — an "all-in on both
  sides" requirement that changes what a valid M1 result looks like (critique.md, B3, MoSCoW
  item 8), not just what the pitch says.
- Reframes the platform-value argument: direct DAO revenue from the 2 bps fee is a floor, not
  the case for funding — the real argument is that unmanaged net exposure taxes Aqua's own
  capital-efficiency pitch, and this tool is what lets LPs commit more capital and run more
  strategies safely, benefiting every other strategy's volume (critique.md, B1).
- One-directional flow is now an expected outcome rather than a failure mode to explain away.
- Revenue projections in bleu-brain's `application.md` were rederived bottom-up from an assumed
  managed-TVL × drift-rate model rather than an unsupported flat volume number (critique.md,
  B4) — this ADR's KPI choice is what makes that derivation the right one to use.

## References

- bleu-brain `1inch-aqua-incubator/portfolio-manager/context.md`, decision 8 (superseded)
- bleu-brain `1inch-aqua-incubator/portfolio-manager/critique.md`, issues 1.4, B1, B3, B4, B7
