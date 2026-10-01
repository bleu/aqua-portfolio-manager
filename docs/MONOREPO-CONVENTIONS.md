# Monorepo conventions

This repo splits `packages/*` into two kinds: apps and packages. Pedro's review on PR #45 asked for this distinction to be written down, not just applied once (BLEUDEV-398).

## Apps

An app is something that runs as its own process and owns a piece of ADR-0014's architecture end to end: `arbitrageur` (the off-chain taker service), `indexer` (the Envio-backed event indexer), `web` (the frontend). Each app may depend on any number of packages. Apps do not depend on each other.

## Packages

A package is a library with no process of its own: code two or more apps need, or will clearly need soon. `decoding` (Aqua order/program byte decoding) is the first one, extracted because the indexer and a future web UI both need the same decode logic the arbitrageur already had.

A package has no `dev`/`start` script, no database, no queue, no server. Its `package.json` exposes `build`, `typecheck`, and `test` only.

## Where new code goes

Write code inside the app that needs it first. Extract it into a package only once a second app actually needs the same logic, not in anticipation of one that might. Premature extraction costs an extra workspace boundary (import paths, a separate `package.json`, a separate test suite) for code nothing else uses yet.

When extracting, move the file with its git history (`git mv`), update every import site, and keep the original tests running unchanged against the new location.

## Known duplication not yet addressed

Well-known token and Chainlink-feed addresses are hardcoded independently in four places: `packages/contracts/script/ShipStrategy.s.sol`, `packages/indexer/config.yaml`, `packages/indexer/src/EventHandlers.ts`'s `SEED_AGGREGATOR_TO_PROXY` map, and `packages/arbitrageur/.env`'s `ALLOWED_TOKENS`/`ALLOWED_FEEDS`. This is the same root cause as the decoding duplication risk, but shipping a strategy and seeding an indexer config aren't quite the same shape of problem as a shared TypeScript function, so it's left as a separate decision rather than folded into the `decoding` package. See BLEUDEV-399.
