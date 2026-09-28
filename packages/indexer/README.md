# Aqua strategy indexer

Collects Aqua's `Shipped`, `Docked`, and `Pushed` events across all apps with Envio HyperIndex.
Each `Strategy` records the maker wallet, app, supported tokens, active status, and the transaction that registered (shipped) or disabled (docked) it.

Also collects `Transfer` events for the token allow list (USDC, USDT, WETH, WBTC on Base) into `WalletBalanceChange`, filtered to transfers touching a known Strategy Wallet (a maker with at least one indexed `Strategy`). Each row is a signed balance delta, not a running total -- a wallet's current balance for a token is the sum of its rows plus the one-time balance read taken at Strategy discovery (see [ADR-0014](../../docs/adr/0014-production-arbitrageur-design.md)). `StrategyWallet` is an internal lookup table only, marking known maker addresses so the `Transfer` handler can check membership without scanning every `Strategy`.

Also collects Chainlink price updates for the same token allow list into `PriceSnapshot`. The well-known feed addresses are `EACAggregatorProxy` contracts that never emit `AnswerUpdated` themselves -- only their current underlying aggregator does, and Chainlink can swap that aggregator over time. `ChainlinkProxy`'s `AggregatorConfirmed` handler registers the new aggregator with Envio's dynamic contract indexing and records the address-to-feed mapping in `ChainlinkAggregatorFeed`; `ChainlinkAggregator`'s `AnswerUpdated` handler looks that mapping up (falling back to a seed table in `EventHandlers.ts` for each feed's aggregator as of setup) to know which feed a price update belongs to.

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
- Wallet Balance Change history only starts once a wallet becomes a known Strategy Wallet (its first `Shipped` event). A consumer needs a one-time balance read at Strategy discovery to establish the starting balance; indexed rows alone give deltas, not an absolute balance.
- `ChainlinkAggregator`'s seed addresses are each feed's aggregator as of this package's last update (see `config.yaml`'s comment for the date). A swap that happened earlier than that is not covered -- `AnswerUpdated` history from a still-earlier aggregator is not indexed. Every swap from the seed date forward is, via `AggregatorConfirmed`.
