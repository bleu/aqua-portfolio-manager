# ADR-0010: On-chain form — AquaApp, a swapVM instruction, or a hybrid

**Status:** Proposed — this is a named Milestone 1 deliverable, not yet decided

## Context

The strategy needs multi-token portfolio state (groups, targets, smoothing state) and
cross-group pricing logic. Three shapes were named as candidates:

- **A pure `AquaApp`** — holds all portfolio state and policy itself, calling into Aqua for
  balance reads and pull/push. Leans toward this option today because it naturally holds
  multi-token state and cross-group logic, which a single swapVM instruction (designed around
  per-swap pricing, not persistent multi-asset policy) doesn't fit as directly.
- **A new swapVM instruction** — per-swap pricing logic only; would need portfolio state to
  live somewhere else it can read from.
- **A hybrid** — `AquaApp` holds portfolio state/policy, a swapVM instruction handles per-swap
  pricing math.

A **keeper/controller** design (an off-chain-triggered contract that ships/docks/trades) was
already rejected: strategies are immutable once shipped, so a controller can only
ship/dock/trade — it has no on-chain IP of its own and is a materially weaker technical
contribution for the grant's evaluation.

Everything else in this ADR log — the maker-wallet scope (ADR-0002), the group model
(ADR-0003), the pricing curve (ADR-0004), the oracle (ADR-0005), smoothing (ADR-0006), and the
invariant proof (ADR-0007) — is written assuming the `AquaApp` path, per
[`../ARCHITECTURE.md`](../ARCHITECTURE.md)'s explicit note that this is the current working
assumption, not a closed decision.

## Decision

Not yet made. This is Milestone 1's named research deliverable: a bounded design-space search
(not open-ended discovery — the candidate knobs are already named: EMA window, tolerance band,
rate caps, TWAP-of-rebalancing, discount/surcharge curve shape, and this AquaApp-vs-instruction-
vs-hybrid fork) evaluated against pre-declared criteria — the tracking-error/cost frontier from
simulation, gas per rebalance, scope-fit, and donation-attack resistance (ADR-0007). Deliverable
is a simulation notebook plus an architecture-decision writeup that picks the mechanism and
justifies the form with numbers.

## Consequences

- Every ADR in this log written against the `AquaApp` assumption may need a follow-up ADR (or an
  amendment noted here) once M1 concludes, if the chosen form is the swapVM-instruction or
  hybrid path instead.
- `lib/swap-vm` is vendored to keep the swapVM-instruction and hybrid paths live options, not
  dead weight — see `foundry.toml`'s `swap-vm/` remapping.
- This ADR should flip to **Accepted** (or split into a superseding ADR) once M1's writeup picks
  a form — until then, treat the architecture doc's L2 component diagram as illustrative of the
  AquaApp case, not as a settled contract boundary.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — explicit "working assumption, not a closed
  decision" note
- `lib/aqua/src/AquaApp.sol`, `lib/swap-vm/src/` — the two base paths
