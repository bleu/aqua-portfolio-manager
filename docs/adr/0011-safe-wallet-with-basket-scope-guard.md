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

Identify the trusted strategy by `keccak256(strategy)` because one router can execute many different strategies.
Fix the trusted hash and token-to-group mapping at Guard construction.

## Alternatives considered

- **Rewards based on price feeds:** make safety depend on those prices and require a separate proof for the rewards.
- **Combined price limits and surcharges that decrease over time:** add settings and ways the system can fail.
- **Wallet controlled directly by a private key (EOA):** cannot host a Safe Guard.
- **PM-only wallet:** removes other strategies but gives up shared-wallet use. It remains available to LPs.

## Consequences and limits

- Install the Guard before shipping. Check prior active strategies off-chain because the Guard cannot inspect event history.
- The implementation checks the destination contract and function identifier. It does not inspect nested calls, including `MultiSendCallOnly` batches.
- Signers must therefore inspect batches that ship strategies. The Guard does not check everything a Safe can execute.
- Module transactions need a separately installed module guard on Safe 1.5.0 or later. The policy remains to exclude modules that can make unrestricted calls.
- Owners can remove the Guard or transfer tokens directly with the Safe's required number of owner signatures.
- Replacing trusted strategy bytes or the group mapping requires a new Guard.
- Within-group trading remains possible. Group membership alone does not prove that another strategy preserves the group's oracle-valued total.

These limits mean the Guard does not eliminate all risks from other strategies.
The Guard restricts declarations on the calls it sees. It does not extend the curve proof to arbitrary wallet activity.

## References

- [BasketScopeGuard](../../packages/contracts/src/BasketScopeGuard.sol): actual call coverage.
- [Wallet setup](../guides/fresh-wallet-setup.md): installation and signer checks.
- [ADR-0003](0003-oracle-valued-token-groups.md): group valuation.
- [Invariant proof](../DONATION-RESISTANCE-PROOF.md): mathematical scope.
- [Zodiac Scope](https://github.com/gnosisguild/zodiac-guard-scope) and [Roles](https://github.com/gnosisguild/zodiac): examples of restricting permitted calls.
- [Milionis et al.](https://arxiv.org/abs/2208.06046) and [Balancer Managed Pools](https://balancer.gitbook.io/balancer-v2/products/balancer-pools/managed-pools): research behind rejected reward and circuit-breaker alternatives.
- Historical Code4rena module-guard concern: the exact audit reference still needs verification.
