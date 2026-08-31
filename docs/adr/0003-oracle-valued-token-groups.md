# ADR-0003: Track exposure by oracle-valued token groups, not per-token targets

**Status:** Accepted — revised 2026-08-25 to correct the Context's phrasing (the strategy never buys anything itself; see ADR-0004)

## Context

The LP could declare a target weight per individual token, or per a coarser bucket. Per-token targets force a decision this design wants to avoid: if the LP says "30% longtail," which specific longtail token should that 30% be? The strategy never initiates a trade — it only prices whatever cross-group pair a taker brings, discounting trades that move the portfolio toward target and charging more for trades that move it away ([ADR-0004](0004-constant-mean-weighted-curve-pricing.md)) — so a per-token target still needs one concrete token to price toward. That's an active allocation call, not portfolio maintenance, and it's not something an immutable strategy should be making.

Grouping by asset class (e.g. "majors", "stablecoins") lets the LP set a target at the level they care about, and leaves intra-group composition unmanaged.

## Decision

Each token in the declared universe is tagged to a group. A group's value is `Σ (token_balance_j × oracle_price_j)` over every token `j` it holds — every member's price must resolve to the same numeraire for that sum to mean anything (e.g. a "stables" group of USDC + EURC needs both converted to USD, not summed as raw token amounts; EUR/USD floats, so the two are never actually interchangeable 1:1). Group weight = that oracle-valued group total ÷ portfolio total (the same sum computed across every group). Takers bring any cross-group pair; the pricing curve (ADR-0004) reacts to only the two involved groups' weight impact — a third group's balance doesn't enter that trade's price at all, the same way a Balancer pool's pairwise swap formula never depends on a token that isn't one of the two sides being swapped. Intra-group drift is allowed by design.

## Consequences

- Sidesteps deciding which specific longtail token to target.
- Makes the LP's own curation quality load-bearing: a group is only as safe as its weakest-oracle member, and a depeg inside a group can leak value if the feed lags. Both are accepted as curation responsibilities, not code bugs — default to well-fed tokens, warn on thin ones, guard divergence inside stable groups.
- A multi-token group's price needs every member's feed to be fresh, not just the two tokens actually changing hands in a given trade — see ADR-0005's staleness decision. One stale feed blocks trading against that whole group until the feed updates or the LP re-groups. This is a related but distinct consequence from the "weakest-oracle member" point above: that one is a bounded *value-leak* risk (a lagging or depegged feed skews a price); this one is an *availability* risk (a feed judged too stale to use at all freezes the group's trading, not its pricing accuracy).
- `proofs-of-concept/swapvm-multi-token/src/BasketXYCSwap.sol`'s PoC doesn't yet implement this: it adds a basket token's raw balance with no price conversion, which is only correct by coincidence when every group member happens to be worth the same. The simulation model (`simulation/src/aqua_sim/basket.py`) has been corrected to convert through each member's own price — currently on a separate open PR (#12), not yet merged as of this writing. The Solidity PoC fix is tracked separately, not done by this ADR.
- Because grouping is baked into the immutable strategy config at `ship()` time, changing a group assignment means shipping a new strategy and docking the old one (same cost as any other config change — see ADR-0002 and ADR-0010).
