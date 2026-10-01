# Aqua Portfolio Manager

A strategy that helps keep a portfolio near its chosen asset mix, built on [1inch Aqua](https://github.com/1inch/aqua).
Liquidity providers (LPs) choose target shares for groups of tokens held in a dedicated Safe wallet.
Portfolio Manager (PM) sets trade prices using those targets and the wallet's actual balances.
Traders, called takers, execute the trades. The strategy does not schedule them.

The pricing formula runs as an instruction in our own SwapVM router, the contract that receives trade requests.
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

End-to-end (E2E) tests run against a local copy of Base at a fixed block.
Set `BASE_RPC_URL` in `.env` to use your own blockchain data service (RPC endpoint).

## Documentation

- [Architecture](docs/ARCHITECTURE.md): components, trade flow, and security boundaries.
- [Pricing](docs/PRICING.md): formulas, units, fees, and rounding.
- [Decision records](docs/adr/README.md): design choices and tradeoffs.
- [Writing style](docs/STYLE.md): rules for docs and code comments.
- [Monorepo conventions](docs/MONOREPO-CONVENTIONS.md): what counts as an app vs. a shared package.
- [Wallet setup](docs/guides/fresh-wallet-setup.md): funding, approvals, and registering strategies.
- [Contracts](packages/contracts/README.md), [indexer](packages/indexer/README.md), [arbitrageur](packages/arbitrageur/README.md), [decoding](packages/decoding/README.md), and [simulation](simulation/README.md): package instructions.

## License

The project uses [Aqua-Source-1.1](LICENSE).
See [third-party notices](THIRD_PARTY_NOTICES.md) for dependency licenses and [licensing risk](docs/LICENSING-RISK.md) for unresolved commercial terms.
