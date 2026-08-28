# ADR-0011: Require a Safe maker wallet with a Basket Scope Guard, instead of bounding cross-strategy risk

**Status:** Accepted

## Context

`ADR-0002`'s exposure reader uses real `balanceOf(maker)`, which is shared across
every strategy the LP runs from that wallet. `ADR-0003` already assumed a boundary exists —
*"the pricing curve reacts to group-weight impact, not individual-token impact. Intra-group
drift is allowed by design"* — but nothing enforced that boundary. Any other strategy sharing
the wallet could move tokens between groups (or in from outside the declared universe), and
PM's curve would price the result as if it were legitimate. `thoughts/cross-strategy-manipulation.md`
worked this out in full with a concrete numeric exploit.

Two families of fix were explored and rejected before this one — see Alternatives Considered
below for both.

The team's direction (2026-08-20): **don't bound the risk — remove the capability.** No strategy
other than PM's own should be able to cross a group boundary or touch a token outside the
declared universe. If that's enforceable, the cross-strategy problem doesn't need a mathematical
bound at all — it needs to not exist.

## Decision

The maker wallet must be a Safe, with a **Basket Scope Guard** installed (`ITransactionGuard`,
and `IModuleGuard` on Safe ≥1.5.0) that inspects every outgoing `AQUA.ship(app, strategy, tokens,
amounts)` call: if `keccak256(strategy)` matches the exact, known strategy hash of this LP's PM
instance — computed off-chain, before deployment, from PM's already-parameterized strategy
bytes — it's allowed unconditionally (PM is the trusted mechanism that's supposed to span
groups). For any other strategy, every token in `tokens` must belong to the same declared group,
and every token must belong to *some* declared group — the Guard reverts otherwise.

