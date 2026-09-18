# Re-shipping Existing Strategies From the New Wallet — Guide

Migrates an LP's existing **non-PM** Aqua strategies — whatever else the LP already runs on Aqua
from another wallet — into the new dedicated Safe wallet that will also host the Portfolio
Manager strategy, per [ADR-0002](../adr/0002-dedicated-maker-wallet-as-portfolio-scope.md) /
[ADR-0011](../adr/0011-safe-wallet-with-basket-scope-guard.md). This is not about moving PM
itself — PM ships fresh into the new Safe; this is about consolidating the LP's *other* Aqua
activity into that same wallet, if the LP wants to.

## Prerequisites

- The new dedicated Safe wallet already set up and Guard-installed — see
  [Fresh wallet setup + funding](./fresh-wallet-setup.md).
- Know each existing strategy's `app`, `strategyHash`, and declared `tokens`.

## Steps

1. Note each existing strategy's `app`, `strategyHash`, and declared `tokens` — needed to dock it.
2. Dock each existing strategy (`IAqua.dock(app, strategyHash, tokens)`) from its current wallet,
   clearing its balances there.
3. Confirm the new Safe is set up per the fresh-wallet-setup guide (Guard installed).
4. Re-ship each existing strategy from the new Safe (`IAqua.ship(app, strategy, tokens,
   amounts)`).
5. Keep every token in each re-shipped strategy inside a single declared basket —
   `BasketScopeGuard` allows only PM's exact trusted strategy hash to span groups; every other
   strategy must stay within one.

## See also

- [Fresh wallet setup + funding](./fresh-wallet-setup.md).
- ADR-0011 — `BasketScopeGuard`'s group-boundary rule.
