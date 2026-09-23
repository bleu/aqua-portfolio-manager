# Arbitrageur

An off-chain taker/solver stand-in for 1inch's Pathfinder, so a deployed Portfolio Manager
strategy's tradeability can actually be exercised end-to-end -- not just unit-tested in Foundry.

## Why this exists

Pathfinder is closed-source with **no self-hosted or forked-mainnet-testable equivalent**
(`docs/ARCHITECTURE.md`'s Milestone 1 section). Every real trade against a live PM strategy is
meant to come from *some* external taker or solver calling the router directly -- Pathfinder is
one path to that, but not the only one, and not one we can test against ourselves. This package
is that external taker, played by a real (or fork-local) EOA instead of a same-transaction
Foundry mock (`lib/swap-vm/test/mocks/MockTaker.sol`, which only works inside a Foundry test
process).

## Architecture

Two halves, split deliberately along the "protocol encoding vs. trading decisions" line:

- **On-chain: `packages/contracts/src/Arbitrageur.sol`.** A minimal, owner-controlled contract
  that builds SwapVM's packed `TakerTraits` encoding once, in Solidity, reusing the same audited
  `TakerTraitsLib` the rest of this codebase already relies on. Exposes `quoteExactIn` (a
  static-call-safe price simulation), `executeArbitrage` (a self-funded trade, pulling tokens from
  the owner), and `executeFlashArbitrage` (borrows the input token from Balancer's Vault instead
  -- see "Flash-loan execution" below) -- so its owner can be an ordinary EOA with no
  `ITakerCallbacks` implementation. Hand-replicating `TakerTraitsLib`'s bit-packed encoding in
  TypeScript, with no test coverage protecting it, was a correctness risk not worth taking (see
  the contract's own doc comment).
- **Off-chain: this package.** The actual "pathfinder" logic -- deciding *whether* a trade is
  profitable and *how large* to size it -- reading the strategy's own Chainlink feeds (the same
  ones `OracleAdapter.sol` reads) as the fair-value reference, comparing them against the curve's
  actual quoted price via `Arbitrageur.quoteExactIn`, and (for the flash-loan path) asking a
  locally-running **Fynd** server for the best real-market route to close the loop.

## Flash-loan execution

The default, automated flow (`src/index.ts`) never holds or approves standing capital in the
owner EOA's wallet -- only enough ETH to pay gas. Every arbitrage borrows exactly what it needs,
trades, and repays within one atomic transaction:

```
                         ┌─ 1. Flash-borrow tokenIn from Balancer's Vault (0% fee) ─┐
                         │                                                          │
oracle price (Chainlink) ─┤                                                          ▼
                         │                                         2. Swap tokenIn -> tokenOut
curve price (PM's curve) ─┘                                            against the PM curve
                                                                                     │
                                                                                     ▼
                                                          3. Swap tokenOut -> tokenIn via
                                                             Fynd's best real-market route
                                                                                     │
                                                                                     ▼
                                                          4. Repay the Vault; keep the profit
```

**Why this is safe even though step 3 routes through arbitrary, off-chain-supplied calldata:**
the final check inside `Arbitrageur.receiveFlashLoan` is that this contract's `tokenIn` balance
covers the amount owed -- if Fynd's route (or the market) slips worse than expected, that check
fails and the *entire* transaction reverts, including the curve trade from step 2. A bad attempt
costs gas, never borrowed principal. Slippage buffers and the minimum-profit threshold are
optimization on top of that hard guarantee, not what makes the design safe.

**Why Fynd, and why self-hosted.** [Fynd](https://github.com/propeller-heads/fynd) (PropellerHeads,
built on their Tycho engine) is an open-source, real-time DEX routing engine -- the off-chain
equivalent of what this package's own `pricing.ts` search does for the PM curve alone, but across
the real market. It runs as a small local HTTP server, so `src/fynd.ts` points a client at it
directly rather than depending on a hosted API.

`src/fynd.ts` uses the official `@kayibal/fynd-client` package's `FyndClient.quote` (with
`encodingOptions` set, so the response includes a ready-to-call `transaction`) and
`FyndClient.info` (to get the router's address, the spender that ends up holding the approval).
The client's higher-level `swapPayload`/`executeSwap` methods build an EOA sign-and-submit flow;
this package skips those and uses only the raw `quote`/`info` calls, since what step 3 above
needs is calldata a *contract* can call mid-transaction, not something an EOA signs.
`encodingOptions`'s default `transferType` (`'transfer_from'`) means the router pulls the
approved amount via a plain `approve()`, not Permit2 -- there's no EOA available mid-flash-loan
to produce a Permit2 signature with.

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

### Balancer's Vault

`Arbitrageur`'s constructor now takes a `balancerVault` address -- Balancer V2's Vault is deployed
at the same canonical address (`0xBA12222222228d8Ba445958a75a0704d566BF2C8`) on every EVM chain
it supports, Base included, so this is a fixed constant, not something to look up per-deployment.
Flash loans there are 0% fee as of this writing.

## Opportunity search

`pricing.ts`'s `findBestOpportunity` probes `SEARCH_STEPS` geometrically-spaced trade sizes
between `MIN_TRADE_AMOUNT` and `MAX_TRADE_AMOUNT` (log-spaced, so a wide range still gets even
coverage across orders of magnitude) and picks whichever size clears `MIN_PROFIT_BPS` by the
widest margin. This is a bounded approximation, not a true optimum -- good enough for a
test/monitoring tool. A tighter search (e.g. exploiting the curve's known concavity) is a
reasonable future improvement, not a correctness requirement.

**Basket-wide, not one fixed pair.** The strategy's declared universe is two groups -- group A
(e.g. `{USDT, USDC}`) and group B (e.g. `{WBTC, WETH}`) -- and the PM curve only ever prices a
trade between two *different* groups (`PortfolioManagerSwap._resolve`'s own `groupInIdx !=
groupOutIdx` check). `src/index.ts` builds every cross-group directed pair (every group-A member
against every group-B member, both directions) from `GROUP_A_TOKENS`/`GROUP_B_TOKENS` and checks
all of them every tick, not just one hardcoded pair.

## Running against a local Base fork

This repo currently has no deploy script (`packages/contracts/script/` was intentionally removed
in favor of self-contained E2E tests, see `test/e2e/base/AquaE2EBase.t.sol`'s own doc comment), so
standing up something for this server to talk to is a few manual steps:

1. **Fork Base locally:**
   ```
   anvil --fork-url https://mainnet.base.org --chain-id 8453
   ```
2. **Deploy the router, ship a strategy, and deploy `Arbitrageur`.** The quickest path is a small
   ad hoc `forge script` mirroring `test/e2e/ArbitrageurFlashE2E.t.sol`'s `setUp()` (which does
   exactly this against the same fork pattern, including the two-group USDT/USDC vs. WBTC/WETH
   basket) -- deploy `PortfolioManagerRouter` + `PortfolioManagerStrategyValidator`, ship the
   strategy from a Safe (see `docs/guides/fresh-wallet-setup.md`), then:
   ```
   forge create src/Arbitrageur.sol:Arbitrageur \
     --rpc-url http://127.0.0.1:8545 --private-key <anvil-key> \
     --constructor-args <router-address> 0xBA12222222228d8Ba445958a75a0704d566BF2C8 <owner-eoa-address>
   ```
3. **Start a local Fynd server** pointed at the same fork (see "Running a local Fynd server"
   above) -- on a local anvil fork, Fynd needs `RPC_URL`/equivalent config pointed at
   `http://127.0.0.1:8545` too, not the public Base RPC, so its quotes reflect the fork's state.
4. **Copy the shipped order's `(maker, traits, data)`** into `PM_ORDER_MAKER` /
   `PM_ORDER_TRAITS` / `PM_ORDER_DATA` (from the ship script's logs).
5. **Run in dry-run mode first:**
   ```
   cp .env.example .env   # fill in the values above
   DRY_RUN=true pnpm --filter @aqua-portfolio-manager/arbitrageur dev
   ```
   Confirm it logs the opportunities you expect before setting `DRY_RUN=false`. No token funding
   step is needed for the owner EOA -- the flash-loan path means it never holds `tokenIn` at all.

## Scripts

- `pnpm dev` -- runs `src/index.ts` directly (via `tsx`), restarting on file change.
- `pnpm build` / `pnpm start` -- compiles to `dist/` and runs the compiled output.
- `pnpm typecheck` -- `tsc --noEmit`.
- `pnpm test` -- `vitest run`, covering `pricing.ts`'s pure functions (fair-value conversion,
  profit calculation, the geometric search) against synthetic quote functions, and `fynd.ts`'s
  request-building and response-mapping against a fake `FyndClient` -- no live chain or Fynd
  server needed for either.
