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

`pnpm dev` requires Docker running locally (Envio's local dev stack) — this hasn't been run
end-to-end in this repo yet; `codegen` and `pnpm typecheck` (`tsc --noEmit` against the real
generated types) have both been verified to pass, but the actual indexing run against a live
chain has not.

## Configuring which `app` is our own Portfolio Manager router

`src/pmAppRegistry.ts`'s `PM_ROUTER_ADDRESSES` map is empty by default — it's deployment-specific
(differs per chain, same pattern as `packages/contracts/script/Deploy.s.sol`'s `AQUA_ADDRESS`)
and can't be derived from a `Shipped` event alone. Without an entry for the chain being indexed,
`isPmApp` always returns `false`, which means **compatibility alerts will never fire** — every
active strategy looks "non-PM" with nothing to conflict against. Fill in the real router address
before relying on the alerting feature for a given chain.

## Known gaps (see `thoughts/indexer-architecture.md`'s "Open questions" for the full list)

- `start_block: 0` in `config.yaml` is a placeholder, not Aqua's real per-chain deployment block —
  works, but re-syncs far more history than necessary.
- No local-anvil-fork RPC override is wired up yet (the doc's docker-compose sketch assumes one);
  this indexer currently targets Base directly via Envio's hosted HyperSync data source.
- `strategyBytes` stays raw/undecoded — no PM-specific token/weight/feeBps decoding (deliberately
  deferred, see the doc).
- No automated test suite yet — `pnpm codegen` + `pnpm typecheck` are the only verification run
  so far, both against the real Envio toolchain (not hand-simulated).
