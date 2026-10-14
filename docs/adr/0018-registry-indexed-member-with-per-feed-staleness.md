# ADR-0018: Reference tokens and feeds by registry index, with maxStaleness set per feed

**Status:** Accepted.

## Context

An AI security audit (BLEUDEV-412) also flagged `PortfolioManagerArgsCodec.Member`'s size: 43 bytes per member (a 20-byte token address, a 20-byte feed address, and a 3-byte `maxStaleness`). `PortfolioManagerArgsCodec.MAX_MEMBERS_PER_GROUP` (5) times `MAX_GROUPS` (4) means a strategy can carry up to 20 members, and every byte of encoded member data counts against SwapVM's 255-byte instruction argument limit — large baskets were at real risk of not fitting at all.

Most of that cost is redundant: a given production deployment only ever trades a small, fixed set of tokens and feeds, so the same 20-byte address appears across many strategies' encodings. A 2-byte index into a shared list captures the same information at a fraction of the size, if something keeps the list and resolves an index back to an address when a strategy needs one.

A token address carries no safety claim beyond "this is the token being priced" — any address is a valid token to put in a basket. A feed address does: declaring a feed usable means someone vetted that it quotes the right pair, at a cadence the protocol can tolerate. These two facts called for different registries with different write access, not one shared list.

While implementing this, real Base-mainnet E2E tests (forked at a pinned block) surfaced a second, related problem: a single project-wide `maxStaleness` constant could not satisfy every feed. Stablecoin feeds (DAI/USD, USDC/USD, USDT/USD) update on a price-deviation-or-heartbeat basis and can legitimately go several hours without a new round under calm market conditions, while volatile-asset feeds (ETH/USD, BTC/USD) update far more often. A constant tight enough for the latter rejected live trades against the former.

## Decision

**Two registries, by trust model.** `PortfolioManagerTokenRegistry` is permissionless: `register(address)` is idempotent (a repeat call returns the existing index) and anyone may call it, because adding a token index carries no claim beyond "this address exists." `Member.token` becomes `Member.tokenIndex` (`uint16`); index 0 is reserved and always resolves to the zero address, so `indexOf[token] == 0` means "not registered."

`PortfolioManagerFeedRegistry` is owner-gated (`Ownable2Step`): only the owner may `register` a feed. The owner is intended to be a `TimelockController` (already vendored via OpenZeppelin), so every new feed clears a public review delay before strategies can reference it — not enforced by the registry itself, only by who holds its ownership. `Member.feed` becomes `Member.feedIndex` (`uint16`); index 0 is reserved to mean "no feed — this member is its group's own numeraire" (ADR-0017), never assigned a real feed.

**`maxStaleness` moves into the feed registry, set once per feed at registration time.** `register(address feed, uint32 maxStaleness)` stores both together; `feedAt(uint16) returns (address, uint32)` resolves both together. This is neither a per-member encoded byte (the old design, which this ADR removes to shrink `Member`) nor one fixed global constant (rejected after the real-feed E2E finding above) — it is a property of the feed itself, set with the same trust/governance model as the feed address: whoever vets a feed as fit to quote a pair also decides how stale a reading from it may be before a trade must reject. A production deployment is expected to register ETH/USD and BTC/USD at a tight bound (around 1 hour, matching their observed heartbeat) and DAI/USD, USDC/USD, and USDT/USD at a wider one (around 4 hours, matching their observed cadence) — exact values are a deployment-time choice, not a protocol constant.

