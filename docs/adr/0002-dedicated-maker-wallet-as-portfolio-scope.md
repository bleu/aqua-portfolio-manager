# ADR-0002: Use a dedicated maker wallet

**Status:** Accepted. Revised 2026-08-20 to require a Safe under [ADR-0011](0011-safe-wallet-with-basket-scope-guard.md).

## Context

PM needs the LP's real exposure across strategies.
Aqua's `rawBalances` and `safeBalances` read the same per-`(maker, app, strategyHash)` ledger.
That ledger changes with its own strategy's settlement, not with every trade from the wallet.
`safeBalances` additionally checks that the strategy is active and contains the tokens.

ERC20 `balanceOf(maker)` provides the shared real balance, but a mixed-purpose wallet includes unrelated holdings.

## Decision

Use one dedicated Safe wallet per managed portfolio and declare its token universe.
Read each declared token's `balanceOf(maker)` for pricing.
Use Aqua's ledger separately to authorize settlement. Make no changes to Aqua core.

## Alternatives considered

- **Per-strategy ledger:** cannot measure exposure across strategies.
- **Existing mixed-purpose wallet:** unrelated holdings affect the managed exposure.
- **EOA:** cannot host the Guard required by ADR-0011.

## Consequences

- Adoption requires wallet setup, token funding, Aqua approvals, and migration of existing strategies.
- Tokens outside the declared universe do not affect pricing.
- Real balances and authorized ledger amounts must both cover settlement.
- Donations can change the exposure reading. See [ADR-0007](0007-donation-resistance-via-curve-invariant.md).
- Other strategies can change shared balances. ADR-0011 restricts their declared groups, subject to its coverage limits.

See [wallet setup](../guides/fresh-wallet-setup.md) for the procedure.
