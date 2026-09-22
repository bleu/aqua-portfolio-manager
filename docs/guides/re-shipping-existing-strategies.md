# Move existing strategies to the maker wallet

This procedure moves non-PM Aqua strategies into the dedicated Safe.
Each strategy must use tokens from one declared group.

## Prerequisites

- Complete [wallet setup](fresh-wallet-setup.md).
- Record each strategy's `app`, strategy bytes, `strategyHash`, tokens, and ledger amounts.
- Check whether its program or authorization binds it to the old maker address.

## Steps

1. Check that every token in each strategy belongs to the same declared group.
2. Dock each strategy from its current wallet with `Aqua.dock(app, strategyHash, tokens)`.
3. Transfer the required capital to the new Safe.
4. Approve Aqua for each token from the new Safe.
5. Prepare each strategy for the new maker address.
6. Ship each strategy directly from the Safe with `Aqua.ship(app, strategy, tokens, amounts)`.
7. Check its active ledger entry and the Safe's remaining balances.

Docking clears Aqua's ledger entry. It does not transfer the wallet's tokens.
Use direct shipping calls so the Guard can inspect them.
See [ADR-0011](../adr/0011-safe-wallet-with-basket-scope-guard.md) for the strategy-hash exception that permits PM to span groups.
