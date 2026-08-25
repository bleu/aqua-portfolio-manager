# ADR-0003: Track exposure by oracle-valued token groups, not per-token targets

**Status:** Accepted — revised 2026-08-25 to correct the Context's phrasing (the strategy
never buys anything itself; see ADR-0004)

## Context

The LP could declare a target weight per individual token, or per a coarser bucket. Per-token
targets force a decision this design wants to avoid: if the LP says "30% longtail," which
specific longtail token should that 30% be? The strategy never initiates a trade — it only
prices whatever cross-group pair a taker brings, discounting trades that move the portfolio
toward target and charging more for trades that move it away ([ADR-0004](0004-constant-mean-weighted-curve-pricing.md))
— so a per-token target still needs one concrete token to price toward. That's an active
allocation call, not portfolio maintenance, and it's not something an immutable strategy
should be making.

Grouping by asset class (e.g. "majors", "stablecoins") lets the LP set a target at the level
they care about, and leaves intra-group composition unmanaged.

## Decision

Each token in the declared universe is tagged to a group. Group weight = oracle-valued group
total ÷ portfolio total. Takers bring any cross-group pair; the pricing curve (ADR-0004) reacts
to group-weight impact, not individual-token impact. Intra-group drift is allowed by design.

## Consequences

- Sidesteps deciding which specific longtail token to target.
- Makes the LP's own curation quality load-bearing: a group is only as safe as its
  weakest-oracle member, and a depeg inside a group can leak value if the feed lags. Both are
  accepted as curation responsibilities, not code bugs — default to well-fed tokens, warn on
  thin ones, guard divergence inside stable groups.
- Because grouping is baked into the immutable strategy config at `ship()` time, changing a
  group assignment means shipping a new strategy and docking the old one (same cost as any
  other config change — see ADR-0002 and ADR-0010).
