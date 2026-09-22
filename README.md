# Aqua Portfolio Manager

A portfolio rebalancing strategy for [1inch Aqua](https://github.com/1inch/aqua).
It prices trades against the real balances of a dedicated Safe wallet and the LP's target weights for token groups.
Takers execute the trades. The strategy does not schedule rebalances.

The implementation uses a weighted-curve instruction on an independent SwapVM router.
See the [roadmap](docs/ROADMAP.md) for milestone status.

## Development

```sh
pnpm install
git submodule update --init --recursive
cd packages/contracts
cp .env.example .env
forge build
forge test
forge fmt --check
```

The E2E tests use a pinned Base fork. Set `BASE_RPC_URL` in `.env` to use your own RPC endpoint.

## Documentation

- [Architecture](docs/ARCHITECTURE.md): components, trade flow, and security boundaries.
- [Pricing](docs/PRICING.md): formulas, units, fees, and rounding.
- [Decision records](docs/adr/README.md): design choices and tradeoffs.
- [Writing style](docs/STYLE.md): rules for docs and code comments.
- [Wallet setup](docs/guides/fresh-wallet-setup.md): funding, approvals, and shipping.
- [Contracts](packages/contracts/README.md), [indexer](packages/indexer/README.md), and [simulation](simulation/README.md): package instructions.

## License

The project uses [Aqua-Source-1.1](LICENSE).
See [third-party notices](THIRD_PARTY_NOTICES.md) for dependency licenses and [licensing risk](docs/LICENSING-RISK.md) for unresolved commercial terms.
