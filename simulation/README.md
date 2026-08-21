# M1 economic simulation

Answers the question `docs/adr/0008-success-metrics-tracking-error-and-cost.md` sets up:
does the mechanism actually beat naive rebalancing baselines on a tracking-error/cost
frontier? This is a floating-point, fast-iteration companion to the Solidity contracts —
**not** the on-chain source of truth. The real spec is `docs/PRICING.md` /
`docs/INVARIANT-PROOF.md`; this package reimplements that math in Python to run market
simulations (Monte Carlo sweeps, parameter search) far faster than Forge allows.

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
│   └── adversary.py      — hostile agents: sustained one-directional pressure, stale-quote exploitation
├── notebooks/            — one notebook per concept, numbered in dependency order,
│                           each a self-contained set of explanations + real assertions
│                           (not just printed claims) + visualizations
└── pyproject.toml        — uv-managed; numpy/pandas/matplotlib + jupyterlab
```

### Notebooks

| # | Notebook | Status | Covers |
|---|---|---|---|
| 01 | `01_pricing_curve.ipynb` | Done | Implements + checks the curve against `PRICING.md`/`INVARIANT-PROOF.md`: equal-weight reduces to `xy=k`, spot-price direction, the round-trip invariant (200k random trades), the `fee=0` equality case, donation-only-increases, degenerate-balance rejection. Also records (not hides) a known float64 precision limit near an empty pool at extreme trade sizes — matches `BLEUDEV-263`/`BLEUDEV-296`'s planned minimum-liquidity floor. |
| 02 | `02_exogenous_flow.ipynb` | Done (`BLEUDEV-322`) | Organic trade arrivals unrelated to the pool's own skew — Poisson arrival rate, unbiased direction (checked correctly, across many realizations, not one path), lognormal size distribution. |
| 03 | `03_endogenous_flow.ipynb` | Done (`BLEUDEV-322`) | Arbitrageur/solver-driven corrective flow. **Documents a real price-convention bug** this work found and fixed (see below) — kept in the notebook deliberately, not cleaned out of the record. Verifies arb direction both ways, tolerance band, rate cap, and a full year end-to-end. |
| 04 | `04_naive_baselines.ipynb` | Done (`BLEUDEV-322`) | Periodic manual rebalance + threshold rebalance via a generic DEX — what the mechanism must beat, on the same cost/tracking-error metrics. |
| 05 | `05_frontier_sweep.ipynb` | Done (`BLEUDEV-322`) | The tracking-error/cost-of-rebalancing frontier: mechanism (tolerance-band sweep) vs. both baselines (period/threshold sweeps), 15 Monte Carlo reps per point. **Result: the mechanism's frontier dominates both baselines' at every swept point** (10/10, checked as an explicit assertion, not eyeballed). Picking a final tolerance-band value from this frontier is separate, deliberately out-of-scope work (`BLEUDEV-256`/`279`/`280`). |\n| 06 | `06_price_shocks.ipynb` | Done (`BLEUDEV-323`) | Jump-diffusion price paths (Merton: GBM + Poisson-arrival log-normal jumps) and a deterministic instantaneous shock injector. **Result: after a -30% shock, the mechanism recovers under the tolerance band in ~25 minutes, vs. ~20.5 days for the weekly baseline (~1183x faster)**. |\n| 07 | `07_adversarial_agent.ipynb` | Done (`BLEUDEV-323`) | Two hostile agents (not relabeled noise): sustained one-directional pressure all year, and profit-maximizing exploitation of a stale post-shock quote. **Result: sustained pressure forces more corrective trades and higher tracking-error volatility, but does not raise the LP's realized cost — every attacking trade pays the same fee the invariant proof already shows benefits the pool.** The stale-quote exploit is real but bounded (~1.1% of portfolio value for a severe -30% shock), a known AMM cost category (loss-versus-rebalancing), directly controllable via the rate cap. |

### A real bug this work found (documented, not hidden)

`simulate.py`'s first version fed `market.py`'s conventional price (`price_a_in_b`, "how
many B is 1 A worth") directly into `flows.py`'s arbitrage logic, which expects
`curve.py`'s reciprocal `SP(i->o)` convention ("units of `i` paid per unit of `o`
received"). Every isolated unit test happened to use `market_price=1.0` (its own
reciprocal), so nothing caught the mismatch until a full end-to-end run produced a
95th-percentile tracking error of 43% — obviously wrong for a mechanism whose entire job
is to hold tracking error small. Fixed, and locked in with a non-self-reciprocal
regression check in `03_endogenous_flow.ipynb` §1. Left in the record as evidence this was
actually checked end to end, not just assumed correct because the algebra looked right on
paper.

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
