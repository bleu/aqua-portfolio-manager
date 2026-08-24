# M1 architecture decision: mechanism, on-chain form, and the numbers behind them

This is the single document M1 asks for: the mechanism, the on-chain form, and the
evidence behind both, in one place. Every claim here is backed by a proof, a contract, or
a simulation result committed in this repo — this document synthesizes and cites; it
doesn't re-derive anything. Where a claim needs the full detail, it links to the source.

## The mechanism

A constant-mean weighted curve — Balancer's weighted-pool formula, reimplemented from
scratch (not reused; see [`LICENSING-RISK.md`](LICENSING-RISK.md) for why). An LP
declares a target weight split across a token group; the curve prices trades against the
group's current real balance, with a tolerance band and rate cap to reduce unnecessary
correction churn. No moving average feeds the price — an earlier design smoothed the
balance reading through an EMA/TWAP, dropped once the invariant proof showed it cost
donation-resistance rather than adding it (see [ADR-0006](adr/0006-exposure-smoothing.md)).

Full formula: [`PRICING.md`](PRICING.md). Component-level architecture (L1 system
context, L2 contract layout): [`ARCHITECTURE.md`](ARCHITECTURE.md).

## The on-chain form

**Decided: an independent router, deploying a new swapVM instruction — not `AquaApp`,
not merged into 1inch's own deployed router.**

Made on the unilateral-deployability criterion: this form doesn't depend on 1inch
shipping anything or granting access to their router. The
[`proofs-of-concept/swapvm-multi-token/`](../proofs-of-concept/swapvm-multi-token/)
standalone PoC proves the mechanism is buildable as a swapVM instruction, including the
multi-token-group balance read `Context`'s two-token struct doesn't natively expose —
made ahead of the full simulation-based gas/frontier comparison this decision originally
scoped as closing evidence, a strategic call recorded as such, not a numbers-driven one.

Full reasoning: [ADR-0010](adr/0010-on-chain-form-aquaapp-vs-swapvm-instruction.md).

## Safety: donation-attack non-profitability, proven

**The round-trip invariant holds unconditionally: any closed sequence of trades against
this curve ends at or above where it started, for the pool.** Not asserted — proven,
algebraically, independent of how the pre-trade balance got to be what it is (the
strategy's own trades, or a pure donation). This is what turns "donate tokens into the
wallet to skew the price, then trade against it" into an irreversible gift rather than an
extractable profit.

Proof: [`INVARIANT-PROOF.md`](INVARIANT-PROOF.md) and
[ADR-0007](adr/0007-donation-resistance-via-curve-invariant.md). Checked against the
actual Python implementation across 200,000 random trades in
[`01_pricing_curve.ipynb`](../simulation/notebooks/01_pricing_curve.ipynb).

**What this proof does not cover on its own:** a *different* strategy trading against the
same shared wallet (a two-sided balance change, not a donation).
[`thoughts/cross-strategy-manipulation.md`](../thoughts/cross-strategy-manipulation.md)
found a concrete exploit through exactly that gap. Closed separately, structurally: the
maker wallet must be a Safe with a Basket Scope Guard installed, forbidding any strategy
but PM's own from crossing a declared group boundary. That guard is now written,
compiled, and tested — [`proofs-of-concept/basket-scope/`](../proofs-of-concept/basket-scope/),
standalone, 12/12 tests passing including integration tests against a real deployed Safe.
External audit is still open (M4). See [ADR-0011](adr/0011-safe-wallet-with-basket-scope-guard.md).

## The numbers: what the simulation shows

Ten notebooks, `simulation/notebooks/`, each with real assertions checked in code, not
just plotted claims — see [`simulation/README.md`](../simulation/README.md) for the full
table. Headline results:

- **The mechanism beats both naive rebalancing baselines** (periodic and threshold
  rebalancing) on the tracking-error/cost-of-rebalancing frontier, at every one of 10
  swept baseline settings — checked as an explicit assertion, not eyeballed
  ([`05_frontier_sweep.ipynb`](../simulation/notebooks/05_frontier_sweep.ipynb)).
- **After a severe price shock (-30%), the mechanism recovers ~1183x faster than a
  weekly-rebalance baseline** (~25 minutes vs. ~20.5 days)
  ([`06_price_shocks.ipynb`](../simulation/notebooks/06_price_shocks.ipynb)).
- **Sustained adversarial pressure doesn't raise the LP's realized cost** — every
  attacking trade pays the same fee the invariant proof shows always benefits the pool.
  A stale-quote exploit right after a shock is real but bounded (~1.1% of portfolio for a
  severe shock), controllable via the rate cap
  ([`07_adversarial_agent.ipynb`](../simulation/notebooks/07_adversarial_agent.ipynb)).
- **A basket association structurally costs something, even from a dormant co-strategy**
  — a real, non-obvious finding for the still-unbuilt multi-token group routing design
  (`BLEUDEV-75`) to account for, not a safety issue
  ([`08_basket_interaction.ipynb`](../simulation/notebooks/08_basket_interaction.ipynb)).
- **A recommended swap fee of ~30-32bps**, derived from real WETH/USDC volatility and
  independently matching what the real, established Balancer 50/50 WETH/USDC pool
  already charges. Pool depth, not fee, is usually the binding constraint on
  competitiveness at realistic launch-stage size
  ([`09_fee_recommendation.ipynb`](../simulation/notebooks/09_fee_recommendation.ipynb)).
- **Concrete parameter values for the tolerance band and rate cap**: `0.5%` and `1 hour`.
  Every measured dimension gets monotonically worse as either knob loosens — no genuine
  in-model trade-off exists — so these values are a deliberate, documented step back from
  the in-model mathematical optimum, trading real simulated performance for a >10x
  reduction in worst-case correction frequency against gas cost this suite doesn't model
  ([`10_parameter_decision.ipynb`](../simulation/notebooks/10_parameter_decision.ipynb),
  [ADR-0006](adr/0006-exposure-smoothing.md)).

## What this does and doesn't prove

**Established:** the pricing math is implemented correctly and is safe against round-trip
draining, unconditionally. The mechanism, under a reasonable synthetic-then-real-calibrated
market model with an idealized always-available arbitrageur, keeps a portfolio closer to
target and cheaper than the naive alternatives, holds up under hostile trading pressure,
recovers fast from shocks, and has concrete, evidenced parameter values.

**Not established by this milestone:** real-world performance under live trading, real
gas costs (a placeholder throughout every cost number above, pending
gas-per-rebalance benchmarking against the real implementation), multi-token group
routing beyond the two-token pair every notebook models, and real aggregator routing
behavior (the fee/competitiveness analysis compares quoted prices directly, not live
1inch routing decisions). Two more steps close that gap, neither of which this milestone
substitutes for: a live testnet deployment (M2) running real transactions, then real
mainnet usage (M4) with real capital and unpredictable traders.

## What's next

M2 — PoC on testnet: implement the components named in [`ARCHITECTURE.md`](ARCHITECTURE.md)'s
L2 diagram, wire the dedicated maker wallet convention end to end against a Safe, deploy
the Basket Scope Guard and confirm it blocks a real cross-group attempt on testnet, not
just locally. Full checklist: [`ROADMAP.md`](ROADMAP.md).