**Trust is anchored to the specific strategy hash, not to the router address (`app`).** A
swapVM router is a general-purpose opcode dispatcher — the same router address can run PM's
strategy *and* any other strategy built from the same opcode set, each with its own
`strategyHash`. Checking `app` alone would trust every strategy that happens to share PM's
router, not just PM itself. This isn't a hypothetical distinction: `Aqua.pull(maker,
strategyHash, token, amount, to)` looks up `_balances[maker][msg.sender][strategyHash][token]` —
keyed by `msg.sender`, i.e. by router address, not by strategy. Any strategy shipped through the
same router can call `pull()` as that same `msg.sender`; only `strategyHash` distinguishes one
strategy's authorized balance from another's sharing the same router. The group-membership
mapping and the trusted strategy hash are both fixed at the Guard's construction, with no
setter, so neither can be loosened later by whoever controls the Safe.

This makes the assumption ADR-0003 and ADR-0007 already relied on ("only PM, or a pure
donation, can move what PM prices") structurally true, rather than hoped-for. See
`thoughts/basket-scope-guard-design.md` for the contract sketch and installation details.

## Alternatives considered

- **An oracle-informed reward mechanism** (virtual weight anchored to a live oracle price, plus
  a rebalancing reward capped at a provably-real surplus) — mathematically sound, but leans on a
  live oracle for a safety-critical property, which the LVR literature (Milionis et al.) warns
  against. Left as a documented, superseded exploration rather than deleted — the reasoning and
  precedent research may be useful again if a future design needs to bound rather than eliminate
  a risk.
- **A set of layered guardrails** modeled on Balancer's own Managed Pool circuit breaker, an
  oracle-informed reward, and a time-decay surcharge modeled on mutual-fund redemption fees
  (`thoughts/cross-strategy-layered-defense.md`) — each layer individually well-precedented, but
  the team decided against carrying three separate mechanisms, each with its own parameters and
  failure modes, when the underlying problem might be closable structurally instead. Same
  reasoning for keeping it documented rather than deleting it.
- **EOA maker wallet:** ruled out outright — an EOA has no code, so there is nowhere to attach
  any check. Nothing in the grant proposal requires EOA support; `ADR-0002`'s original "EOA or
  Safe" wording was our own choice, not a constraint, and is narrowed here.
- **Restrict the wallet to PM only (no other strategies at all):** the simplest, most-precedented
  option (direct analog: SEC Rule 15c3-3's customer-asset segregation) and still available to an
  LP who wants it, but it gives up ADR-0002's stated value (visibility across the LP's *other*
  strategies) entirely. The Guard is strictly more permissive: other strategies are welcome, as
  long as they stay within one group.

## Consequences

- **Onboarding gets stricter.** An LP must use a Safe, install the Guard before shipping
  anything from it, and — if the wallet ever had prior activity — pass a one-time, off-chain
  check (scanning `Shipped` events for that address) confirming no pre-existing strategy already
  violates the group boundary. The Guard has no way to see or undo the past; it only governs
  transactions that pass through it after installation.
- **Module coverage is a versioned gap.** Safe's `IModuleGuard` (the mechanism covering
  module-executed transactions, as opposed to the normal multisig path) only exists from v1.5.0,
  and a real integration bug in that exact mechanism was found in a Code4rena audit. Until that
  matures, the safer default is: **no module capable of an arbitrary call may be installed on a
  Safe used for this**, regardless of Safe version — checked at onboarding, not enforceable by
  the Guard itself (a bypass via module happens outside the Guard's own execution path by
  construction).
- **The Guard can be removed.** `setGuard`/`setModuleGuard` are ordinary Safe transactions,
  subject to the wallet's existing signature threshold — this raises the bar to a visible,
  on-chain, threshold-gated action, not a cryptographic guarantee against a colluding majority of
  owners.
- **PM's specific strategy hash is now a versioned trust anchor — not its router address.** A
  swapVM router is a general opcode dispatcher; the same router can run PM's strategy and any
  other strategy built from the same opcodes, each with a distinct `strategyHash`. The Guard
  allowlists the exact hash of this LP's already-parameterized PM strategy (computed off-chain
  before the Guard is deployed), not the router's identity. Consequence: every time an LP's PM
  weights/groups are reconfigured (a new `ship()`, per ADR-0003's already-accepted cost) or PM
  itself is redeployed, the Guard's trusted hash goes stale and a new Guard must be deployed and
  installed — this isn't fixable post-construction by design (no setter, on purpose). Migration
  cost worth flagging for Milestone 4, symmetric to the immutability cost `ADR-0010`
  already accepted for `ship()`.
- Closes the residual `ADR-0002` flagged as open ("strategies sharing one wallet can
  change the balance PM prices against") for the cross-group case specifically. Intra-group
  drift by other strategies remains possible and remains accepted — that was ADR-0003's decision
  from the start, not a new gap this ADR introduces.

## References

- `thoughts/basket-scope-guard-design.md` — the Guard's contract sketch and installation steps
- `thoughts/cross-strategy-manipulation.md`, `thoughts/cross-strategy-layered-defense.md` —
  superseded prior approaches, kept for their research and reasoning
- `docs/adr/0002-dedicated-maker-wallet-as-portfolio-scope.md` — the Safe-only requirement this
  ADR depends on
- `docs/adr/0003-oracle-valued-token-groups.md` — the group-boundary assumption this Guard
  enforces
- `docs/adr/0007-donation-resistance-via-curve-invariant.md` — the proof whose "only PM or a
  donation" precondition this ADR makes true
- `lib/aqua/src/Aqua.sol:63-70` — `pull()`'s `msg.sender`-keyed ledger lookup, the concrete
  mechanism behind "trust the strategy hash, not the router address" above
- Safe (`safe-smart-account`) `contracts/base/GuardManager.sol`, `CHANGELOG.md` (`IModuleGuard`
  introduced in v1.5.0)
- Zodiac (Gnosis Guild) `zodiac-guard-scope` and Roles Modifier — real, audited precedent for a
  function/parameter-scoping Safe Guard
