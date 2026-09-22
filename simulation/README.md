# Economic simulation

Python models of the [pricing formulas](../docs/PRICING.md), used to explore portfolio behavior with synthetic prices.
`BasketWorld` runs PM, competing strategies, and noise traders against shared balances.
The contracts define on-chain behavior.

Prices use GBM or jump-diffusion with configured parameters. They are not fitted to historical or live market data.
Gas costs are assumptions, not measurements of the deployed contracts.

## Notebooks

| Notebook | Question |
|---|---|
| [01_pm_alone](notebooks/01_pm_alone.ipynb) | How closely does PM track targets without competing strategies? |
| [02_basket_with_without_pm](notebooks/02_basket_with_without_pm.ipynb) | How does PM affect value under mean reversion and a forced WETH uptrend? |
| [03_cross_basket_no_pm](notebooks/03_cross_basket_no_pm.ipynb) | How does PM compare with unconstrained strategies across token pairs? |

Each notebook contains its parameters, assertions, and results.
Guard enforcement is tested in the [contracts package](../packages/contracts/README.md).

## Run

Install [uv](https://docs.astral.sh/uv/), then run:

```sh
cd simulation
uv sync
uv run jupyter lab
```

To execute one notebook without the UI:

```sh
uv run --with nbclient jupyter execute --inplace notebooks/01_pm_alone.ipynb
```

Commit notebook outputs with changes to simulation behavior so readers can inspect the results.
