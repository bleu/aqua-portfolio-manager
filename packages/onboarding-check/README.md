# PoC: onboarding pre-existing-strategy check

Standalone TypeScript/Node project — no Foundry/Solidity dependency at runtime or test
time. Closes the other half of the gap [ADR-0011](../../docs/adr/0011-safe-wallet-with-basket-scope-guard.md)'s
`BasketScopeGuard` ([basket-scope PoC](../basket-scope), [BLEUDEV-320](../../)) left open:
the Guard only inspects `ship()` calls made *after* it's installed on a Safe — it has no
way to see, let alone undo, a strategy that Safe already shipped before installation.
Grouped with BLEUDEV-320 as the two tasks validating whether the Safe Guard approach is
viable at all.

**Answer: a one-time, off-chain scan is enough — no on-chain change needed.** Before
installing the Guard on a candidate Safe, replay that Safe's shipping history against the
same group-boundary rule the Guard is about to start enforcing, and refuse to proceed if
anything already violates it.

- `src/scan.ts` — the check itself. `Shipped` events don't carry a strategy's token list,
  but `ship()` emits one `Pushed` event per declared token in the *same* transaction, and
  Aqua's `StrategiesMustBeImmutable` guarantee means a given `(maker, app, strategyHash)`
  can only ever be shipped once — so that transaction's `Pushed` events are the complete,
  permanent token set, not a snapshot. `fetchShippedStrategies` finds a maker's `Shipped`
  events; `reconstructDeclaredTokens` reads the one transaction receipt each resolves to;
  `classifyStrategy` applies `BasketScopeGuard.sol`'s own on-chain rule exactly (PM's own
  trusted strategy hash is always exempt, everything else must stay inside one group).
  Full design rationale, including the unindexed-event-params caveat and why this scans
  fine without an indexer at PoC scale, is in the module's own docstring.
- `src/cli.ts` — run the check from the command line against a real RPC endpoint.
- `test/scan.test.ts` — integration test against a real local Anvil chain: deploys the
  actual compiled Aqua contract (`src/fixtures/aqua-artifact.json`, trimmed from the
  [basket-scope PoC](../basket-scope)'s own build output), ships real strategies (a
  compliant one, a cross-group violation, an outside-the-declared-universe violation, and
  PM's own exempt one spanning two groups), and asserts the check flags exactly the two
  real violations. Not mocked, same standard the rest of this repo's PoCs hold to.

## Running

```bash
pnpm install
pnpm build   # tsc --noEmit
pnpm test    # spins up a real local anvil, requires it on PATH
```

```bash
pnpm cli --rpc <url> --aqua <address> --maker <address> \
  --trusted-strategy-hash <bytes32> --groups <path/to/groups.json> \
  [--from-block <n>] [--to-block <n|latest>]
```

`groups.json`: `{ "<tokenAddress>": "<groupId>", ... }`.
