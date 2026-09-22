# ADR-0003: Value exposure by token group

**Status:** Accepted.

## Context

The LP wants targets for asset classes, such as majors and stablecoins.
Per-token targets would also require the LP to choose each class's internal allocation.
PM prices taker-initiated trades and does not choose which assets to buy.

## Decision

Assign each declared token to one group.
Value a group as `Σ (token balance × oracle price)` in a common quote currency.
Its portfolio share is its value divided by total portfolio value.

Price cross-group trades from the two involved groups' values and target weights.
Other groups do not enter that pair's curve formula.
Leave within-group composition unmanaged. Reject same-group PM swaps.

## Consequences

- The LP is responsible for group membership and feed quality.
- A lagging feed or depeg can expose the group to value loss.
- Every feed in a traded group must be fresh, including feeds for tokens that do not move.
- Changing group membership requires a new strategy and an updated Guard configuration.
- Single-token groups use the same oracle conversion as multi-token groups.

See [pricing](../PRICING.md) for units and [ADR-0005](0005-chainlink-push-oracles.md) for oracle policy.
The raw-balance `BasketXYCSwap` prototype does not implement this valuation.
