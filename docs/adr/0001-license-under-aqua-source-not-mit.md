# ADR-0001: License this repo's own code under Aqua-Source-1.1, not MIT

**Status:** Accepted — revised 2026-08-25 to reflect ADR-0010's on-chain form (a swapVM
instruction on our own router, not `AquaApp`)

## Context

`1inch/aqua` and `1inch/swap-vm` ship under a custom Degensoft Ltd license
(`Aqua-Source-1.1` / `SwapVM-1.1`). Its §3 "Modification" clause is defined broadly enough to
cover inheritance and static linking, and our strategy ships as a swapVM instruction on our
own router, which inherits `SwapVM` directly ([ADR-0010](0010-on-chain-form-aquaapp-vs-swapvm-instruction.md))
— compiled directly into our bytecode, not called as a separate deployed instance. That reads
as "based on or incorporating" the licensed work, not the "independent code that merely
calls/interfaces with it" carve-out in §3.3.

Defaulting to MIT, as `forge init` does, would misstate which license governs this code — and
the grant proposal's own "MIT, open source" language, written before this license was found,
repeats that mistake externally.

Separately, §5 creates a Commercial License trigger if usage crosses either of two thresholds:
**Charged Fees** (protocol fees collected) above $100k over any 12-month period, or **Liquidity
Under Control** (LUC — total value routed through strategies built on this license) above $10M.
Both are currently covered by a revocable §5.3 enforcement waiver — see
[`../LICENSING-RISK.md`](../LICENSING-RISK.md). That's a business-risk question, not part of
this ADR's decision.

## Decision

This repo's root `LICENSE` is the full text of `Aqua-Source-1.1`, and
[`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md) documents why, per dependency.

## Consequences

- Any code in `src/` is subject to Aqua-Source-1.1's copyleft: publishing it must carry attribution, marked changes, and reproducible build instructions.
- `lib/balancer-v3-monorepo` stays reference-only (GPL-3.0, separately incompatible with shipping proprietary code) — never imported from `src/`, per [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md).
- Doesn't resolve the §5 commercial-trigger business risk — that's a decision for whoever owns the grant relationship, tracked in [`../LICENSING-RISK.md`](../LICENSING-RISK.md).

## References

- [`../LICENSING-RISK.md`](../LICENSING-RISK.md) — full finding
- [`../../THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md) — per-dependency license table
- `lib/aqua/LICENSES/Aqua-Source-1.1.txt` (vendored copy)
- [ADR-0010](0010-on-chain-form-aquaapp-vs-swapvm-instruction.md) — resolved the on-chain form
  referenced here (`SwapVM`, not `AquaApp`)
