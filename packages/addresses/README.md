# addresses

Single source of truth for the Base mainnet addresses this repo used to hardcode independently in
4 places: `packages/contracts/script/ShipStrategy.s.sol`, `apps/indexer/config.yaml`,
`apps/indexer/src/EventHandlers.ts`, and `apps/arbitrageur/.env.example`.

This package has no runtime code of its own -- it's data (`base-mainnet.json`) plus a generator.

## Updating an address

1. Edit `base-mainnet.json`.
2. Run `pnpm --filter @aqua-portfolio-manager/addresses generate`.
3. Commit the data file and every file it regenerated.

CI re-runs the generator and fails the build if any generated file doesn't match what's committed
(`check-generated-addresses` in `.github/workflows/test.yml`), so a hand-edit to a generated file,
or an edit to `base-mainnet.json` without regenerating, fails the same way a stale `.gitignore`d
build artifact would -- the CI job is the enforcement, not just a convention.

## What gets generated

- `packages/contracts/script/generated/BaseMainnetAddresses.sol` -- a Solidity library of
  constants, imported by `ShipStrategy.s.sol` and `Deploy.s.sol`.
- `apps/indexer/src/generated/baseMainnetAddresses.ts` -- `SEED_AGGREGATOR_TO_PROXY`, imported by
  `EventHandlers.ts`.
- `apps/indexer/config.yaml` -- the whole file. Envio only ever reads the final YAML; generating it
  doesn't change how Envio consumes it, and the static scaffolding (event definitions, comments)
  lives in the generator script itself, not derived from the JSON, so it's preserved verbatim.
- `apps/arbitrageur/.env.example`'s `ALLOWED_TOKENS`/`ALLOWED_FEEDS` lines only -- every other line
  in that file is untouched, and the real, gitignored `.env` is never written by this script.

## Not in scope here

`ROUTER`/`VALIDATOR` (this repo's own deployed Portfolio Manager contracts, not external
addresses) are still hardcoded separately in `ShipStrategy.s.sol` and `EventHandlers.ts`'s
`PM_ROUTER` -- a deployment output, not a well-known external address, so it doesn't belong in this
data file. Left as-is.
