# ADR-0016: Per-trade deviation step cap replaces the pre-trade check

**Status:** Accepted.

## Context

[ADR-0012](0012-price-deviation-circuit-breaker.md) added a pre-trade spot-price deviation
check: before pricing a swap, require the pair's *current* spot-price deviation from parity to
be within `maxDeviationBps`. That ADR already recorded the consequence explicitly: "A blocked
pair cannot correct itself through PM."

An AI security audit (BLEUDEV-338, finding BLEUDEV-403) identified that this is reachable by an
ordinary taker at the cost of one trade, not just an external event. The check only reads the
pair's balances *before* the trade -- it does not bound what the trade itself does to those
balances. A single sufficiently large swap can pass the pre-trade check while the pair is
balanced, then push both directions' spot price past `maxDeviationBps`. Every subsequent trade,
including the corrective one that would restore the pair, now starts from that excessive state
and fails the same pre-trade check. The pair stays frozen until an external balance or
oracle-price change happens, or the LP replaces the strategy.

## Decision

Replace the pre-trade check with a per-trade step cap: bound the *change* in spot price the
trade itself causes, not the pair's starting deviation from parity.

```
spBefore = spotPrice(pre-trade balances)
spAfter  = spotPrice(post-trade balances)
require |spAfter - spBefore| <= maxDeviationBps
```

No single trade -- corrective or worsening -- can move the pair's spot price by more than
`maxDeviationBps` in one execution, regardless of where the pair started. A pair that is or
becomes imbalanced beyond `maxDeviationBps` can still trade; it just cannot cross more than
`maxDeviationBps` of distance in one step, so fully correcting a large imbalance may take
several smaller trades instead of one.

This only changes the swap-side check in `PortfolioManagerSwap._portfolioManagerSwapXD`. The
validation-time group-share check in `PortfolioManagerStrategyValidator` (ADR-0012's "during
validation" bullet) is a separate mechanism and is unaffected by this ADR -- see BLEUDEV-407 for
its own, independent fix aligning it to the swap guard's pairwise metric.

## Alternatives considered

- **Allow a trade through if it reduces `|deviation|`, even while still over the limit.** Also
  closes the freeze, but removes the hard per-trade magnitude bound entirely: a taker could still
  walk the price arbitrarily far given enough individually-corrective-labeled trades, since the
  check would only look at direction, not size. Rejected in favor of keeping a hard, direction-
  independent magnitude cap.
- **Leave ADR-0012 as-is, document the freeze as an intentional circuit breaker.** Rejected: the
  freeze is reachable by an ordinary taker at the cost of one trade and its gas, which is a
  stronger guarantee violation than ADR-0012's own "external balance change" framing anticipated.

## Consequences

- `maxDeviationBps` changes meaning for every strategy that set it under ADR-0012's semantics:
  previously a floor/ceiling on the pair's absolute spot price; now a per-trade step limit.
  Existing shipped strategies are unaffected on-chain (same encoded value, same storage slot),
  but the number now bounds something different than when the LP chose it.
- A trade that ADR-0012's pre-trade gate would have rejected outright may now succeed, if its own
  step is within bounds, even starting from an already-imbalanced pair.
- A single trade can no longer freeze a pair in both directions: every direction stays tradable,
  in steps no larger than `maxDeviationBps`.
- The deviation check now runs after `PortfolioManagerPricing.exactIn`/`exactOut` compute the
  trade's amounts, instead of before them, since it needs the post-trade balances.
- `PortfolioManagerSwapExcessivePriceDeviation`'s `spotPriceWad` field now reports the
  (rejected) post-trade spot price, not the pre-trade one.

## References

- `packages/contracts/src/PortfolioManagerSwap.sol` -- `_portfolioManagerSwapXD`'s deviation check.
- BLEUDEV-403 (AI Audit finding, BLEUDEV-338).
