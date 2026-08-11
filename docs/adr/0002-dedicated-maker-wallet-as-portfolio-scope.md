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
token0, token1)` already reads real, on-chain, settled state today. The cost is operational,
not technical — B5 in bleu-brain's critique.md flags that "the LP just segregates capital"
undersells a real migration: a fresh wallet, moving capital, and re-shipping every existing
strategy from it.

## Decision

Portfolio scope = one dedicated maker wallet per LP, holding only a declared universe of
tokens. Every strategy shipped from that wallet settles into it, so the wallet's real balance,
read only over the declared universe, *is* the tracked net exposure. No changes to Aqua core.

## Consequences

- Zero-protocol-change integration is a strong pitch, but onboarding has a real cost this ADR
  doesn't remove: LP must create the wallet, fund it, and re-ship existing strategies from it.
  An onboarding guide / migration checklist is owed by M4 (bleu-brain critique.md, B5).
- The exposure reader must filter to the declared universe only — anything else that lands in
  the wallet (accidental or a deliberate donation) must be ignored by the reading, not just by
  convention. This is a spec requirement, not a documentation note (critique.md, 1.6).
- Because the wallet is real and public, it is also attackable by direct transfer — this ADR
  creates the donation-attack surface that ADR-0007 exists to bound, not to prevent outright.
- Strategies sharing one wallet can interact within the same block (two strategies each pricing
  off a balance the other is about to change) — accepted as a tested, guardrailed residual
  (critique.md, 1.7), not solved by this ADR.

## References

- bleu-brain `1inch-aqua-incubator/portfolio-manager/context.md`, decisions 3 and 4
- bleu-brain `1inch-aqua-incubator/portfolio-manager/critique.md`, issues 1.6, 1.7, B5
- `lib/aqua/src/interfaces/IAqua.sol` — `safeBalances`, `ship`, `dock`
