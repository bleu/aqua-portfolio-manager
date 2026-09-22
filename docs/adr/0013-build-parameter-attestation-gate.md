# ADR-0013: Require parameter attestation before trading

**Status:** Accepted.

## Context

Aqua permits registering (shipping) a strategy without calling PM's validator.
Attestation is the validator's stored record that the strategy passed its checks.
A recommended validation batch alone cannot stop a caller from skipping the checks.

## Decision

`attestBuildParameters(order, tokens)` validates the encoded settings, token list, and initial deviation limit.
It records `buildParamsAttested[keccak256(abi.encode(order))] = true`.
PM checks this flag before decoding arguments on every quote or swap.

Anyone can request attestation, including repeat requests, because the validator performs the checks on-chain.
The flag is never cleared.

## Alternatives considered

- **Validation without stored attestation:** leaves no evidence for the swap instruction to check.
- **Maker-only attestation:** restricts who records a publicly verifiable result without improving the checks.
- **Require later shipping parameters to match attestation:** deferred. The recommended procedure instead batches validation and shipping with identical tokens.

## Consequences

- An unattested strategy cannot trade until someone successfully attests it.
- Attestation checks encoded settings that cannot change, which allows the swap path to use `decodeTrusted`.
- Attestation does not enforce the token list used by a later `ship()` call.
- It records the balance check at attestation time, not a guarantee about future balances.
- Combine attestation and shipping with identical tokens in one transaction. Both calls must succeed or both must fail. Signers must verify the batch contents.
- Running both calls in one transaction does not enforce matching token lists. The caller must supply them correctly.
- Each trade pays for a validator call and storage read. Storing the result in the router could reduce that cost.

See [wallet setup](../guides/fresh-wallet-setup.md), the [validator](../../packages/contracts/src/PortfolioManagerStrategyValidator.sol), [ADR-0011](0011-safe-wallet-with-basket-scope-guard.md), and [ADR-0012](0012-price-deviation-circuit-breaker.md).
