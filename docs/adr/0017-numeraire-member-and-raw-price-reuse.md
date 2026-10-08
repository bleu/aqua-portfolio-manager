# ADR-0017: Let one member be the strategy's numeraire; fetch each feed once per swap

**Status:** Accepted. Refines [ADR-0003](0003-oracle-valued-token-groups.md)'s "single-token
groups use the same oracle conversion as multi-token groups" consequence.

## Context

An AI security audit's gas-cost analysis (BLEUDEV-412) found two independent sources of
avoidable oracle cost in every swap:

1. **Each traded token's feed was read twice.** `PortfolioManagerSwap` values both traded groups
   (rounding the input group up, the output group down) and separately converts the traded
   amounts between native and value units (rounding the opposite way for each). Both steps read
   the *same* traded member's feed, under different roundings -- two `latestRoundData()` calls
   and two `decimals()` calls per traded token, every swap, for a value `OracleAdapter.priceWad`
   already derives from one `(answer, decimals)` read (`scaleUp` for one rounding, `scaleDown` for
   the other).
2. **Every group member is priced in USD even when cheaper options exist.** Per ADR-0003, a
   group's value is `Σ (member balance × oracle price)` in one currency, "such as USD" -- and
   that ADR explicitly chose to convert a single-token group's lone member through its own feed,
   same as any multi-token group's members. But `PortfolioManagerPricing`'s formulas never
   reference USD or any specific currency: they only need `balanceIn` and `balanceOut` in the
   *same* unit. A plain Balancer-style weighted pool needs no oracle at all when both reserves are
   already in one unit.

## Decision

Two changes, addressing each source independently:

**A. Fetch each traded feed once per swap.** `OracleAdapter.fetchRawPrice` reads and validates a
feed's latest round once; `OracleAdapter.roundPrice` is a pure function that rounds an
already-fetched `RawPrice` either direction with no further call. `priceWad` is now just
`roundPrice(fetchRawPrice(config), rounding)` -- unchanged behavior, same checks, same errors.
`PortfolioManagerSwap` fetches each traded member's `RawPrice` once and rounds it both ways
locally instead of calling `priceWad` twice.

**B. Let a member opt out of pricing entirely as the strategy's numeraire.** A member's `feed` may
be the zero address, designating it the strategy's unit of account: its native balance already
*is* its value (scaled to WAD by its own decimals), so `OracleAdapter` never calls an external
feed for it. At most one member, across every group in the strategy, may do this -- a second
numeraire would leave the unit of account ambiguous between two different tokens.
`PortfolioManagerArgsCodec.build`/`parse` enforce the at-most-one rule; `OracleAdapter.priceWad`
returns exactly `WAD` for the sentinel.

This still requires ADR-0003's "all feeds must use the same quote currency" invariant -- a
numeraire member doesn't change what unit the *other* members' feeds must be quoted in, it just
lets one member skip the conversion because it already *is* that unit. Whether a given token pair
has direct feeds cheap enough to make a non-numeraire member's conversion itself cheaper (e.g. a
native BTC/ETH feed instead of two USD legs) is a per-deployment choice this ADR does not make --
it only removes the oracle call a numeraire member never needed.

## Alternatives considered

- **Cache feed reads in a transaction-scoped map keyed by feed address**, to dedupe any feed
  shared across members, not just the two traded ones. Rejected as more plumbing than the actual
  problem needs: a feed can currently only be shared by two members if both are the one being
  traded in and the one being traded out, which (A) already covers directly.
- **Always require a numeraire member.** Rejected: some strategies have no natural shared-unit
  token among their declared universe (e.g. a basket of unrelated tokens with only USD feeds
  available), and forcing one would mean inventing a synthetic reference asset with no real
  balance behind it. Making it optional costs nothing for strategies that don't use it.

## Consequences

- `PortfolioManagerStrategyValidatorExcessivePriceDeviation`'s pairwise check (ADR-0007) and the
  swap-side deviation step cap (ADR-0016) both operate purely on `balanceIn`/`balanceOut` ratios
  already in a common unit -- neither needed any change for (B) to work correctly, verified by
  tests exercising both guards against a numeraire-denominated pair.
- `_portfolioManagerSwapXD` and `PortfolioManagerStrategyValidator._requireBalancedWithinTolerance`
  were each split into smaller private helper functions to carry the extra `RawPrice`/override
  parameters without exceeding Solidity's stack-depth limit. This added a small, fixed per-call
  overhead (a few hundred gas) to the ship-time-only path, which doesn't benefit from (A)'s
  savings the way the swap path does -- measured and accepted as the cost of the refactor, not of
  the oracle-call reduction itself.
- A strategy's numeraire choice is immutable once shipped, same as every other encoded argument.
- `PortfolioManagerMultipleNumeraireMembers` replaces `PortfolioManagerZeroFeedAddress` --
  `feed == address(0)` is no longer categorically invalid, only a second one is.

## References

- `packages/contracts/src/utils/OracleAdapter.sol` -- `RawPrice`, `fetchRawPrice`, `roundPrice`,
  `groupValueWadWithOverride`.
- `packages/contracts/src/PortfolioManagerSwap.sol` -- `_buildQuote`, `_priceExactIn`/`_priceExactOut`.
- BLEUDEV-412 (AI Audit gas-cost finding, BLEUDEV-338).
