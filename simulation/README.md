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
├── src/aqua_sim/       — reusable simulation library (imported by every notebook)
│   └── curve.py        — the weighted curve, mirroring docs/PRICING.md formula-for-formula
├── notebooks/           — one notebook per concept, numbered in dependency order,
│                          each a self-contained set of explanations + real assertions
│                          (not just printed claims) + visualizations
└── pyproject.toml       — uv-managed; numpy/pandas/matplotlib + jupyterlab
```

### Notebooks

| # | Notebook | Status | Covers |
|---|---|---|---|
| 01 | `01_pricing_curve.ipynb` | Done | Implements + checks the curve against `PRICING.md`/`INVARIANT-PROOF.md`: equal-weight reduces to `xy=k`, spot-price direction, the round-trip invariant (200k random trades), the `fee=0` equality case, donation-only-increases, degenerate-balance rejection. Also records (not hides) a known float64 precision limit near an empty pool at extreme trade sizes — matches `BLEUDEV-263`/`BLEUDEV-296`'s planned minimum-liquidity floor. |
| 02 | `02_exogenous_flow.ipynb` | Not started (`BLEUDEV-274`) | Organic trade arrivals unrelated to the pool's own skew. |
| 03 | `03_endogenous_flow.ipynb` | Not started (`BLEUDEV-275`) | Arbitrageur/solver-driven corrective flow — the mechanism's actual rebalancing path. |
| 04 | `04_naive_baselines.ipynb` | Not started (`BLEUDEV-276`) | Periodic manual rebalance + threshold rebalance via a generic DEX — what the mechanism must beat. |
| 05 | `05_frontier_sweep.ipynb` | Not started (`BLEUDEV-276`/`277`) | The tracking-error/cost-of-rebalancing frontier; picks concrete tolerance-band/rate-cap values (`BLEUDEV-256`/`279`/`280`). |

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
