# ADR-0007: Use the curve invariant for donation resistance

**Status:** Accepted. The real-arithmetic derivation is in the [proof](../DONATION-RESISTANCE-PROOF.md).

## Context

Anyone can transfer tokens into the maker wallet and change its exposure reading.
Internal accounting could ignore donations but would also lose visibility into other strategies' settlement.

## Decision

Use the constant-mean invariant to analyze PM trades and pure donations.
Price current balances directly, as required by [ADR-0006](0006-exposure-smoothing.md).

## Alternatives considered

- **Internal accounting:** conflicts with wallet-wide exposure measurement.
- **Smoothed balances:** introduce a lag that requires a different proof.

## Consequences

- Donations can still change the wallet's allocation.
- The proof concerns the curve invariant under its assumptions, not arbitrary changes in market value.
- A different strategy's trade is a two-sided balance change and does not inherit PM's invariant guarantee.
- The Guard restricts other strategies' declared groups. Its coverage and trust assumptions are recorded in [ADR-0011](0011-safe-wallet-with-basket-scope-guard.md).
- Fixed-point rounding and arithmetic limits require implementation checks in addition to the real-arithmetic proof.
