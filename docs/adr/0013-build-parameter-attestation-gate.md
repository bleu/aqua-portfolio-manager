# ADR-0013: Require parameter attestation before trading

**Status:** Accepted.

## Context

Aqua permits shipping without calling PM's validator.
A recommended validation batch alone cannot stop a caller from skipping the checks.

## Decision

`attestBuildParameters(order, tokens)` validates the encoded arguments, token universe, and configured initial deviation limit.
It records `buildParamsAttested[keccak256(abi.encode(order))] = true`.
PM checks this flag before decoding arguments on every quote or swap.

Attestation is permissionless and idempotent because the validator computes the checks on-chain.
The flag is never cleared.

## Alternatives considered

- **Validation without stored attestation:** leaves no evidence for the swap instruction to check.
- **Maker-only attestation:** restricts who records a publicly verifiable result without improving the checks.
- **Bind attestation to later shipping parameters:** deferred. The recommended procedure instead batches validation and shipping with identical tokens.

## Consequences

- An unattested strategy cannot trade until someone successfully attests it.
- Attestation validates immutable argument bytes, which allows the swap path to use `decodeTrusted`.
- Attestation does not bind the token array used by a later `ship()` call.
- It records the balance check at attestation time, not a guarantee about future balances.
- Batch attestation and shipping atomically with identical tokens. Signers must verify the batch contents.
- Atomic execution alone does not enforce matching arrays. The caller must supply them correctly.
- Each trade pays for a validator call and storage read. A local cache remains a possible optimization.

See [wallet setup](../guides/fresh-wallet-setup.md) and the [validator](../../packages/contracts/src/PortfolioManagerStrategyValidator.sol).
