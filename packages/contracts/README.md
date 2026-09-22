# Contracts

Foundry package for the PM router, pricing instruction, validator, and Safe Guard.
See [architecture](../../docs/ARCHITECTURE.md) for responsibilities and [pricing](../../docs/PRICING.md) for formulas.

`BasketXYCSwap`, `PoCOpcodes`, and `PoCRouter` are reference prototypes.
`BasketXYCSwap` adds raw Aqua ledger balances without converting them through price feeds. It is not the production pricing path.

## Build and test

Run from this directory:

```sh
git submodule update --init --recursive -- lib
forge build
forge test
forge fmt --check
```

Run local tests without RPC access:

```sh
forge test --no-match-path 'test/e2e/*'
```

## Base fork tests

Tests in `test/e2e/` use the deployed Aqua registry on a local copy of Base at a fixed block.
Each test setup deploys its own router, validator, and Safe infrastructure.

```sh
cp .env.example .env
```

Set `BASE_RPC_URL` in `.env` to use your own endpoint.
`BASE_RPC_BLOCK` overrides the pinned snapshot. Set it to `0` to test live state.
The default snapshot is defined in [AquaE2EBase](test/e2e/base/AquaE2EBase.t.sol).
