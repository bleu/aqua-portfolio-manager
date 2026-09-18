# Arbitrageur (BLEUDEV-349)

An off-chain taker/solver stand-in for 1inch's Pathfinder, so a deployed Portfolio Manager
strategy's tradeability can actually be exercised end-to-end -- not just unit-tested in Foundry.

## Why this exists

1inch confirmed directly that Pathfinder is closed-source with **no self-hosted or
forked-mainnet-testable equivalent** (`docs/ARCHITECTURE.md`'s Milestone 1 section,
`BLEUDEV-346`). Every real trade against a live PM strategy is meant to come from *some* external
taker or solver calling the router directly -- Pathfinder is one path to that, but not the only
one, and not one we can test against ourselves. This package is that external taker, played by a
real (or fork-local) EOA instead of a same-transaction Foundry mock
(`lib/swap-vm/test/mocks/MockTaker.sol`, which only works inside a Foundry test process).

## Architecture

Two halves, split deliberately along the "protocol encoding vs. trading decisions" line:

- **On-chain: `packages/contracts/src/Arbitrageur.sol`.** A minimal, owner-controlled contract
  that builds SwapVM's packed `TakerTraits` encoding once, in Solidity, reusing the same audited
  `TakerTraitsLib` the rest of this codebase already relies on. Exposes two plain-argument
  entrypoints -- `quoteExactIn` (a static-call-safe price simulation) and `executeArbitrage` (a
  real trade) -- so its owner can be an ordinary EOA with no `ITakerCallbacks` implementation.
  Hand-replicating `TakerTraitsLib`'s bit-packed encoding in TypeScript, with no test coverage
  protecting it, was a correctness risk not worth taking (see the contract's own doc comment).
- **Off-chain: this package.** The actual "pathfinder" logic -- deciding *whether* a trade is
  profitable and *how large* to size it -- reading the strategy's own Chainlink feeds (the same
  ones `OracleAdapter.sol` reads) as the fair-value reference, and comparing them against the
  curve's actual quoted price via `Arbitrageur.quoteExactIn`.

```
oracle price (Chainlink, on-chain) ──┐
                                      ├─▶ pricing.ts: is quotedOut > fairOut + minProfitBps?
curve price (Arbitrageur.quoteExactIn) ──┘         │
                                                     ▼
                                     Arbitrageur.executeArbitrage (real tx, EOA-signed)
```

## Opportunity search

`pricing.ts`'s `findBestOpportunity` probes `SEARCH_STEPS` geometrically-spaced trade sizes
between `MIN_TRADE_AMOUNT` and `MAX_TRADE_AMOUNT` (log-spaced, so a wide range still gets even
coverage across orders of magnitude) and picks whichever size clears `MIN_PROFIT_BPS` by the
widest margin. This is a bounded approximation, not a true optimum -- good enough for a
test/monitoring tool. A tighter search (e.g. exploiting the curve's known concavity) is a
reasonable future improvement, not a correctness requirement.

Every tick checks **both directions** (tokenIn→tokenOut and tokenOut→tokenIn), since either side
of the pair could be the one that's mispriced.

## Running against a local Base fork

This repo currently has no deploy script (`packages/contracts/script/` was intentionally removed
in favor of self-contained E2E tests, see `test/e2e/base/AquaE2EBase.t.sol`'s own doc comment), so
standing up something for this server to talk to is a few manual steps:

1. **Fork Base locally:**
   ```
   anvil --fork-url https://mainnet.base.org --chain-id 8453
   ```
2. **Deploy the router, ship a strategy, and deploy `Arbitrageur`.** The quickest path is a small
   ad hoc `forge script` mirroring `test/e2e/base/PortfolioManagerE2EBase.t.sol`'s `setUp()` (which
   does exactly this against the same fork pattern) -- deploy `PortfolioManagerRouter` +
   `PortfolioManagerStrategyValidator`, ship a WETH/DAI strategy from a Safe (see
   `docs/guides/fresh-wallet-setup.md`), then:
   ```
   forge create src/Arbitrageur.sol:Arbitrageur \
     --rpc-url http://127.0.0.1:8545 --private-key <anvil-key> \
     --constructor-args <router-address> <owner-eoa-address>
   ```
3. **Fund the owner EOA with `TOKEN_IN`** -- on a fork, impersonate a known holder
   (`cast rpc anvil_impersonateAccount <whale>` then `cast send`), or use `anvil_setBalance` +
   wrap ETH for WETH.
4. **Copy the shipped order's `(maker, traits, data)`** into `PM_ORDER_MAKER` /
   `PM_ORDER_TRAITS` / `PM_ORDER_DATA` (from the ship script's logs).
5. **Run in dry-run mode first:**
   ```
   cp .env.example .env   # fill in the values above
   DRY_RUN=true pnpm --filter @aqua-portfolio-manager/arbitrageur dev
   ```
   Confirm it logs the opportunities you expect before setting `DRY_RUN=false`.

## Scripts

- `pnpm dev` -- runs `src/index.ts` directly (via `tsx`), restarting on file change.
- `pnpm build` / `pnpm start` -- compiles to `dist/` and runs the compiled output.
- `pnpm typecheck` -- `tsc --noEmit`.
- `pnpm test` -- `vitest run`, covering `pricing.ts`'s pure functions (fair-value conversion,
  profit calculation, the geometric search) against synthetic quote functions -- no live chain
  needed for these.
