# Contracts

Foundry package for this grant's on-chain code. Consolidates what were two standalone
Milestone 1 PoCs (`basket-scope`, `swapvm-multi-token`) into one real package, now that M2
implementation work is starting.

- `src/BasketScopeGuard.sol` — the Safe Transaction Guard from
  [ADR-0011](../../docs/adr/0011-safe-wallet-with-basket-scope-guard.md): closes cross-strategy
  manipulation structurally by confining any strategy other than PM's own to a single declared
  group. `test/BasketScopeGuard.t.sol` covers it both as unit tests and as integration tests
  against a real deployed `Safe` + `SafeProxyFactory`.
- `src/BasketXYCSwap.sol`, `src/PoCOpcodes.sol`, `src/PoCRouter.sol` — the swapVM instruction
  and independent router from [ADR-0010](../../docs/adr/0010-on-chain-form-aquaapp-vs-swapvm-instruction.md):
  prices against a multi-token basket by reading a third token's Aqua balance directly, not
  just the two tokens `Context` describes. `test/BasketXYCSwap.t.sol` covers this end-to-end
  against a real `AquaRouter`.

## Running

```bash
git submodule update --init --recursive -- lib
forge build
forge test
```

## E2E tests (real Base fork)

`test/e2e/` forks Base directly (`vm.createSelectFork`, reading `BASE_RPC_URL` via `vm.envOr`)
and deploys every contract it needs — router, strategy factory, Safe infra, test fixtures —
inline in its own `setUp()`, against Aqua's *real* deployed registry on that fork. No separate
deploy step, no external Anvil process: plain `forge test` above already runs these for real, so
M2 work gets validated against real protocol state, not a clean-room chain.

```bash
cp .env.example .env   # set BASE_RPC_URL to avoid the public endpoint's rate limits
```
