# M1 economic simulation

Answers the question `docs/adr/0008-success-metrics-tracking-error-and-cost.md` sets up:
does the mechanism beat naive rebalancing baselines on a tracking-error/cost frontier?
This is a floating-point, fast-iteration companion to the Solidity contracts — **not**
the on-chain source of truth. The spec is `docs/PRICING.md` / `docs/INVARIANT-PROOF.md`;
this package reimplements that math in Python to run market simulations (Monte Carlo
sweeps, parameter search) far faster than Forge allows.

## Structure

```
simulation/
├── src/aqua_sim/         — reusable simulation library (imported by every notebook)
│   ├── curve.py          — the weighted curve, mirroring docs/PRICING.md formula-for-formula
│   ├── market.py         — synthetic GBM price paths (price_a_in_b convention)
│   ├── flows.py          — exogenous (organic) + endogenous (arbitrage) trade models
│   ├── metrics.py        — tracking error + the frictionless-reference cost metric (ADR-0008)
│   ├── baselines.py      — the two naive baselines the mechanism must beat
│   ├── simulate.py       — ties market+flows+metrics into one mechanism simulation run
│   ├── adversary.py      — hostile agents: sustained one-directional pressure, stale-quote exploitation
│   ├── basket.py         — basket-augmented pricing (mirrors the swapVM PoC's formula) + a co-basket agent
│   └── marketdata.py     — loads the fixed real-data snapshot in data/ (no network calls)
├── data/                 — fixed, real, one-time-captured market data (CoinGecko/Balancer/1inch)
│                           — see data/README.md for exactly what and when
├── notebooks/            — one notebook per concept, numbered in dependency order,
│                           each a self-contained set of explanations + real assertions
│                           (not just printed claims) + visualizations
└── pyproject.toml        — uv-managed; numpy/pandas/matplotlib + jupyterlab
```

### Notebooks

| # | Notebook | Status | Covers |
|---|---|---|---|
| 01 | `01_pricing_curve.ipynb` | Done | Implements + checks the curve against `PRICING.md`/`INVARIANT-PROOF.md`: equal-weight reduces to `xy=k`, spot-price direction, the round-trip invariant (200k random trades), the `fee=0` equality case, donation-only-increases, degenerate-balance rejection. Also records a known float64 precision limit near an empty pool at extreme trade sizes — matches `BLEUDEV-263`/`BLEUDEV-296`'s planned minimum-liquidity floor. |
| 02 | `02_exogenous_flow.ipynb` | Done (`BLEUDEV-322`) | Organic trade arrivals unrelated to the pool's own skew — Poisson arrival rate, unbiased direction (checked across many realizations, not one path), lognormal size distribution. |
| 03 | `03_endogenous_flow.ipynb` | Done (`BLEUDEV-322`) | Arbitrageur/solver-driven corrective flow. Verifies arb direction both ways, including a non-self-reciprocal regression check (§1), across a full multi-step simulation run, on the settled fee + gas-cost profitability gate — no tolerance band, no rate cap (`ADR-0006`, revised after a real sweep found neither reduces cost). |
| 04 | `04_naive_baselines.ipynb` | Done (`BLEUDEV-322`) | Periodic manual rebalance + threshold rebalance via a generic DEX — what the mechanism must beat, on the same cost/tracking-error metrics. On one seed, doesn't cleanly win either way: the mechanism tracks ~25x tighter but costs more on this LVR-style metric than either baseline, which barely register any gas/fee drag correcting as rarely as they do. |
| 05 | `05_frontier_sweep.ipynb` | Done (`BLEUDEV-322`) | The tracking-error/cost-of-rebalancing comparison: the mechanism's one real operating point (fee + gas-cost gate — no tunable knob left to sweep) vs. both baselines (period/threshold sweeps), 15 Monte Carlo reps per point. **Result: 0/10 baseline settings are beaten on both cost and tracking at once** — the mechanism has by far the tightest tracking of anything tested, but loses on cost to every baseline setting tried, a real trade-off rather than outright dominance (checked as an explicit count, not eyeballed or asserted toward a target). |
| 06 | `06_price_shocks.ipynb` | Done (`BLEUDEV-323`) | Jump-diffusion price paths (Merton: GBM + Poisson-arrival log-normal jumps) and a deterministic instantaneous shock injector. **Result: after a -30% shock, the mechanism recovers under a fixed measurement yardstick within a single step (~5 minutes), vs. ~9,360 minutes (~6.5 days) for the weekly baseline** — correcting a 30% skew is obviously worth its real gas cost, so the gate doesn't slow it down here. |
| 07 | `07_adversarial_agent.ipynb` | Done (`BLEUDEV-323`) | Profit-maximizing exploitation of a stale post-shock quote. **Result: with no rate cap, the mechanism's own same-step correction after a -30% shock already leaves essentially nothing (~0%) for a stale-quote exploiter to extract** — down from a real, measurable ~1.1% cost under the old rate-capped design. Caveat stated directly in the notebook: this simulation models one clean corrector, not real same-block competition between multiple parties racing for the same opportunity. |
| 08 | `08_basket_interaction.ipynb` | Done (`BLEUDEV-324`) | How PM reacts to another strategy sharing its declared basket group, on a real WETH/USDC pair. **Result: merely having a basket association structurally biases PM off its own real-asset target (p99 tracking error 0.10% → 15.18% as basket size grows from 0% to 50% of the pool), even with zero basket activity — and an actively-trading co-basket strategy worsens tracking error consistently, raising cost on average but noisily (50-rep Monte Carlo).** Not a safety issue — the invariant proof still holds — a behavior/UX one for `BLEUDEV-75`'s still-unbuilt multi-token routing design to account for. |
| 09 | `09_fee_recommendation.ipynb` | Done (`BLEUDEV-324`) | A recommended swap-fee band, using WETH/USDC volatility (CoinGecko), Balancer weighted-pool fee/volume comparables, and a live 1inch aggregated price-impact curve + protocol routing breakdown. **Result: breakeven fee ≈ 30-32bps, matching almost exactly what the real Balancer 50/50 WETH/USDC pool already charges.** Bigger finding: pool **depth**, not fee, is usually the binding constraint on competitiveness at realistic launch-stage TVL — even at zero fee, a $200K-$1M pool's own price impact already loses to 1inch's execution for most sizes; fee only becomes the deciding factor around $10M+ TVL. Methodology flagged separately as needing a deeper rework (too many confounders for a one-snapshot correlation) — out of scope for the fee+gas mechanism change. |

Notebook 10 (`10_parameter_decision.ipynb`, formerly here) picked concrete values for the
tolerance band and rate cap — both removed (`ADR-0006`, revised): a real sweep found
neither reduces cost once correction is gated on real gas economics instead. Deleted along
with the parameters it existed to choose.

## Running

Requires [`uv`](https://docs.astral.sh/uv/).

```bash
cd simulation
uv sync                              # installs the venv + aqua_sim itself, editable
uv run jupyter lab                   # open notebooks/ from here
```

Or run a single notebook headlessly (used in CI / to regenerate committed outputs):

```bash
uv run --with nbclient jupyter execute --inplace notebooks/01_pricing_curve.ipynb
```

Notebook outputs are committed intentionally — the executed results (including the plots)
are part of what the M1 write-up deliverable cites, not just the code that produces them.
Re-run and re-commit after any change to `src/aqua_sim/`.
