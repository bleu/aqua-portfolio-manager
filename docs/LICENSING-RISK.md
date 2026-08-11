# Licensing risk — read before assuming this project is "MIT, open source"

Found 2026-08-11 while scaffolding this repo, reading the actual license file shipped in
`lib/aqua/LICENSES/Aqua-Source-1.1.txt` (not previously documented in the grant proposal's
`context.md` / `application.md` / `critique.md` in bleu-brain). Not yet reviewed by counsel.
Flagging clearly here rather than quietly defaulting this repo's `LICENSE` to MIT.

## The core fact

Aqua and swapVM are **not** permissively licensed. Both ship under a custom Degensoft Ltd
license (`Aqua-Source-1.1`, `SwapVM-1.1` — same family, same terms). Full text in
[`LICENSES/`](../LICENSES/).

## Two separate obligations, not one

### 1. Copyleft on our own code (unconditional — applies even with zero revenue)

§3.1 of Aqua-Source-1.1: if you "Modify" the Licensed Work, you must publish your own
resulting source under *the same license*, with attribution, marked changes, and reproducible
build instructions. §1.7 defines "Modification" broadly: "any change to, or work based on or
incorporating, the Licensed Work, including static/dynamic linking... instruction sets
executing in the same virtual machine/address space, or artifacts shipped/deployed together
as one product."

Our strategy contract inherits `abstract contract AquaApp` — that's compiled into our
bytecode, not an external call to a separately deployed instance. That's about as clear a
case of "based on or incorporating" as exists; §3.3's carve-out ("independent code that
simply calls, interfaces with, or is distributed alongside the Licensed Work") is written for
callers, not for something that inherits the base contract.

**Practical consequence: this repo's own contracts should ship under
`LicenseRef-Degensoft-Aqua-Source-1.1`, not MIT.** That's why `LICENSE` at the repo root is
the Aqua license text, not an MIT template. This isn't necessarily bad news — Milestones 2-4
already plan to open-source everything anyway — but the grant's public-facing language
("MIT, open source") is imprecise about *which* license, and should say Aqua-Source-1.1
specifically once this is confirmed, not "MIT."

### 2. Commercial-use trigger (conditional on scale — currently under a revocable waiver)

§5.2 requires a paid Commercial License from Degensoft (confidential, negotiated terms) once
either:
- Charged Fees exceed **US$100,000** in any rolling 12 months, or
- "Liquidity Under Control" (LUC) exceeds **US$10,000,000** at any time.

The application's own base-case projection (see bleu-brain `application.md`, Post-Launch
Targets) assumes **$30M under management** six months after mainnet — three times the LUC
trigger, on the base case, not the upside scenario.

§5.3 currently waives enforcement for "Volume Activities" (routing, arbitrage,
market-making — including charging fees, including with third-party capital), which is
plausibly what this strategy is. **But the waiver is explicitly not a license, creates no
reliance rights, and is revocable by Degensoft at any time in its sole discretion** — 10 days
to comply or stop, after notice. This is the actual business risk: the project's entire
"no commercial license needed" framing rests on an informal, revocable accommodation from a
specific counterparty (Degensoft), not on the license's own permanent terms.

## What this changes, concretely

1. **`LICENSE`** in this repo is Aqua-Source-1.1, not MIT (done, see root).
2. **The grant application's "MIT" language should be corrected** to name the actual
   license, in bleu-brain — not done yet, flagging here for whoever owns that doc next.
3. **A new risk item belongs in `critique.md`'s register** (bleu-brain
   `1inch-aqua-incubator/portfolio-manager/critique.md`): the revocable §5.3 waiver, alongside
   a decision on whether to budget for a possible Degensoft Commercial License negotiation if
   the base-case $30M LUC projection is taken seriously. Not added there yet — this file is
   where the finding lives until someone decides where it belongs in the shared doc.
4. **Worth a direct question to Tanner** (the 1inch contact who already confirmed the
   weighted-math scope question) given the base case crosses the LUC trigger by design, not
   as an edge case.

Not a blocker to writing code or continuing Milestone 1 design work — just something the
person running this project should know before repeating "MIT, open source" in any external
communication.
