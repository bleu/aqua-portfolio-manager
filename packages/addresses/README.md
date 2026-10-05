# addresses

Single source of truth for the Base mainnet addresses this repo used to hardcode independently in
`packages/contracts/script/ShipStrategy.s.sol`, `apps/indexer/config.yaml`,
`apps/indexer/src/EventHandlers.ts`, and `apps/arbitrageur/.env.example`.

`src/index.ts` is the data. Every TS consumer (currently `apps/indexer`) imports this package
directly via `workspace:*`, same as `packages/decoding` -- no generation step for TS. Solidity
can't import TS, so it still needs one small generated file; `config.yaml` and `.env.example` stay
hand-maintained, checked against `src/index.ts` by a drift check instead of being regenerated.

## Updating an address

1. Edit `src/index.ts`.
2. Run `pnpm --filter @aqua-portfolio-manager/addresses generate-solidity`, commit the result.
3. Update the same address by hand in `apps/indexer/config.yaml` and, if it's a token or feed
   address, `apps/arbitrageur/.env.example`'s `ALLOWED_TOKENS`/`ALLOWED_FEEDS`.
4. Run `pnpm --filter @aqua-portfolio-manager/addresses check-config-drift` to confirm.

CI (`check-generated-addresses` in `.github/workflows/test.yml`) runs steps 2 and 4 on every push,
so a forgotten regeneration or a forgotten hand-edit both fail the build.

`src/index.ts` validates its own data on import (well-formed addresses, unique token symbols) --
every consumer gets that guarantee for free, including `apps/indexer`'s own runtime import.

## Not in scope here

`ROUTER`/`VALIDATOR` (this repo's own deployed Portfolio Manager contracts, not external
addresses) are still hardcoded separately in `ShipStrategy.s.sol` and `EventHandlers.ts`'s
`PM_ROUTER` -- a deployment output, not a well-known external address, so it doesn't belong here.
