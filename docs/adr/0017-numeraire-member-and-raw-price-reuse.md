# ADR-0017: Let each group have its own numeraire member; fetch each feed once per swap

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
   reference USD or any specific currency, and -- as this ADR's Decision section works out in
   more detail -- don't even need `balanceIn` and `balanceOut` in the *same* unit, only each in
   its *own* group's unit. A plain Balancer-style weighted pool needs no oracle at all when its
   reserves are each in their own native unit.

## Decision

Two changes, addressing each source independently:

**A. Fetch each traded feed once per swap.** `OracleAdapter.fetchRawPrice` reads and validates a
feed's latest round once; `OracleAdapter.roundPrice` is a pure function that rounds an
already-fetched `RawPrice` either direction with no further call. `priceWad` is now just
`roundPrice(fetchRawPrice(config), rounding)` -- unchanged behavior, same checks, same errors.
`PortfolioManagerSwap` fetches each traded member's `RawPrice` once and rounds it both ways
locally instead of calling `priceWad` twice.

**B. Let a member opt out of pricing entirely as its own group's numeraire.** A member's `feed`
may be the zero address, designating it that group's unit of account: its native balance already
*is* its value (scaled to WAD by its own decimals), so `OracleAdapter` never calls an external feed
for it. At most one member per group may do this -- a second numeraire in the same group would
leave that group's unit of account ambiguous between two different tokens. Different groups may
pick different numeraires, or none at all; nothing requires them to agree.
`PortfolioManagerArgsCodec.build`/`parse` enforce the at-most-one-per-group rule;
`OracleAdapter.priceWad` returns exactly `WAD` for the sentinel.

This still requires ADR-0003's "all feeds must use the same quote currency" invariant *within a
group* -- a numeraire member doesn't change what unit the *other members of its own group* must be
quoted in, it just lets one member skip the conversion because it already *is* that unit.

**Why per group, not per strategy, and why the curve math never needed reconciling across
groups.** An earlier version of this ADR required one numeraire for the *whole* strategy, reasoning
that `PortfolioManagerPricing`'s exact-in/exact-out formulas need `balanceIn`/`balanceOut` in "the
same unit." That premise was wrong. The formulas only need the traded *input* amount in `balanceIn`'s
unit -- `A_o = balanceOut * (1 - (balanceIn/(balanceIn+A_i))^(weightIn/weightOut))` returns its
result in `balanceOut`'s unit automatically, whatever that unit is. This is exactly how a plain
two-token Balancer pool prices ETH against USDC with no shared unit and no oracle at all: each side
keeps its own native unit, and the curve's output lands in the *other* side's unit as a mechanical
consequence of the formula, not because anything was converted first. A group here is the same
idea, generalized to a basket: `_groupValueWad` aggregates a group's members into one number in
*that group's own* unit (via its own numeraire, if any), and `_buildQuote`/`_priceExactIn`/
`_priceExactOut` hand that number to the curve exactly as a raw single-token balance would be
handed to a plain weighted pool. So each group may use a different numeraire with no bridging step
anywhere in the trade path.

**Where a shared unit actually matters: the deviation checks.** The swap-side step cap
(ADR-0016) only ever compares a trade's own `SP` before and after itself -- both computed in the
same units since nothing changes between them, so it needs no reconciliation and was already
confirmed unit-agnostic. The ship-time pairwise check (ADR-0007) is different: it compares the
*current* `SP` against *parity* (`WAD`), and "parity" only means "matches target weights" when
`balanceIn`/`balanceOut` are already in the same unit. With per-group numeraires, two groups being
compared may not be. **`Bridge` entries exist to fix exactly this, and only this** -- a live feed,
registered for one specific pair of groups, used solely to convert one group's value into the
other's unit before the existing parity comparison runs. Swap pricing never reads a `Bridge`; it
has no need to, per the paragraph above.

A `Bridge{groupA, groupB, feed, maxStaleness}` is keyed by group *index* pair, not by naming either
group's unit -- omit the entry entirely for a pair of groups that already share a unit (including
every strategy that uses one strategy-wide numeraire, or none at all, as before). A strategy only
needs as many `Bridge` entries as it has pairs of groups using genuinely *different* units, which
in practice is almost always one or two, not one per group pair -- an earlier draft considered a
dedicated strategy-wide "hub" unit to keep this below one feed per group pair in the worst case, but
real strategies rarely have more than two or three distinct units in play at all, so the hub added
a concept (and a required field) without a real saving. `feed` quotes groupA's unit in terms of
groupB's unit; `PortfolioManagerStrategyValidator` resolves whichever side of the stored entry
matches the pair it's checking.

