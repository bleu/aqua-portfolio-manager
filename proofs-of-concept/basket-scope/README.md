# PoC: BasketScopeGuard — closing cross-strategy manipulation structurally

Standalone Foundry project — not part of the main repo's build. Supports [ADR-0011](../../docs/adr/0011-safe-wallet-with-basket-scope-guard.md): the LP's maker wallet must be a Safe with a `BasketScopeGuard` installed. ADR-0007's donation proof never covered a *different* strategy trading on the same wallet — a two-sided balance change, not a donation — which could otherwise cross a group boundary and undermine the pricing this strategy relies on. This guard closes that gap by removing the capability instead of bounding it: every outgoing `AQUA.ship(app, strategy, tokens, amounts)` call is inspected before the Safe executes it.

- PM's own, exact strategy (`keccak256(strategy)`, fixed at construction) is always allowed — it's the trusted mechanism meant to price across groups.
- Any other strategy must keep every token it declares inside a single group, and every token must belong to *some* declared group.
- Both the group-membership mapping and the trusted strategy hash have no setter anywhere in the contract — neither can be loosened later by whoever controls the Safe.

`test/BasketScopeGuard.t.sol` covers this both as unit tests against the guard directly and as integration tests against a real deployed `Safe` + `SafeProxyFactory` (not mocked) — a module and `execTransaction` both routed through the actual Guard hook.

## Running

```bash
git submodule update --init --recursive -- lib
forge build
forge test
```
