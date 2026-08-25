# ADR-0002: Scope the portfolio to a dedicated maker wallet, with zero Aqua protocol changes

**Status:** Accepted

## Context

Aqua's shared virtual-balance model (`balances[maker][app][strategyHash][token]`) is exactly
what makes Aqua capital-efficient, but it also means an LP's *net* exposure across strategies
is an emergent sum nothing tracks. Two, not three, candidate sources of truth actually exist —
an earlier draft of this ADR named a third ("read `AQUA.safeBalances()` for settled state"),
but that was a misreading of the interface, corrected here (2026-08-18):

- **Raw `balanceOf(maker)`** (standard ERC20, no Aqua call involved) — real, and shared
  across every strategy the LP runs from that wallet, but polluted by unrelated holdings
  and manipulable (anyone can transfer tokens into an address to skew a reading — see
  ADR-0007).
- **Aqua's own per-strategy ledger** (`rawBalances(maker, app, strategyHash, token)` and
  `safeBalances(maker, app, strategyHash, token0, token1)`) — these are **the same underlying
  storage**, `_balances[maker][app][strategyHash][token]` (`lib/aqua/src/Aqua.sol:21-38`).
  `safeBalances` only adds a check that the token belongs to an active, non-docked strategy —
  "safe" means *validated*, not *settled* or *real*. Both are scoped to one
  `(maker, app, strategyHash)` triple, populated once at `ship()` (no balance check against
  real holdings at that point — `Aqua.sol:40-52`) and only ever moved by that same triple's own
  `pull`/`push` calls. A different strategy's trades — even from the very same maker wallet —
  never touch this ledger. This is exactly the over-allocation problem described below, just
  under a name (`safeBalances`) that sounds more authoritative than it is.

There is no function anywhere in `IAqua` that reads a wallet-wide, cross-strategy-visible,
settled balance. The only thing that *is* wallet-wide and shared is plain
`balanceOf(maker)` — Aqua never takes custody of the maker's tokens (`ship`/`pull`/`push` only
adjust an allowance-style ledger and move tokens at settlement time, `Aqua.sol:63-80`); the real
tokens sit in the maker's own wallet the entire time. So "settled balance of a wallet the LP
dedicates to this purpose, over a declared token universe" was never a third source distinct
from `balanceOf` — it **is** `balanceOf`, scoped to a dedicated wallet and a declared universe,
specifically to make the first option's pollution problem tractable. The cost is operational,
not technical — "the LP just segregates capital" undersells a real migration: a fresh wallet,
moving capital, and re-shipping every existing strategy from it.

This trades integration smoothness for signal quality: an LP already running strategies from
an existing wallet can't adopt this without migrating first, which is onboarding friction
weighed against the alternative of a reading that's either polluted (raw `balanceOf`) or
doesn't reflect the LP's actual settled position (Aqua's own virtual balances).

## Decision

Portfolio scope = one dedicated maker wallet per LP, holding only a declared universe of
tokens. The exposure reader calls plain `balanceOf(maker)` on each in-universe token — not
`AQUA.rawBalances`/`safeBalances` — since that's the only reading that's real and
shared across every strategy shipped from that wallet. No changes to Aqua core.

Aqua's own per-strategy ledger is still used, separately, for what it's actually for:
authorizing how much a given `(app, strategyHash)` may `pull()` from the maker. Pricing and
authorization are two different questions read from two different places.

**Revised 2026-08-20: the maker wallet must be a Safe, not an EOA.** An EOA has no code, so
there's nowhere to enforce anything about what gets shipped from it. A Safe does — see
`ADR-0011` for the mechanism (a Transaction Guard) this now depends on. This narrows
ADR-0002's original "EOA or Safe" language.

## Consequences

- Zero-protocol-change integration is a strong pitch, but onboarding has a real cost this ADR
  doesn't remove: LP must create the wallet, fund it, and re-ship existing strategies from it.
  An onboarding guide / migration checklist is owed by Milestone 4.
- The exposure reader must filter to the declared universe only — anything else that lands in
  the wallet (accidental or a deliberate donation) is ignored by the reading. This is a spec
  requirement, not a documentation note.
- Because the wallet is real and public, it is also attackable by direct transfer — this ADR
  creates the donation-attack surface that ADR-0007 exists to bound, not to prevent outright.
- Reading `balanceOf` for price and Aqua's ledger for pull authorization are two independently
  moving numbers. PM's own `ship()`-registered allowance must stay wide enough that a real-price
  quote it just gave is pullable — a spec/implementation detail owed before M2, not
  solved by this ADR.
- Strategies sharing one wallet can change the balance PM prices against, at any time,
  not just same-block — this is exactly the surface `thoughts/cross-strategy-manipulation.md`
  first worked through. That risk is now closed structurally, not bounded: `ADR-0011` requires
  the wallet to be a Safe with a Guard that forbids any strategy but PM's own from ever crossing
  a group boundary (ADR-0003) or touching a token outside the declared universe. What remains
  (drift *within* one group) was already accepted by ADR-0003 as safe by design.

## References

- `lib/aqua/src/Aqua.sol:21-38` — confirms `rawBalances`/`safeBalances` are the same per-strategy
  ledger, not a settled/real reading
- `lib/aqua/src/interfaces/IAqua.sol` — `ship`, `dock`, `pull`, `push`
- `ADR-0011` — the Safe Guard mechanism this ADR's Safe-only requirement exists for
- `../../thoughts/cross-strategy-manipulation.md`, `../../thoughts/cross-strategy-layered-defense.md`
  — earlier approaches to the same question (bounding the risk with an oracle-informed reward,
  then a set of layered guardrails), both superseded by `ADR-0011`'s structural approach
- `../../thoughts/basket-scope-guard-design.md` — the technical design for the Guard itself
