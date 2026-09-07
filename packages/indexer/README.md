# @aqua-portfolio-manager/indexer

Indexes `Shipped`/`Docked` events from the real Aqua registry contract
(`0x499943e74fb0ce105688beee8ef2abec5d936d31` — same address on every chain Aqua is live on)
across **all apps**, and flags any wallet that has an active Portfolio Manager strategy *and* an
active non-PM strategy at the same time. Built with [Envio HyperIndex](https://docs.envio.dev/).

Full design, the "why", and the class diagram: `thoughts/indexer-architecture.md` (BLEUDEV-339).

## Running locally

```bash
pnpm install
pnpm codegen   # regenerate .envio/types.d.ts and envio-env.d.ts from config.yaml/schema.graphql
pnpm dev       # starts a local Postgres via Docker, then indexes + serves the GraphQL API
```

`pnpm dev` requires Docker running locally, and an `ENVIO_API_TOKEN` env var (free at
[envio.dev/app/api-tokens](https://envio.dev/app/api-tokens)) — Base is a HyperSync-supported
chain, and HyperSync stays the primary data source for those chains even with a local `rpc:`
override in `config.yaml` (confirmed by testing: `rpc` only serves as a *fallback* role for
HyperSync-supported chains, so a local anvil fork's own new blocks are invisible to it — there's
currently no config-level way to force pure-RPC mode for a chain HyperSync already supports).

**Verified end-to-end against real Base mainnet** (2026-09-07, `start_block: 0`, full historical
backfill via HyperSync): the real Aqua registry's actual `Shipped`/`Docked` history indexed
correctly, `isActive`/`dockedAtBlock`/`dockedAtTimestamp`/`dockedAtTxHash` transition correctly on
dock, and `getWhere`-style filtering on `@index`-marked fields (`maker`, `app`, `isActive`,
`status`) works at runtime, not just at codegen. The `CompatibilityAlert` detection/resolution
logic was also verified for real: found a real maker with two concurrently-active strategies
under different apps, temporarily pointed `PM_ROUTER_ADDRESSES` at one of those real apps, and
confirmed both an `OPEN` alert (for a still-active conflict) and a `RESOLVED` one (for a pair
where one side had since docked) appeared with correctly cross-referenced `pmStrategyId`/
`conflictingStrategyId`. Reverted before committing — the shipped `PM_ROUTER_ADDRESSES` map stays
empty by design (see below).

## Configuring which `app` is our own Portfolio Manager router

`src/pmAppRegistry.ts`'s `PM_ROUTER_ADDRESSES` map is empty by default — it's deployment-specific
(differs per chain, same pattern as `packages/contracts/script/Deploy.s.sol`'s `AQUA_ADDRESS`)
and can't be derived from a `Shipped` event alone. Without an entry for the chain being indexed,
`isPmApp` always returns `false`, which means **compatibility alerts will never fire** — every
active strategy looks "non-PM" with nothing to conflict against. Fill in the real router address
before relying on the alerting feature for a given chain.

## Known gaps (see `thoughts/indexer-architecture.md`'s "Open questions" for the full list)

- `start_block: 0` in `config.yaml` is a placeholder, not Aqua's real per-chain deployment block —
  works (verified — backfilled real Base history in well under a second via HyperSync), but
  re-syncs more than strictly necessary.
- No local-anvil-fork testing path exists for chains HyperSync already supports (see "Running
  locally" above) — local dev iteration currently means indexing real Base mainnet directly.
- `strategyBytes` stays raw/undecoded — no PM-specific token/weight/feeBps decoding (deliberately
  deferred, see the doc).
- No automated test suite yet — verification so far is `pnpm codegen` + `pnpm typecheck` plus a
  manual `pnpm dev` run against real Base mainnet (see above), not an automated regression suite.
