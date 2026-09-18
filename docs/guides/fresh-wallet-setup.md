# Fresh Wallet Setup + Funding Guide

Sets up a new dedicated maker wallet for a Portfolio Manager strategy, per
[ADR-0002](../adr/0002-dedicated-maker-wallet-as-portfolio-scope.md) (dedicated wallet) and
[ADR-0011](../adr/0011-safe-wallet-with-basket-scope-guard.md) (Safe + Basket Scope Guard).

## Prerequisites

- PM's strategy bytes already built (weights, groups, fee) — this fixes the strategy hash the
  Guard will trust.
- The declared universe: every token in every group, and which basket each belongs to.

## Steps

1. Deploy a new Safe — this is the dedicated maker wallet; a plain EOA has no code to attach a
   Guard to.
2. Compute the PM strategy's hash off-chain (`keccak256(strategy)`) from its already-built
   strategy bytes.
3. Deploy `BasketScopeGuard`, passing the Safe's address, the trusted PM strategy hash, and the
   universe's token → basket mapping.
4. Install the Guard on the Safe (`Safe.setGuard(guardAddress)`) before shipping anything — the
   Guard cannot see transactions that happened before it was installed.
5. If reusing a Safe with prior activity, first scan its `Shipped` events off-chain to confirm no
   existing strategy already crosses a group boundary.
6. Fund the Safe with only the tokens declared in the universe — nothing else, since the exposure
   reader reads the wallet's real `balanceOf` for every declared token.

## See also

- [Re-shipping existing strategies](./re-shipping-existing-strategies.md) — migrating an existing
  strategy into this new wallet.
- ADR-0002, ADR-0011.
