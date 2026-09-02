# M1 economic simulation

A floating-point, fast-iteration companion to the Solidity contracts — **not** the on-chain source of truth. The spec is `docs/PRICING.md` / `docs/DONATION-RESISTANCE-PROOF.md`; this package reimplements that math in Python to run market simulations (Monte Carlo sweeps, parameter search) far faster than Forge allows.

Built around `BasketWorld`: every trading agent — the Portfolio Manager, competing Aqua-native strategies, organic noise flow — is a `Strategy` plugged into one shared simulation loop, instead of separate one-off scripts per scenario.

Prices are synthetic-only: GBM/jump-diffusion, parametrized directly by volatility/drift/jump rate, never fit to any specific real dataset — no historical or live market data anywhere in this package.

## Structure

```
simulation/
├── src/aqua_sim/
│   ├── curve.py           — the weighted curve, mirroring docs/PRICING.md formula-for-formula
│   ├── xyc.py              — plain xy=k math, mirrors swapVM's XYCSwap opcode
│   ├── stableswap.py       — Curve-style StableSwap math, for near-pegged pairs (e.g. USDC/USDT)
│   ├── strategy.py         — the Strategy protocol + Trade value object every agent shares
│   ├── price_process.py   — synthetic-only GBM/jump-diffusion price generation, step-based
│   ├── basket_world.py    — real + virtual (ADR-0003) balances, group-boundary guard (ADR-0011), the step loop
│   ├── strategies/         — PortfolioManagerStrategy, XYCCompetitorStrategy,
│   │                         StableSwapCompetitorStrategy, NoiseTraderStrategy
│   └── scenarios/          — declarative scenario builders (pm_alone, basket_with_without_pm,
│                             cross_basket_no_pm)
├── notebooks/              — one notebook per scenario, each self-contained: narrative +
│                             real assertions (not just printed claims) + visualizations
└── pyproject.toml          — uv-managed; numpy/matplotlib + jupyterlab
```

### Notebooks

| # | Notebook | Covers |
|---|---|---|
| 01 | `01_pm_alone.ipynb` | Baseline: PM alone, no competitors, no basket-mates. **Result: mean tracking error stays under 0.001% across 10 seeds**, with no tunable knob beyond `fee`/`gas_cost` (`ADR-0006`). |
| 02 | `02_basket_with_without_pm.ipynb` | Portfolio value with PM (arbitrageur + organic flow trading against PM's curve, `pm_fee=2%`) vs. without PM (static). **With PM wins 10/10 seeds** under a mean-reverting price; also charts a forced WETH uptrend. |
| 03 | `03_cross_basket_no_pm.ipynb` | Portfolio value and tracking error with PM vs. an unconstrained competitor on every pairwise token combination (no PM, no Guard). **With PM wins on both value and tracking error** (~0.37% vs. ~16.67% mean tracking error). |

Guard enforcement (a strategy blocked from crossing a group boundary) isn't a notebook — it's verified at the contract level (`packages/contracts/test/BasketScopeGuard.t.sol`, `BasketScopeGuardE2E.t.sol`), since the actual `ship()` accept/revert path through the Safe is what matters, not a simulated approximation of it.

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
