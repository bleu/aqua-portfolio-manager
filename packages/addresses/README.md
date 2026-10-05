# addresses

Single source of truth for the Base mainnet addresses this repo used to hardcode independently in
`packages/contracts/script/ShipStrategy.s.sol`, `apps/indexer/config.yaml`,
`apps/indexer/src/EventHandlers.ts`, and `apps/arbitrageur/.env.example`.

`base-mainnet.json` is the data. Nothing generates it, and nothing generates from it:

- TS consumers (currently `apps/indexer`, via `src/index.ts`) import this package directly
  (`workspace:*`), same as `packages/decoding`. `src/index.ts` imports the JSON with
  `resolveJsonModule`/an import attribute and re-exports it typed and validated -- it's hand-written
  once, not regenerated.
- `ShipStrategy.s.sol` and `Deploy.s.sol` read `base-mainnet.json` live via `vm.readFile` +
  `vm.parseJsonAddress`, at script-run time. No Solidity file is generated or committed; editing
  `base-mainnet.json` is immediately reflected the next time either script runs. This needed one
  `fs_permissions` entry in `packages/contracts/foundry.toml` for the sibling directory.
- `apps/indexer/config.yaml` and `apps/arbitrageur/.env.example` stay hand-maintained -- they're
  Envio's own config format and a plain env file, not something worth owning the structure of for
  ~15 addresses. `scripts/check-config-drift.ts` checks every address in `base-mainnet.json` still
  appears in both files, and CI (`check-generated-addresses` in `.github/workflows/test.yml`) runs
  it on every push.

## Updating an address

1. Edit `base-mainnet.json`.
2. Update the same address by hand in `apps/indexer/config.yaml` and, if it's a token or feed
   address, `apps/arbitrageur/.env.example`'s `ALLOWED_TOKENS`/`ALLOWED_FEEDS`.
3. Run `pnpm --filter @aqua-portfolio-manager/addresses check-config-drift` to confirm.

`base-mainnet.json` validates itself on import (well-formed addresses, unique token symbols) --
every consumer gets that guarantee for free, including `apps/indexer`'s own runtime import and
`ShipStrategy.s.sol`/`Deploy.s.sol`'s live reads.

## Not in scope here

`ROUTER`/`VALIDATOR` (this repo's own deployed Portfolio Manager contracts, not external
addresses) are still hardcoded separately in `ShipStrategy.s.sol` and `EventHandlers.ts`'s
`PM_ROUTER` -- a deployment output, not a well-known external address, so it doesn't belong here.
