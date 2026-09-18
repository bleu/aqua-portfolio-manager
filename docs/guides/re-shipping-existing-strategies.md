# Re-shipping Existing Strategies From the New Wallet — Guide

Migrates an LP's existing PM strategy from an old wallet to the new dedicated Safe wallet required
by [ADR-0002](../adr/0002-dedicated-maker-wallet-as-portfolio-scope.md) /
[ADR-0011](../adr/0011-safe-wallet-with-basket-scope-guard.md).

## Prerequisites

- The new dedicated Safe wallet already set up, Guard-installed, and funded — see
  [Fresh wallet setup + funding](./fresh-wallet-setup.md).

## Steps

1. Note the old strategy's `app`, `strategyHash`, and declared `tokens` — needed to dock it.
2. Dock the old strategy (`IAqua.dock(app, strategyHash, tokens)`) from the old wallet, clearing
   its balances there.
3. Confirm the new Safe wallet is set up per the fresh-wallet-setup guide (Guard installed, funded
   with universe tokens only).
4. Re-ship the same strategy config from the new Safe (`IAqua.ship(app, strategy, tokens,
   amounts)`).
5. If shipping anything other than PM's own trusted strategy from that wallet, keep every token
   inside a single declared group — `BasketScopeGuard` allows PM's exact strategy hash
   unconditionally but restricts everything else to one basket.

## See also

- [Fresh wallet setup + funding](./fresh-wallet-setup.md).
- ADR-0011 — `BasketScopeGuard`'s group-boundary rule.
