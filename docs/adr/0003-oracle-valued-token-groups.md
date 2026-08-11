# ADR-0003: Track exposure by oracle-valued token groups, not per-token targets

**Status:** Accepted

## Context

The LP could declare a target weight per individual token, or per a coarser bucket. Per-token
targets force a decision this design wants to avoid: if the LP says "30% longtail," which
specific longtail token should the pool buy? That's an active allocation call, not portfolio
maintenance, and it's not something an immutable strategy should be making.

Grouping by asset class (e.g. "majors", "stablecoins") lets the LP set a target at the level
they care about, and leaves intra-group composition unmanaged.

## Decision

Each token in the declared universe is tagged to a group. Group weight = oracle-valued group
total ÷ portfolio total. Takers bring any cross-group pair; the pricing curve (ADR-0004) reacts
to group-weight impact, not individual-token impact. Intra-group drift is allowed by design.

## Consequences

- Sidesteps deciding which specific longtail token to buy.
- Makes the LP's own curation quality load-bearing: a group is only as safe as its
  weakest-oracle member (critique.md, 1.8), and a depeg inside a group can leak value if the
  feed lags (critique.md, 1.9). Both are accepted as curation responsibilities, not code bugs —
  default to well-fed tokens, warn on thin ones, guard divergence inside stable groups.
- Because grouping is baked into the immutable strategy config at `ship()` time, changing a
  group assignment means shipping a new strategy and docking the old one (same cost as any
  other config change — see ADR-0002 and ADR-0010).

## References

- bleu-brain `1inch-aqua-incubator/portfolio-manager/context.md`, decision 6
- bleu-brain `1inch-aqua-incubator/portfolio-manager/critique.md`, issues 1.8, 1.9
