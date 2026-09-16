# @aqua-portfolio-manager/indexer

Indexes `Shipped`/`Docked`/`Pushed` events from the real Aqua registry contract (`0x499943e74fb0ce105688beee8ef2abec5d936d31` — same address on every chain Aqua is live on) across **all apps**, and exposes a single `Strategy` entity: which wallet, which app, which tokens it declared at ship time, whether it's still active, and when it shipped/docked. Built with [Envio HyperIndex](https://docs.envio.dev/).

Full design and the class diagram: `thoughts/indexer-architecture.md`.

## Running locally

```bash
pnpm install
pnpm codegen   # regenerate .envio/types.d.ts and envio-env.d.ts from config.yaml/schema.graphql
pnpm dev       # starts a local Postgres via Docker, then indexes + serves the GraphQL API
```

`pnpm dev` requires Docker running locally, and an `ENVIO_API_TOKEN` env var (free at [envio.dev/app/api-tokens](https://envio.dev/app/api-tokens)) — Base is a HyperSync-supported chain, and HyperSync stays the primary data source for those chains even with a local `rpc:` override in `config.yaml`: `rpc` only serves as a fallback for HyperSync-supported chains, so a local anvil fork's own new blocks are invisible to it — there's currently no config-level way to force pure-RPC mode for a chain HyperSync already supports.

## How `tokens` gets populated

`Shipped`'s own event args don't carry the `tokens`/`amounts` arrays passed to `ship()` — only the opaque `strategy` program bytes. Decoding the top-level transaction's calldata directly doesn't work: PM maker wallets are required to be Safes (`ADR-0011`), so the top-level transaction is `Safe.execTransaction(...)`, not a direct `ship()` call, and decoding `transaction.input` as `ship()` calldata would silently break for every real PM wallet.

Instead, the indexer also tracks `Pushed` (`Aqua.sol` emits one per token, in the same transaction as `Shipped`, right after it, regardless of how the call arrived) and appends a token to `Strategy.tokens` only when a `Pushed` event's transaction hash matches that strategy's own `shippedAtTxHash` — this is what tells the initial ship-time token declaration apart from every later trade's own `Pushed` event (pull/push cycles happen on every swap, not just at ship time).

## Known gaps (see `thoughts/indexer-architecture.md`'s "Open questions" for the full list)

- No local-anvil-fork testing path exists for chains HyperSync already supports (see "Running locally" above) — local dev iteration currently means indexing real Base mainnet directly.
- No automated test suite yet — verification so far is `pnpm codegen` + `pnpm typecheck` plus manual `pnpm dev` runs against real Base mainnet, not an automated regression suite.
- `Strategy` doesn't store the raw `strategy` program bytes from `Shipped` — a strategy's actual program (curve, weights, fees) is entirely unrecoverable from the indexed data, not merely undecoded. `event.params.strategy` is already available in the handler if a future consumer needs it added back.
