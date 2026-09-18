# ADR-0013: Build-parameter attestation gate — block trading unless ship-time validation ran on-chain

**Status:** Accepted

## Context

`PortfolioManagerStrategyFactory.requireUniverseMatches` and `requireBalancedWithinTolerance`
(ADR-0012) both exist to catch a real ship-time mistake before it can hurt a taker later — but
neither leaves any trace of having run. The only thing that ever made an LP go through them at all
is convention: the recommended flow batches both checks with the real `Aqua.ship()` call via
`MultiSendCallOnly`, in the same atomic transaction. `Aqua.ship()` itself has no idea the factory
exists — it's permissionless, and nothing stops a caller from invoking it directly, skipping
validation entirely. A strategy shipped that way prices and trades exactly as if it had been
validated, because from the swap opcode's point of view, it had no way to tell the difference.

This is the same shape of gap `ADR-0011`'s Basket Scope Guard closed for cross-basket strategies:
a check that only runs if the caller happens to cooperate isn't a check at all, just a suggestion.
That Guard's own fix — `attestOnboardingClean`/`onboardingAttested`, a persisted on-chain fact
checked before allowing the risky action — is the closest existing precedent in this codebase and
the one this design mirrors in naming and shape.

## Decision

`PortfolioManagerStrategyFactory` gains `mapping(bytes32 => bool) public buildParamsAttested` and
`attestBuildParameters(order, tokens)`, which runs both existing checks and then records
`buildParamsAttested[strategyHash] = true`. `PortfolioManagerSwap`'s opcode checks this flag —
first thing, before parsing anything else — and reverts outright if it's never been set for that
strategy's hash.

Checked on *every* swap, not specially on "the first" one: the flag is monotonic (set once, never
unset), so if it was true for swap #1 it's true for every swap after, and if it was false, swap #1
already reverted — there's no "swap #2" scenario the two behave differently on. No firstness
special-case is needed to get the described behavior.

Unlike `attestOnboardingClean` (restricted to the Safe itself, since it's a subjective off-chain
claim about wallet history), `attestBuildParameters` is **permissionless and idempotent** — no
`msg.sender` check, no revert on re-attesting. The fact it records is a purely mechanical,
independently-recomputable on-chain computation (does this `tokens` array match the declared
universe; is the wallet within tolerance), not an authorization decision — restricting who's
allowed to *record* an already-independently-verifiable fact adds no safety.

## Alternatives considered

- **Keep `requireUniverseMatches`/`requireBalancedWithinTolerance` as the only entrypoints, no
  persisted state.** This is the status quo the gap describes — rejected precisely because it
  relies on every caller cooperating with a convention `Aqua.ship()` never enforces.
- **Restrict `attestBuildParameters` to `order.maker` only**, mirroring `attestOnboardingClean`
  exactly. Rejected: unlike onboarding cleanliness (something only the Safe owner can meaningfully
  claim), universe-match and tolerance are facts anyone can already verify by calling the existing
  `view`/`pure` checks directly — restricting who can *persist* that verification doesn't add
  anything, and would make legitimate third-party tooling (indexers, keepers) unable to attest on
  an LP's behalf for no benefit.
- **Cryptographically bind the attested `tokens` array to whatever `ship()` later actually uses**
  (e.g. storing a hash of `tokens` alongside the attestation, checked again at ship time). Out of
  scope here — see Consequences below for why the atomicity requirement this ADR inherits (not
  introduces) already covers the same ground for the recommended flow.

## Consequences

- **A strategy that's never been attested is permanently blocked from trading**, not just
  discouraged — this is the point, not a side effect. There is no recovery path other than calling
  `attestBuildParameters` for that exact `strategyHash` with parameters that actually pass.
- **`attestBuildParameters`'s `tokens` argument isn't cryptographically bound to whatever a later,
  separate `ship()` call actually uses.** Attesting with a correct `tokens` array and then shipping
  a *different* one (in a separate, non-atomic transaction) still leaves the strategy "attested" by
  a set of parameters that no longer describes what's actually on Aqua's ledger. This isn't a new
  gap introduced here — `requireUniverseMatches` already had the identical assumption before this
  ADR, since nothing ever verified a standalone validation call's `tokens` matched a separate
  `ship()` call's `tokens` either. The requirement this ADR carries forward, unchanged: attest and
  ship **must** be batched atomically, with the literal same `tokens`/`amounts`, in the same
  transaction — exactly what the recommended `MultiSendCallOnly` flow already does.
- One additional `STATICCALL` + `SLOAD` per swap (reading `buildParamsAttested`) — cheap, and paid
  by every trade regardless of whether the strategy was ever going to be a problem, in exchange for
  closing a structural gap rather than trusting convention.

## References

- `docs/adr/0011-safe-wallet-with-basket-scope-guard.md` — `attestOnboardingClean`'s precedent,
  and the permissionless/idempotent divergence from it explained above
- `docs/adr/0012-price-deviation-circuit-breaker.md` — the two checks this attestation wraps
- `src/BasketScopeGuard.sol` — `onboardingAttested`/`attestOnboardingClean`/`AlreadyAttested`
