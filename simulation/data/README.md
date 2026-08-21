# Real market data (fixed snapshot)

Captured once, on 2026-08-21, and committed as plain CSVs — not re-fetched on every
notebook run. `aqua_sim.marketdata` only reads these files; it makes no network calls.

| File | Source | What |
|---|---|---|
| `weth_usd_daily.csv` | CoinGecko `coins/weth/market_chart`, `days=180` | Daily WETH/USD close, ~180 days |
| `usdc_usd_daily.csv` | CoinGecko `coins/usd-coin/market_chart`, `days=180` | Daily USDC/USD close, ~180 days |
| `wbtc_usd_daily.csv` | CoinGecko `coins/wrapped-bitcoin/market_chart`, `days=180` | Daily WBTC/USD close, ~180 days |
| `balancer_weth_pools.csv` | Balancer v3 API (`api-v3.balancer.fi/graphql`), `poolGetPools` | Mainnet weighted pools containing WETH — swap fee, 24h volume, TVL, 24h fee revenue |
| `oneinch_weth_usdc_quotes.csv` | 1inch aggregation API (`api.1inch.dev/swap/v6.0/1/quote`) | Best-execution WETH→USDC quotes at 1/5/10/25/50/100/250/500/1000 WETH — a price-impact curve |
| `oneinch_weth_usdc_routes.csv` | Same 1inch calls, `includeProtocols=true` | Which protocols (Uniswap V3/V4, Curve, PMM market makers, Fluid, Ekubo, Angstrom, ...) 1inch routed each size through, and their share — the competitive landscape our strategy would be routed against |

## Why fixed, not live

Re-fetching on every run would make notebook results non-reproducible (a different market
snapshot each time) and adds a live-API dependency + rate limits + (for 1inch) an API key
requirement to something that should just run. A fixed, dated snapshot is a
point-in-time sample, not a live feed — every notebook that uses this data says so — and
keeps the simulation suite's reproducibility independent of external services staying up.

## Regenerating

Not scripted on purpose (avoids maintaining fetch/cache machinery for data that's meant
to stay fixed). To recapture a fresh snapshot, hit the same endpoints above with the same
parameters and replace these files.
