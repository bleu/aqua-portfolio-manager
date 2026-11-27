# Aqua strategy indexer

Collects Aqua's `Shipped`, `Docked`, and `Pushed` events across all apps with [Ponder](https://ponder.sh), syncing over plain JSON-RPC (not a shared indexing service -- see "Why Ponder" below).
Each `strategy` row records the maker wallet, app, the encoded order (Aqua's own `Shipped.strategy` bytes -- `abi.encode(ISwapVM.Order)`, not bare program bytecode), supported tokens, active status, and the transaction that registered (shipped) or disabled (docked) it.

Also collects Chainlink price updates for the same token allow list into `priceSnapshot`. The well-known feed addresses are `EACAggregatorProxy` contracts that never emit `AnswerUpdated` themselves -- only their current underlying aggregator does, and Chainlink can swap that aggregator over time. The `ChainlinkProxy` contract's `AggregatorConfirmed` handler registers the new aggregator via Ponder's `factory()` dynamic-address discovery and records the address-to-feed mapping in `chainlinkAggregatorFeed`; the aggregator's own `AnswerUpdated` handler looks that mapping up (falling back to a seed list in `ponder.config.ts` for each feed's aggregator as of setup) to know which feed a price update belongs to.

## Why Ponder (not Envio)

This package ran on Envio HyperIndex until the migration that produced this file. Envio's free-tier `ENVIO_API_TOKEN` rate-limits `HyperSync` access, which made a full-history sync from Aqua's own genesis block impractically slow. Ponder syncs over plain `eth_getLogs`/`eth_getBlockByNumber` JSON-RPC instead, so sync speed depends entirely on the RPC endpoint given via `BASE_RPC_URL`, not a shared free-tier service's rate limit.

## Run locally

Docker must be running (for a local Postgres). Copy `.env.example` to `.env.local` and set `BASE_RPC_URL` to a real Base RPC endpoint -- a free/public one is fine for local testing; none of the contracts this indexer watches is high-volume enough to need a paid one. A pruned RPC node cannot serve `eth_getLogs` for blocks older than its retention window, which fails outright rather than running slowly.

Run from this directory:

```sh
pnpm install
pnpm codegen
pnpm dev
```

`pnpm dev`'s interactive TUI hides real build errors behind a spinner. For debugging, run `TUI_OFF=true pnpm start` instead -- production mode, same sync logic, but with clean log output.

Check generated types with `pnpm typecheck`. GraphQL is served at `/graphql` (and `/` ), SQL-over-HTTP at `/sql`, health checks at `/healthz` -- see `src/api/index.ts`.

## Token declarations

`Shipped` omits the token array. Aqua emits one `Pushed` event per token during shipping.
The handler adds tokens only when the event's transaction hash matches the strategy's `shippedAtTxHash`.
This supports Safe calls without decoding the outer transaction's input data.

## Limits

- `AQUA_GENESIS_BLOCK` in `ponder.config.ts` is not actually Aqua's real genesis block (38281777) -- see that file's own comment. It's capped to whatever history the configured `BASE_RPC_URL` can serve; a pruned RPC node cannot serve logs further back than its retention window. Full genesis-to-now history needs an archive-tier RPC.
- Verification uses code generation, type checks, and manual runs. There is no automated regression suite.
- This indexer no longer tracks wallet token balances (it used to, via a `Transfer` handler on USDC/USDT/WETH/cbBTC into a `walletBalanceChange` table). That meant watching every transfer of 4 of Base's highest-volume tokens just to find the tiny fraction touching a Strategy Wallet, which grew Ponder's own raw sync cache (`ponder_sync.*`, which has no automatic retention) without bound -- disk usage from this alone took down a production deployment. `apps/arbitrageur` was the only consumer, and it already re-reads balances live via `balanceOf` before ever acting on one; it now reads them live for scoring too, via one multicall per evaluation tick per Strategy (see `fetchTokenStates()` in `chain.ts`), instead of this indexer maintaining a global ledger.
- The Chainlink aggregator seed addresses in `ponder.config.ts` are each feed's aggregator as of this package's last update (see that file's own comment for the date). A swap that happened earlier than that is not covered -- `AnswerUpdated` history from a still-earlier aggregator is not indexed. Every swap from the seed date forward is, via `AggregatorConfirmed`.
