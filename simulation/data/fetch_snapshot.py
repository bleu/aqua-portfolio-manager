"""Generates this directory's local CSV snapshot from the real endpoints in README.md's
table — required once before running notebooks 08/09 (the CSVs are gitignored, not
committed; see data/README.md).

Not part of the normal notebook flow — `aqua_sim.marketdata` never imports this file, and
no notebook runs it. Run manually:

    uv run python data/fetch_snapshot.py

Requires network access. The 1inch calls need an API key (`api.1inch.dev` returns 401
unauthenticated without one); set ONEINCH_API_KEY and re-run to also refresh those two
files, or leave it unset to refresh just the CoinGecko/Balancer files and skip 1inch with
a warning.
"""

from __future__ import annotations

import csv
import os
import sys
import time
import urllib.request
import json
from pathlib import Path

DATA_DIR = Path(__file__).parent

COINGECKO_IDS = {
    "weth_usd_daily.csv": "weth",
    "usdc_usd_daily.csv": "usd-coin",
    "wbtc_usd_daily.csv": "wrapped-bitcoin",
}

WETH_SIZES = [1, 5, 10, 25, 50, 100, 250, 500, 1000]
WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"


def _get_json(url: str, headers: dict[str, str] | None = None) -> dict:
    all_headers = {"User-Agent": "Mozilla/5.0"} | (headers or {})
    req = urllib.request.Request(url, headers=all_headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def fetch_coingecko_prices() -> None:
    for filename, coin_id in COINGECKO_IDS.items():
        url = f"https://api.coingecko.com/api/v3/coins/{coin_id}/market_chart?vs_currency=usd&days=180&interval=daily"
        data = _get_json(url)
        prices = data["prices"]  # [[timestamp_ms, price], ...]
        path = DATA_DIR / filename
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["date", "price_usd"])
            for ts_ms, price in prices:
                date = time.strftime("%Y-%m-%d", time.gmtime(ts_ms / 1000))
                writer.writerow([date, price])
        print(f"wrote {path} ({len(prices)} rows)")
        time.sleep(2)  # CoinGecko's free tier rate-limits aggressively


def fetch_balancer_pools() -> None:
    query = {
        "query": """
        query {
          poolGetPools(where: {chainIn: MAINNET, tokensIn: ["%s"]}, first: 20) {
            name
            symbol
            dynamicData { swapFee volume24h totalLiquidity fees24h }
            poolTokens { symbol weight }
          }
        }
        """
        % WETH_ADDRESS
    }
    req = urllib.request.Request(
        "https://api-v3.balancer.fi/graphql",
        data=json.dumps(query).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "Mozilla/5.0"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    pools = data.get("data", {}).get("poolGetPools", [])
    path = DATA_DIR / "balancer_weth_pools.csv"
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["name", "symbol", "swap_fee", "volume_24h_usd", "total_liquidity_usd", "fees_24h_usd", "tokens"])
        for pool in pools:
            dd = pool["dynamicData"]
            tokens = "/".join(f"{t['symbol']}:{float(t['weight'] or 0):.2f}" for t in pool["poolTokens"])
            writer.writerow(
                [pool["name"], pool["symbol"], dd["swapFee"], dd["volume24h"], dd["totalLiquidity"], dd["fees24h"], tokens]
            )
    print(f"wrote {path} ({len(pools)} rows)")


def fetch_1inch_quotes_and_routes() -> None:
    api_key = os.environ.get("ONEINCH_API_KEY")
    if not api_key:
        print("ONEINCH_API_KEY not set — skipping 1inch_weth_usdc_quotes.csv / _routes.csv", file=sys.stderr)
        return

    quotes_path = DATA_DIR / "1inch_weth_usdc_quotes.csv"
    routes_path = DATA_DIR / "1inch_weth_usdc_routes.csv"
    with open(quotes_path, "w", newline="") as qf, open(routes_path, "w", newline="") as rf:
        qw = csv.writer(qf)
        rw = csv.writer(rf)
        qw.writerow(["weth_in", "usdc_out", "effective_price_usdc_per_weth"])
        rw.writerow(["weth_in", "protocol", "part_pct"])
        for size in WETH_SIZES:
            amount_wei = int(size * 1e18)
            url = (
                f"https://api.1inch.dev/swap/v6.0/1/quote?src={WETH_ADDRESS}&dst={USDC_ADDRESS}"
                f"&amount={amount_wei}&includeProtocols=true"
            )
            data = _get_json(url, headers={"Authorization": f"Bearer {api_key}"})
            usdc_out = int(data["dstAmount"]) / 1e6
            qw.writerow([size, usdc_out, usdc_out / size])
            for route in (data.get("protocols") or [[]])[0]:
                for hop in route:
                    rw.writerow([size, hop["name"], hop["part"]])
            time.sleep(1)
    print(f"wrote {quotes_path} and {routes_path}")


if __name__ == "__main__":
    fetch_coingecko_prices()
    fetch_balancer_pools()
    fetch_1inch_quotes_and_routes()
