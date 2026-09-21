# ADR-0012: Price-deviation circuit breaker for extreme off-target composition

**Status:** Accepted

## Context

`ADR-0011`'s Basket Scope Guard restricts which *strategies* can move tokens through the Safe — but it only inspects `AQUA.ship()` calls. It says nothing about the Safe owner's own ordinary transactions: a plain `execTransaction` moving tokens straight out of the wallet, outside `ship()`/`swap()` entirely. `DONATION-RESISTANCE-PROOF.md`'s scope is explicit that it covers donations and cross-strategy interaction, not this case.

Nothing in the curve or in `ship()` today notices when this happens. `PortfolioManagerPricing`'s own price impact discourages a *single trade* from moving a group pair further off target, but it has no opinion on the *starting* state — a wallet that's already badly skewed (drained on one side, by a direct withdrawal or by drift no one corrected) is priced exactly the same as a healthy one. `ship()` itself never checks that a wallet's starting composition matches its declared target weights at all.

**This is not a re-run of `ADR-0006`'s already-rejected tolerance band.** That design dampened the curve's reaction to *small* deviations, purely to cut rebalancing-churn cost — its own text is explicit that it isn't a security requirement, since `ADR-0007`'s invariant-based proof already covers donation resistance regardless of smoothing. This ADR's mechanism is the opposite shape: a hard ceiling that *blocks* trading (or shipping) once deviation from target gets *extreme*, closing a gap the existing proofs never claimed to cover, not tuning how the curve reacts within the range they do cover.

The mechanism reuses existing pricing math rather than inventing new math: `PortfolioManagerPricing.spotPrice(quote) = (B_i/w_i)/(B_o/w_o)` equals exactly `WAD` (1e18) whenever a group pair's real, oracle-valued composition exactly matches its declared target weights, regardless of the weight ratio, and diverges from `WAD` in proportion to how far off-target it's drifted. "How far has this pair drifted from target" reduces to "how far has `spotPrice` drifted from `WAD`."

## Decision

A new per-strategy parameter, `maxDeviationBps` (`uint32`, `PM_BPS`-scaled, same convention as `feeBps`), appended to `PortfolioManagerArgsCodec`'s encoded args. `0` disables the mechanism entirely — existing and future strategies that don't set it see no behavior change.

Two checks, both gated on `maxDeviationBps != 0`, each solving a different half of the problem:

- **Swap-time, pairwise:** in `PortfolioManagerSwap`, immediately after building the pair's `Quote` (before pricing the trade), `spotPrice(quote)`'s deviation from `WAD` is checked against `maxDeviationBps`. Only the two groups already involved in the trade — not the whole portfolio — keeping the hot path's cost unchanged for every group not being traded. This is a check against *current* state, not the hypothetical post-trade state: it answers "is this pair already too far gone to trade against," not "would this specific trade push it over."
- **Ship-time, whole-portfolio:** a new `view` function on `PortfolioManagerStrategyValidator`, `requireBalancedWithinTolerance`, checks every group's real share of total portfolio value against its target weight. A one-time cost paid at `ship()`, so checking the whole portfolio (not just a pair) is affordable — batched as a third leg alongside the existing `requireUniverseMatches` call in the same `MultiSendCallOnly` transaction.

Both parse the same `maxDeviationBps` out of the same encoded args — one config *value*, not two —
but the two checks measure different things against it: the swap-time check is a price-ratio
deviation (normalized by `WAD`), the ship-time check is a portfolio-share deviation (normalized by
the group's own target weight). They coincide closely for a 50/50 two-group pair, but diverge for
unequal weights or more groups — the same configured number is not equally strict on both sides in
general. Not reconciled here; worth a follow-up decision on whether they should share one formula.

## Alternatives considered

- **Whole-portfolio check at swap time too**, for consistency with the ship-time check. Rejected: it would make every trade's gas cost scale with the number of declared groups, even for groups the trade never touches, for no benefit the pairwise check doesn't already provide — a swap only ever moves value between the two groups it names.
- **Post-trade check** (does *this* trade push the pair over the limit) instead of pre-trade (is the pair *already* over the limit). Rejected in favor of pre-trade: post-trade would let the very last unit of an already-critical trade squeak through right up to the boundary, and makes the "frozen until external action" consequence below fuzzier — pre-trade is the simpler invariant to reason about and to test.
- **Smoothing the deviation reading itself** (EMA/TWAP) before comparing to the threshold, to avoid a single-block reading tripping the breaker. Rejected for the same reason `ADR-0006` rejected it for the curve's own pricing: a lag between real balance and the quoted/checked value is exactly what a patient attacker trades against during convergence, and this mechanism's whole point is reacting to the real, current state.

## Consequences

- **A skewed pair can become permanently untradeable through this mechanism alone.** Once a group pair's `spotPrice` has drifted past `maxDeviationBps`, no single trade can move it back within tolerance and pass the same pre-trade check in one step — the swap-time guard blocks every trade on that pair until something outside the mechanism restores it (the owner deposits tokens back, or a fresh strategy is shipped with a rebalanced wallet). This is deliberate hard-circuit-breaker behavior, not a self-healing rate limiter, and should be communicated to LPs as a real operational consequence of setting a nonzero `maxDeviationBps`, not a bug.
- **Byte budget:** `+4` bytes on `PortfolioManagerArgsCodec`'s encoded args against the wire format's 255-byte cap. The heaviest declared universe in the test suite (2 groups, 5 members total) still fits comfortably under it.
- **Opt-in, zero-cost when unused:** `maxDeviationBps == 0` skips both checks outright, so strategies that don't need this see no gas or behavior change.
- Closes the gap `DONATION-RESISTANCE-PROOF.md` was explicit it didn't cover: a direct Safe-owner withdrawal that never touches `ship()`/`swap()`, and so never crosses `BasketScopeGuard`'s own inspection point, can still be caught the next time someone tries to trade against — or ship a fresh strategy onto — that wallet.

## References

- `docs/PRICING.md` — `spotPrice`'s formula, reused directly here
- `docs/adr/0003-oracle-valued-token-groups.md` — the group-value aggregation `spotPrice`'s inputs are built from
- `docs/adr/0006-exposure-smoothing.md` — the previously-rejected tolerance-band/smoothing design this ADR is deliberately not repeating
- `docs/adr/0007-donation-resistance-via-curve-invariant.md`, `docs/DONATION-RESISTANCE-PROOF.md` — the proof whose stated scope (donations, cross-strategy interaction) excludes the direct-withdrawal gap this ADR closes
- `docs/adr/0011-safe-wallet-with-basket-scope-guard.md` — the Guard this ADR's gap sits outside of (it only inspects `ship()`-routed strategies)
