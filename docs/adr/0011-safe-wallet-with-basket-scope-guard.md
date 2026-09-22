# ADR-0011: Require a Safe with a Basket Scope Guard

**Status:** Accepted.

## Context

Other strategies can change the balances PM uses for pricing.
Their trades do not follow PM's invariant, so PM's donation proof does not cover them.
The design restricts which token groups another strategy can declare.

## Decision

Require a dedicated Safe with a Basket Scope Guard.
For direct Aqua `ship()` calls, allow the exact trusted PM strategy hash to span groups.
Require every token in another strategy to belong to one common declared group.

Use `keccak256(strategy)` as the trust anchor because one router can execute many different strategies.
Fix the trusted hash and token-to-group mapping at Guard construction.

## Alternatives considered

- **Oracle-informed rewards:** add a safety dependency on oracle values and a separate reward proof.
- **Layered circuit breakers and time-decay surcharges:** add parameters and failure modes.
- **EOA wallet:** cannot host a Safe Guard.
- **PM-only wallet:** removes other strategies but gives up shared-wallet use. It remains available to LPs.

## Consequences and limits

- Install the Guard before shipping. Check prior active strategies off-chain because the Guard cannot inspect event history.
- The implementation checks the transaction target and selector. It does not inspect nested calls, including `MultiSendCallOnly` batches.
- Signers must therefore inspect batches that ship strategies. The Guard is not complete enforcement over arbitrary Safe execution.
- Module transactions need a separately installed module guard on Safe 1.5.0 or later. The policy remains to exclude arbitrary-call modules.
- Owners can remove the Guard or transfer tokens directly under the Safe's signature threshold.
- Replacing trusted strategy bytes or the group mapping requires a new Guard.
- Within-group trading remains possible. Group membership alone does not prove that another strategy preserves the group's oracle-valued total.

These limits qualify the original design's claim of structural closure.
The Guard restricts declarations on the calls it sees. It does not extend the curve proof to arbitrary wallet activity.

## References

- [BasketScopeGuard](../../packages/contracts/src/BasketScopeGuard.sol): actual call coverage.
- [Wallet setup](../guides/fresh-wallet-setup.md): installation and signer checks.
- [ADR-0003](0003-oracle-valued-token-groups.md): group valuation.
- [Invariant proof](../DONATION-RESISTANCE-PROOF.md): mathematical scope.