`Member` is now 4 bytes (`tokenIndex` + `feedIndex`, both `uint16`), down from 43 — a 91% cut per member, and the real lever against the 255-byte argument limit the audit flagged. `PortfolioManagerArgsCodec.build`/`parse`/`decodeTrusted` stay `pure`: they decode indices for free and never touch either registry. Only `groupValueWad` and the new `flattenTokens` (used by `PortfolioManagerStrategyValidator` to compare a strategy's declared universe against what `ship()` actually received) resolve an index to an address, and only because they already need external calls (`balanceOf`, the oracle feed) to do their job — resolving the registry alongside those calls adds no new call class.

**No migration path.** The protocol has not launched; existing strategies do not need to carry forward, so this ADR replaces the encoding outright rather than versioning it.

**Stack-depth verified empirically, not assumed.** `PortfolioManagerSwap` and `PortfolioManagerStrategyValidator` hold their registries as contract-level `immutable`s, referenced directly by each contract's own private helpers, rather than threaded through as function parameters down an already-deep call chain. Earlier work in the same call chains (ADR-0016's per-trade step cap, ADR-0017's bridge lookup) repeatedly hit Solidity's "variable ... is 1 too deep in the stack" limit from passing extra parameters through nested calls; adding two more addresses as parameters risked the same failure. Holding them as immutables instead keeps every helper's own parameter list unchanged — confirmed by a clean `forge build` across `src/` and `script/` after the full rewrite, not inferred from the pattern alone.

## Alternatives considered

- **One shared registry for both tokens and feeds.** Rejected: a token index needs no vetting; a feed index does. Merging them would force permissionless writes onto feed entries, which is the property the owner-gated feed registry exists to protect.
- **Keep `maxStaleness` as a fixed global constant** (this ADR's first draft, briefly shipped to an earlier commit on this branch before the real-feed E2E finding). Rejected once Base-mainnet fork tests showed one constant could not satisfy both volatile and stablecoin feeds without either rejecting live stablecoin trades or loosening the bound for every feed, including ones where that would be unsafe.
- **Keep `maxStaleness` as a per-member encoded byte**, restoring part of the old `Member` shape instead of moving it into the feed registry. Rejected: it reopens the exact byte-budget problem this ADR exists to close, for a value (how stale a given feed may be) that is a property of the feed, not of any one member referencing it — two members pointing at the same feed index have no reason to disagree about its staleness bound.
- **Pass the registries as function parameters instead of contract-level immutables.** Rejected after confirming it reopens stack-too-deep in the same call chains ADR-0016/0017 already had to route around once; immutables avoid the parameter entirely instead of needing a further call-chain split.
- **Index `Bridge.feed` through the feed registry too**, for symmetry with `Member`. Rejected: a strategy registers at most a handful of bridges (one per pair of groups using a different unit, almost always one or two per ADR-0017), far below the per-member budget pressure that motivated compressing `Member`. `Bridge` keeps its raw `address feed` and `uint256 maxStaleness` fields unchanged.

## Consequences

- `Member` shrinks from 43 to 4 bytes; a strategy's maximum basket size is no longer at risk of exceeding SwapVM's 255-byte instruction argument limit.
- Shipping or updating a strategy now requires registering its tokens (free, permissionless) and feeds (owner-gated, intended to run through a timelock) before building its encoded arguments — `script/ShipTestStrategy.s.sol` does this as part of the same broadcast.
- A feed's `maxStaleness` is fixed at registration time. Loosening or tightening it for an already-registered feed requires the feed registry's owner to register a new entry (a new index) and point future strategies at it; already-shipped strategies keep referencing the old index and its original bound, unaffected.
- `PortfolioManagerFeedRegistry`'s owner is deployed to the deployer address at launch and must be transferred to a `TimelockController` before the registry is used in production — not yet automated by `Deploy.s.sol`, called out there as a follow-up.
- `PortfolioManagerSwap` and `PortfolioManagerStrategyValidator` each gained two constructor parameters (the two registry addresses) and two private immutables; every call site that constructs either contract (`PortfolioManagerRouter`, `PortfolioManagerOpcodes`, both deploy scripts, every test fixture) was updated accordingly.

## References

- `packages/contracts/src/utils/PortfolioManagerTokenRegistry.sol`, `packages/contracts/src/utils/PortfolioManagerFeedRegistry.sol`.
- `packages/contracts/src/utils/PortfolioManagerArgsCodec.sol` -- `Member`, `groupValueWad`, `flattenTokens`.
- `packages/contracts/src/PortfolioManagerSwap.sol` -- `TOKEN_REGISTRY`/`FEED_REGISTRY` immutables, `_feedOf`.
- `packages/contracts/src/PortfolioManagerStrategyValidator.sol` -- same immutables, `_requireUniverseMatches`.
- `packages/contracts/script/Deploy.s.sol`, `packages/contracts/script/ShipTestStrategy.s.sol`.
- BLEUDEV-412 (AI Audit gas-cost and encoding-size finding, BLEUDEV-338).
