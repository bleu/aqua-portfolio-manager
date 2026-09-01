# M1 economic simulation

A floating-point, fast-iteration companion to the Solidity contracts — **not** the on-chain source of truth. The spec is `docs/PRICING.md` / `docs/DONATION-RESISTANCE-PROOF.md`; this package reimplements that math in Python to run market simulations (Monte Carlo sweeps, parameter search) far faster than Forge allows.

Built around `BasketWorld` (BLEUDEV-334): every trading agent — the Portfolio Manager, a competing Aqua-native strategy, organic noise flow — is a `Strategy` plugged into one shared simulation loop, instead of separate one-off scripts per scenario. See `thoughts/simulation-suite-v2-requirements.md` and the Linear issue for the full requirements and architecture (including the class diagram this implementation follows).

Prices are synthetic-only: GBM/jump-diffusion, parametrized directly by volatility/drift/jump rate, never fit to any specific real dataset — no historical or live market data anywhere in this package.

## Structure

```
simulation/
├── src/aqua_sim/
│   ├── curve.py           — the weighted curve, mirroring docs/PRICING.md formula-for-formula
│   ├── xyc.py              — plain xy=k math, mirrors swapVM's XYCSwap opcode
│   ├── strategy.py         — the Strategy protocol + Trade value object every agent shares
│   ├── price_process.py   — synthetic-only GBM/jump-diffusion price generation, step-based
│   ├── basket_world.py    — real + virtual (ADR-0003) balances, group-boundary guard (ADR-0011), the step loop
│   ├── strategies/         — PortfolioManagerStrategy, XYCCompetitorStrategy, NoiseTraderStrategy
│   └── scenarios/          — declarative scenario builders (pm_alone, basket_with_without_pm, guard_enforcement)
├── notebooks/              — one notebook per scenario, each self-contained: narrative +
│                             real assertions (not just printed claims) + visualizations
└── pyproject.toml          — uv-managed; numpy/matplotlib + jupyterlab
```

### Notebooks

| # | Notebook | Covers |
|---|---|---|
| 01 | `01_pm_alone.ipynb` | R1 baseline: PM alone, no competitors, no basket-mates. **Result: mean tracking error stays under 0.001% across 10 seeds**, with no tunable knob beyond `fee`/`gas_cost` (`ADR-0006`). |
| 02 | `02_basket_with_without_pm.ipynb` | R5: an independent, profit-seeking `XYCCompetitorStrategy` trades within PM's declared "stables" group, with PM present and correcting vs. absent. **Result: mean tracking error ~0.03% with PM vs. ~7.6% without, across 10 seeds** — PM's presence measurably tightens tracking even though PM never trades the competitor's pair directly, entirely through the shared group's oracle-valued virtual balance (ADR-0003). |
| 03 | `03_guard_enforcement.ipynb` | R6: the same competing-strategy logic, this time trying to trade *across* a group boundary to rebalance the wallet. **Result: every profitable-looking cross-group attempt is blocked, on every seed (10/10), balances provably unchanged** — `GroupBoundaryGuard` simulates ADR-0011's Basket Scope Guard structurally, not probabilistically. |

## Running

Requires [`uv`](https://docs.astral.sh/uv/).

```bash
cd simulation
uv sync                              # installs the venv + aqua_sim itself, editable
uv run jupyter lab                   # open notebooks/ from here
```

Or run a single notebook headlessly (used in CI / to regenerate committed outputs):

```bash
uv run --with nbclient jupyter execute --inplace notebooks/01_pm_alone.ipynb
```

Notebook outputs are committed intentionally — the executed results (including the plots) are part of what the M1 write-up deliverable cites, not just the code that produces them. Re-run and re-commit after any change to `src/aqua_sim/`.
