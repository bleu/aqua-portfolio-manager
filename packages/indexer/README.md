# Aqua strategy indexer

Collects Aqua's `Shipped`, `Docked`, and `Pushed` events across all apps with Envio HyperIndex.
Each `Strategy` records the maker wallet, app, supported tokens, active status, and the transaction that registered (shipped) or disabled (docked) it.

## Run locally

Docker must be running. Set `ENVIO_API_TOKEN` from [Envio](https://envio.dev/app/api-tokens).
Run from this directory:

```sh
pnpm install
pnpm codegen
pnpm dev
```

Check generated types with `pnpm typecheck`.

## Token declarations

`Shipped` omits the token array. Aqua emits one `Pushed` event per token during shipping.
The handler adds tokens only when the event's transaction hash matches the strategy's `shippedAtTxHash`.
This supports Safe calls without decoding the outer transaction's input data.

## Limits

- Local development indexes Base mainnet. The current configuration does not index blocks created only on a local Anvil fork.
- Verification uses code generation, type checks, and manual runs. There is no automated regression suite.
- The record omits raw strategy bytes. Applications cannot recover a strategy's program from indexed data alone.
