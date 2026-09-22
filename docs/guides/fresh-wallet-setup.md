# Set up a maker wallet

Use a dedicated Safe wallet for the tokens managed by Portfolio Manager (PM).
Aqua calls registering a strategy "shipping" (`ship()`) and disabling it "docking" (`dock()`).
See [ADR-0011](../adr/0011-safe-wallet-with-basket-scope-guard.md) for the Guard's coverage and limits.

## Prerequisites

- The deployed Aqua registry, PM router, and strategy validator addresses.
- PM token groups, target shares, price feeds, fees, and price limits.
- The supported token list, each token's group, and the amounts each strategy may transfer through Aqua (ledger amounts).

Create the Safe before finalizing the order, because its address is part of the order.
Use `keccak256(abi.encode(order))` for the strategy hash.
This equals `keccak256(strategy)` when `strategy = abi.encode(order)`.

## Prepare the Safe

1. Create a dedicated Safe.
2. Check that it has no extensions (modules) that can make unrestricted calls.
3. Finalize the PM order for this Safe.
4. Deploy `BasketScopeGuard` with the Aqua address, Safe address, strategy hash, and token-to-group mapping.
5. Install it with `Safe.setGuard(guardAddress)` before shipping a strategy.
6. Fund the Safe with the declared tokens.
7. Approve Aqua to transfer each declared token from the Safe.

Choose approvals and ledger amounts that cover the intended trades.
The wallet's real balances and Aqua's ledger limits are separate constraints.
If `maxDeviationBps` is enabled, fund the groups close enough to their targets to pass the limit before validation.

## Validate and ship

1. Prepare `attestBuildParameters(order, tokens)` on the validator.
2. Prepare `Aqua.ship(router, abi.encode(order), tokens, amounts)` from the Safe.
3. Combine these calls with the same token list through Safe's `MultiSendCallOnly`, so both succeed or both fail.
4. Check the batch contents before signing.
5. Execute the batch from the Safe.

See [the E2E fixture](../../packages/contracts/test/e2e/base/PortfolioManagerE2EBase.t.sol) for the validation and shipping batch.
The validator must not call `ship()` for the Safe: Aqua records the caller as maker.

The Guard only inspects direct calls to Aqua. It does not inspect the calls inside `MultiSendCallOnly`.
The Safe signers must check the batch. Recorded validation (attestation) does not enforce the token list used by a later shipping call.

## If the Safe has prior activity

Check active strategies across all Aqua apps before adoption.
Use `Shipped` and `Docked` history or the [indexer](../../packages/indexer/README.md) to identify them.
Dock strategies that violate the declared group boundary.
The Guard cannot inspect or undo strategies shipped before installation.

For migration, see [re-shipping existing strategies](re-shipping-existing-strategies.md).
