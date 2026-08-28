# ADR-0005: Use Chainlink-style push oracles, bluechip-first, not Pyth pull

**Status:** Accepted

## Context

The 1inch Spot Price Aggregator was ruled out early (off-chain-only, manipulable). Between push
and pull oracle models: with a pull oracle (e.g. Pyth), the trader who submits the swap also
submits the price update, and can pick the most favorable still-valid price within the
staleness window — a direct gaming vector on a design where the oracle sets relative token
value for pricing. A pull oracle also needs a fresh price update for every priced token
submitted in the same transaction when a swap touches a multi-token group (ADR-0003), which is
less efficient and more complex to construct than a swap against an already-updated push feed.

Push oracles (Chainlink-style) remove trader-supplied prices entirely and carry no per-swap
update cost, at the price of weaker longtail coverage than a pull oracle offers and some
residual staleness-driven LVR between updates — judged acceptable since it's bounded by the
pricing curve's price impact (ADR-0004) and is, in effect, the same cost any AMM pays for using
an oracle at all. The longtail gap is addressed by GTM sequencing (launch bluechip-only, expand
later), not by the oracle choice itself.

This also closes a related issue: a single mispriced token distorts every cross-group
valuation, and reliable feeds on bluechip tokens make that unlikely, whereas thin longtail feeds
would not.

## Decision

Oracle = Chainlink-style push feeds only. No trader-supplied price updates. Launch universe
restricted to tokens with trustworthy Chainlink (or equivalent push) coverage; longtail
expansion is a later GTM step, not a launch requirement.

**Staleness rejects the trade, not a fallback price.** Every price read checks the feed's
`updatedAt` against a per-feed configured max-staleness threshold (coverage quality varies by
token, so one global threshold isn't appropriate). A read older than that threshold reverts
the trade outright — no degraded execution, no last-known-good fallback, no partial fill. This
is the concrete behavior behind the Oracle Adapter's "checks staleness" responsibility in
[`ARCHITECTURE.md`](../ARCHITECTURE.md), previously named there but not specified as a
behavior anywhere. The exact per-feed threshold values are a parameter, not a design
decision — deferred to the same place other concrete parameters land (see
[ADR-0006](0006-exposure-smoothing.md) for the pattern).

## Consequences

- Closes the pull-oracle gaming vector and the one-bad-price contagion risk outright, by
  removing the attack surface rather than bounding it.
- Caps the initial addressable universe to bluechip pairs; longtail expansion is a later GTM
  step.
- Leaves residual staleness LVR between Chainlink updates as an accepted, bounded cost rather
  than something this ADR eliminates.
- A dead or bad oracle has no on-chain pause path today (strategies are immutable) — the only
  recourse is `dock()`ing the strategy. An admin/circuit-breaker pause is deferred future scope.
  The per-trade staleness revert above is a narrower, automatic mitigation for this same
  failure mode: a dead feed can't be traded against even before anyone notices and docks the
  strategy, it just blocks that one group's trades in the meantime.
- A multi-token group (ADR-0003) needs every member's feed fresh for a trade against that
  group to succeed, not just the two tokens actually changing hands — one stale feed on an
  otherwise-uninvolved group member blocks the whole group until it updates.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — Oracle Adapter component notes
