# Arbitrageur

The production off-chain service that discovers Aqua Portfolio Manager strategies, evaluates them
for arbitrage, and executes profitable trades -- implementing [ADR-0014](../../docs/adr/0014-production-arbitrageur-design.md).

## Why this exists

Pathfinder is closed-source with **no self-hosted or forked-mainnet-testable equivalent**
(`docs/ARCHITECTURE.md`'s Milestone 1 section). Every real trade against a live PM strategy is
meant to come from *some* external taker or solver calling the router directly -- Pathfinder is
one path to that, but not the only one, and not one we can test against ourselves. This service is
that external taker, discovering strategies from [`packages/indexer`](../indexer) instead of a
fixed list, and executing through `packages/contracts/src/Arbitrageur.sol`.

## Architecture

ADR-0014's eight domains, each its own module under `src/domains/`:

| Domain | Module | What it does |
| --- | --- | --- |
| Strategy Catalog | `strategyCatalog.ts` | Decodes each synced Strategy's order, records its resolver KYC token (if gated) and eligibility |
| Balance State | `sync/indexer.ts` | Materializes current token balances per Strategy Wallet from indexed transfers |
| Price State | `sync/indexer.ts` | Materializes the latest usable Chainlink price per feed |
| Candidate Evaluation | `candidateEvaluation.ts` | Screens legs with the oracle pre-filter, gets a real Fynd quote, ranks by Profit Headroom |
| Transaction Simulation | `transactionSimulation.ts` | `eth_call`s the executor before anything is allowed to submit |
| Execution | `execution.ts` | Re-simulates and submits, single concurrency (one wallet, all nonces) |
| Operations API | `api/server.ts` | Read-only, bearer-authenticated, no secrets |
| Notification | `notification.ts` | Slack webhook for submissions, finality, and failures |

`src/workers.ts` wires all of it to the six BullMQ queues from the ADR's Queue rules table
(`sync-indexer`, `evaluate-strategy`, `simulate-candidate`, `execute-candidate`,
`track-transaction`, `retry-evaluation`); `src/main.ts` starts everything as one process.

On-chain, `packages/contracts/src/Arbitrageur.sol` stays a minimal, owner-controlled contract:
`quoteExactIn` (a static-call-safe price simulation) and `executeFlashArbitrage` (borrows the
input token from Uniswap V4's PoolManager, trades, repays, atomically -- see "Flash-loan
execution" below). Hand-replicating SwapVM's packed `TakerTraits` encoding in TypeScript, with no
test coverage protecting it, was a correctness risk not worth taking; that logic stays in
Solidity, reusing the same audited `TakerTraitsLib` the rest of this codebase relies on.

## Flash-loan execution

No standing capital in the owner EOA's wallet -- only enough ETH for gas. Every arbitrage borrows
exactly what it needs, trades, and repays within one atomic transaction:

```
                         ┌─ 1. Flash-borrow tokenIn from Uniswap V4's PoolManager (no fee) ─┐
                         │                                                                   │
oracle price (Chainlink) ─┤                                                                   ▼
                         │                                              2. Swap tokenIn -> tokenOut
curve price (PM's curve) ─┘                                                 against the PM curve
                                                                                              │
                                                                                              ▼
                                                                   3. Swap tokenOut -> tokenIn via
                                                                      Fynd's best real-market route
                                                                                              │
                                                                                              ▼
                                                                4. Repay the PoolManager; keep profit
```

**Why this is safe even though step 3 routes through arbitrary, off-chain-supplied calldata:**
the final check inside `Arbitrageur.unlockCallback` is that this contract's `tokenIn` balance
covers the amount owed -- if Fynd's route (or the market) slips worse than expected, that check
fails and the *entire* transaction reverts, including the curve trade from step 2. A bad attempt
costs gas, never borrowed principal. Slippage buffers and the minimum-profit threshold are
optimization on top of that hard guarantee, not what makes the design safe.

**Step 3 never routes through Uniswap V4.** The PoolManager allows only one active `unlock`
session at a time, and step 1 already holds it for the whole transaction -- a Fynd route that
touches a V4 pool would open a second `unlock` session and revert with `AlreadyUnlocked`.
`src/fynd.ts` excludes the protocol from every quote request (`routeFilter.excludeProtocols`),
plus a defense-in-depth check that a returned route didn't use it anyway.

**Resolver-gated strategies need the credential at quote time too, not just execution.**
`runLoop` executes every instruction in a strategy's program for a `quote()` call exactly like it
does for a real `swap()` -- so a strategy carrying the resolver KYC gate ([ADR-0015](../../docs/adr/0015-two-program-builders-for-the-resolver-kyc-gate.md))
checks `tx.origin` during quoting too. `chain.ts`'s `quoteExactIn` passes the bot's own account as
the `eth_call`'s `from`, or every quote against a gated strategy would fail outright -- see
`packages/contracts/test/e2e/ArbitrageurFlashE2E.t.sol`.

**Why Fynd, and why self-hosted.** [Fynd](https://github.com/propeller-heads/fynd) (PropellerHeads,
built on their Tycho engine) is an open-source, real-time DEX routing engine. It runs as a small
local HTTP server, so `src/fynd.ts` points a client at it directly rather than depending on a
hosted API. Uses the official `@kayibal/fynd-client` package's raw `quote`/`info` calls (not its
higher-level EOA sign-and-submit flow) since what step 3 needs is calldata a *contract* can call
mid-transaction, not something an EOA signs.

### Running a local Fynd server

```
cargo install fynd          # or: docker pull propellerheads/fynd
export TYCHO_API_KEY=...    # ask PropellerHeads / whoever issued yours
export RUST_LOG=fynd=info
fynd serve --chain base
```

Point `FYND_URL` (see `.env.example`) at wherever this ends up listening (`http://127.0.0.1:4000`
by default). See [Fynd's own quickstart](https://github.com/propeller-heads/fynd/tree/main/docs/get-started/quickstart)
for the full setup.

## Opportunity search

Candidate Evaluation's pre-filter computes each leg's optimal trade size directly instead of
searching for it. The curve prices a swap on the two groups' total oracle value, not per-token
balances (`PortfolioManagerSwap._groupValueWad`), and that's exactly Balancer's weighted constant-
product AMM applied to group values (`PortfolioManagerPricing.sol`'s `spotPrice`/`exactIn` mirror
the Balancer whitepaper's eq.2/eq.15 formulas). Balancer's own closed-form "In-Given-Price" formula
(eq.21) gives the trade size that brings a weighted pool's spot price to a target directly, with no
search: `pricing.ts`'s `inGivenPriceValueWad` is that formula, adapted for this curve's group-level
values and its fee-on-input (the whitepaper's base formula excludes fees). The target is always
perfect group-weight equilibrium -- this design's own definition of "fair" (see the price-deviation
circuit breaker, which checks the same ratio against 1), not an external market price.

`MIN_TRADE_USD`/`MAX_TRADE_USD` no longer scope a search; they gate the analytic result instead --
`MIN_TRADE_USD` skips an optimum too small to be worth a quote and gas, `MAX_TRADE_USD` caps risk
per trade even when the curve math favors a bigger one. Whichever direction the formula returns a
positive size for gets exactly one real `quoteExactIn` verification (not the dozen a geometric
search used to cost), scored against the *oracle's* fair value the same way as before. Only a leg
that passes gets a real Fynd quote, ranked by Profit Headroom: the Fynd route's actual expected
return, less principal, less the return-token value of the Profit Floor.

**Oracle pre-filter isolates one bad feed.** A leg whose feed is stale or missing in Postgres is
skipped for that evaluation -- and since a group's value is the sum of every member's own value,
one bad feed disqualifies every leg touching that member's *group*, not just that one token pair.
A healthy leg on an unrelated group is never affected.

## Running the full stack

Needs Postgres, Redis, a running `packages/indexer` instance, and a local Fynd server (above).

```sh
# 1. Start the indexer (separate terminal, see packages/indexer/README.md)
cd ../indexer && pnpm dev

# 2. Migrate this service's own Postgres schema
cp .env.example .env   # fill in DATABASE_URL, REDIS_URL, etc.
pnpm db:generate && pnpm db:migrate

# 3. Run in dry-run mode first
DRY_RUN=true pnpm dev
```

Watch `/health` and `/v1/candidates` on the Operations API (`OPERATIONS_API_PORT`, default 3001 --
not 3000, since that's Fynd's own default port)
to confirm it's discovering strategies and finding opportunities before setting `DRY_RUN=false`.

## Scripts

- `pnpm dev` -- runs `src/main.ts` directly (via `tsx`), restarting on file change.
- `pnpm dev:resilient` -- `pnpm dev` wrapped in a loop that restarts it if the process exits for
  any reason, including an OS-level low-memory kill. Safe against double-submitting a trade on
  restart: job state lives in Redis, not the process, and `execute-candidate` never resubmits
  parameters that already went out (see `run-resilient.sh`).
- `pnpm build` / `pnpm start` -- compiles to `dist/` and runs the compiled output.
- `pnpm typecheck` -- `tsc --noEmit`.
- `pnpm db:generate` / `pnpm db:migrate` -- Drizzle migration generation/application.
- `pnpm test` -- `vitest run`. No live Postgres, Redis, Fynd server, or chain needed: covers
  `pricing.ts`'s pure math, `fynd.ts`'s request-building and Uniswap V4 exclusion against a fake
  client, `sync/indexer.ts`'s cursor and price-normalization logic, and `strategyCatalog.ts`'s
  eligibility check (order/program decoding itself is tested in
  `@aqua-portfolio-manager/decoding`, see `packages/decoding/README.md`).

## Limits

- Verification here is `typecheck`/`build`/`vitest run` plus the Solidity-side E2E suite for the
  on-chain executor. Running the full service against live Postgres/Redis/Fynd/indexer is a manual
  follow-up -- not something this environment can do itself.
- `track-transaction` confirms against live chain depth, not indexer sync progress, even though
  ADR-0014's own Operations section describes waiting for indexer finality specifically -- see
  `src/domains/tracking.ts`'s own doc comment.
- `sync-indexer`'s repeat interval is the practical trigger for "a Strategy, balance, or oracle
  event starts evaluation" -- there's no row-level change notification from Postgres wired up.
- Strategy Catalog and Strategy sync both do a full re-scan/re-evaluation on every tick rather than
  an incremental one -- correct and simple at today's scale, a real follow-up once the catalog
  grows enough to matter (see `sync/indexer.ts` and `strategyCatalog.ts`'s own doc comments).