Nothing on-chain can catch a feed quoting the wrong currency, for a numeraire's own group or for a
`Bridge`: `AggregatorV3Interface` (the subset this contract uses) exposes only `decimals()` and
`latestRoundData()`, no currency/description metadata to check feeds against each other. Getting
every feed's quote currency right is the strategy builder's responsibility, the same trust
assumption ADR-0003 already required for an all-USD strategy.

## Alternatives considered

- **Cache feed reads in a transaction-scoped map keyed by feed address**, to dedupe any feed
  shared across members, not just the two traded ones. Rejected as more plumbing than the actual
  problem needs: a feed can currently only be shared by two members if both are the one being
  traded in and the one being traded out, which (A) already covers directly.
- **Always require a numeraire member.** Rejected: some strategies have no natural shared-unit
  token among their declared universe (e.g. a basket of unrelated tokens with only USD feeds
  available), and forcing one would mean inventing a synthetic reference asset with no real
  balance behind it. Making it optional costs nothing for strategies that don't use it.
- **One numeraire for the whole strategy** (this ADR's original design). Rejected on
  reconsideration: it forced every non-numeraire member, in every group, onto one unit, which
  costs an extra conversion for any group whose own natural unit differs -- and the curve math
  never actually needed that constraint (see above). Per-group numeraires plus `Bridge` feeds for
  the one place a shared unit is genuinely required (the deviation check) removes the constraint
  without losing any safety.
- **A strategy-wide hub unit** that every group bridges to, instead of per-pair `Bridge` entries.
  Rejected: it scales better in the worst case (one feed per group instead of one per differing
  pair) but real strategies rarely have enough distinct units for that worst case to matter, and a
  hub requires picking and configuring a reference unit even when a direct pairwise feed already
  exists and is simpler.

## Consequences

- `PortfolioManagerStrategyValidatorExcessivePriceDeviation`'s pairwise check (ADR-0007) now
  bridge-adjusts one side of a cross-unit pair before comparing to parity, via a live `Bridge`
  feed; a pair whose groups already share a unit is unaffected. The swap-side deviation step cap
  (ADR-0016) needed no change -- confirmed unit-agnostic by construction (see above), verified by
  tests exercising both guards against numeraire-denominated pairs, including two different
  numeraires bridged together.
- `_portfolioManagerSwapXD` and `PortfolioManagerStrategyValidator._requireBalancedWithinTolerance`
  were each split into smaller private helper functions to carry the extra `RawPrice`/override/
  bridge parameters without exceeding Solidity's stack-depth limit, which recurred specifically for
  the bridge lookup even under `via_ir`: passing a decoded `Bridge[]` through the pairwise-check
  call chain kept exceeding the limit regardless of how that chain was split. The fix was routing
  the bridge-rate lookup through a real external self-call (`this.resolveBridgeAdjustedValueWad`)
  that re-parses the raw `args` calldata in its own call frame, rather than threading a decoded
  struct array through nested private functions -- a different class of fix than the private-helper
  splits BLEUDEV-403/407 relied on, needed once splitting alone stopped being enough. This adds a
  small, fixed per-call overhead to the ship-time-only path, which doesn't benefit from (A)'s
  savings the way the swap path does -- accepted as the cost of the refactor, not of the oracle-call
  reduction itself.
- A strategy's numeraire and `Bridge` choices are immutable once shipped, same as every other
  encoded argument.
- `PortfolioManagerMultipleNumeraireMembers` now carries the offending group's index and is
  checked per group instead of once across the whole strategy; `PortfolioManagerZeroFeedAddress`
  stays removed -- `feed == address(0)` is only invalid as a second numeraire *within the same
  group*.

## References

- `packages/contracts/src/utils/OracleAdapter.sol` -- `RawPrice`, `fetchRawPrice`, `roundPrice`,
  `groupValueWadWithOverride`.
- `packages/contracts/src/PortfolioManagerSwap.sol` -- `_buildQuote`, `_priceExactIn`/`_priceExactOut`.
- `packages/contracts/src/utils/PortfolioManagerArgsCodec.sol` -- `Bridge`, per-group numeraire
  validation.
- `packages/contracts/src/PortfolioManagerStrategyValidator.sol` --
  `resolveBridgeAdjustedValueWad`, `_requireEveryPairWithinTolerance`.
- BLEUDEV-412 (AI Audit gas-cost finding, BLEUDEV-338).
