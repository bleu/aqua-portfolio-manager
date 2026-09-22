# ADR-0007: Use the curve invariant for donation resistance

**Status:** Accepted. The derivation without implementation rounding is in the [proof](../DONATION-RESISTANCE-PROOF.md).

## Context

Anyone can transfer tokens into the maker wallet and change its measured holdings.
Tracking only this strategy's own transfers could ignore donations but would miss other strategies' transfers.

## Decision

Use the weighted curve's mathematical guarantee (invariant) to analyze PM trades and donations that add tokens without taking any out.
Price current balances directly, as required by [ADR-0006](0006-exposure-smoothing.md).

## Alternatives considered

- **Internal accounting:** cannot measure the whole wallet's holdings.
- **Smoothed balances:** introduce a lag that requires a different proof.

## Consequences

- Donations can still change the wallet's allocation.
- The proof concerns the curve invariant under its assumptions, not arbitrary changes in market value.
- A different strategy's trade adds one token and removes another. It does not inherit PM's invariant guarantee.
- The Guard restricts other strategies' declared groups. Its coverage and trust assumptions are recorded in [ADR-0011](0011-safe-wallet-with-basket-scope-guard.md).
- Fixed-point rounding and arithmetic limits require implementation checks in addition to the real-arithmetic proof.
