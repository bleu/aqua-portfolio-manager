# ADR-0002: Scope the portfolio to a dedicated maker wallet, with zero Aqua protocol changes

**Status:** Accepted

## Context

Aqua's shared virtual-balance model (`balances[maker][app][strategyHash][token]`) is exactly
what makes Aqua capital-efficient, but it also means an LP's *net* exposure across strategies
is an emergent sum nothing tracks. Three candidate sources of truth were considered:

- **Raw `balanceOf(maker)`** — polluted by unrelated holdings, and manipulable (anyone can
  transfer tokens into an address to skew a reading — see ADR-0007).
- **Aqua's own virtual balances** — over-allocatable across strategies; doesn't equal the
  settled net a maker actually holds, which is the problem being solved.
- **Settled balance of a wallet the LP dedicates to this purpose, over a declared token
  universe** — the LP creates a fresh maker address (EOA or Safe), funds it only with
  in-scope tokens, and ships every strategy meant to be tracked from that address.

The third option requires no protocol changes: `AQUA.safeBalances(maker, app, strategyHash,
token0, token1)` already reads on-chain, settled state today. The cost is operational,
not technical — "the LP just segregates capital" undersells a real migration: a fresh wallet,
moving capital, and re-shipping every existing strategy from it.

This trades integration smoothness for signal quality: an LP already running strategies from
an existing wallet can't adopt this without migrating first, which is real onboarding friction
weighed against the alternative of a reading that's either polluted (raw `balanceOf`) or
doesn't reflect the LP's actual settled position (Aqua's own virtual balances).

## Decision

Portfolio scope = one dedicated maker wallet per LP, holding only a declared universe of
tokens. Every strategy shipped from that wallet settles into it, so the wallet's real balance,
read only over the declared universe, *is* the tracked net exposure. No changes to Aqua core.

## Consequences

- Zero-protocol-change integration is a strong pitch, but onboarding has a real cost this ADR
  doesn't remove: LP must create the wallet, fund it, and re-ship existing strategies from it.
  An onboarding guide / migration checklist is owed by Milestone 4.
- The exposure reader must filter to the declared universe only — anything else that lands in
  the wallet (accidental or a deliberate donation) is ignored by the reading. This is a spec
  requirement, not a documentation note.
- Because the wallet is real and public, it is also attackable by direct transfer — this ADR
  creates the donation-attack surface that ADR-0007 exists to bound, not to prevent outright.
- Strategies sharing one wallet can interact within the same block (two strategies each pricing
  off a balance the other is about to change) — accepted as a tested, guardrailed residual, not
  solved by this ADR.

## References

- `lib/aqua/src/interfaces/IAqua.sol` — `safeBalances`, `ship`, `dock`
