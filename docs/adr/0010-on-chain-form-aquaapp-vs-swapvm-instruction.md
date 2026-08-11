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

### What the vendored `lib/swap-vm` source actually shows

Read directly rather than assumed, three facts change how the three options compare:

1. **A new opcode isn't a strategy author's to add.** `AquaOpcodes._opcodes()`
   (`lib/swap-vm/src/opcodes/AquaOpcodes.sol`) returns a fixed-size array of internal function
   pointers, indexed by opcode byte and hardcoded into whichever contract inherits it — today
   that's `AquaSwapVMRouter`, shipping 1inch's own instruction set (`XYCSwap`, `XYCConcentrate`,
   `Decay`, `Fee`, `PeggedSwap`, `Extruction`; no weighted/constant-mean curve). A maker's
   `order.data` only *sequences* opcodes already in that table — it can't introduce a new one.
   Getting a new opcode into the deployed router means 1inch merging and redeploying it, which
   is outside this project's control. The alternative — deploying a competing router that
   inherits `SwapVM` with our own opcode set — is possible (`AquaSwapVMRouter` is only ~30
   lines gluing `SwapVM` to an opcode list) but pulls in all of `SwapVM.sol`'s taker-facing
   plumbing (EIP-712 order signing, taker-traits parsing, WETH unwrap, maker hooks/callbacks —
   ~300 lines) as part of our own audited surface, almost none of which a single-strategy
   portfolio manager needs.
2. **Instructions can hold persistent storage — this isn't stateless by design.**
   `Invalidators.sol` is a plain contract with real `mapping`s keyed by maker/orderHash/token,
   written to conditionally on `!ctx.vm.isStaticContext` (so `quote()` never mutates state).
   `XYCSwap._xycSwapXD` happens to be `pure`, but that's a property of that one instruction, not
   a framework constraint — an instruction contract can carry exactly the kind of persistent
   EMA/smoothing state [ADR-0006](0006-exposure-smoothing.md) needs. This removes a presumed
   blocker on the swapVM-instruction path, but doesn't touch the router-deployment problem in
   (1).
3. **The "hybrid" is narrower than it sounds.** `SwapVM.swap()`/`quote()` are full external
   entrypoints built around taker-initiated calls with their own order/signature/transfer
   semantics — an external `AquaApp` can't cheaply call into the deployed router just for
   pricing math. The instruction functions themselves (e.g. `_xycSwapXD`) are `internal`,
   reachable only by directly inheriting the instruction contract. That collapses "hybrid" into
   "`AquaApp` that optionally inherits a swap-vm instruction contract for its pure math" — which
   buys nothing today, since swap-vm ships no weighted curve to inherit in the first place
   (ADR-0004's curve has to be written from scratch either way).

## Decision

Not yet made. This is Milestone 1's named research deliverable: a bounded design-space search
(not open-ended discovery — the candidate knobs are already named: EMA window, tolerance band,
rate caps, TWAP-of-rebalancing, discount/surcharge curve shape, and this AquaApp-vs-instruction-
vs-hybrid fork) evaluated against pre-declared criteria — the tracking-error/cost frontier from
simulation, gas per rebalance, scope-fit, and donation-attack resistance (ADR-0007), **plus one
criterion added by the findings above: does this option depend on 1inch redeploying shared
infrastructure we don't control, or is it deployable unilaterally?** `AquaApp` scores cleanly
on that added criterion; the instruction and hybrid paths don't. That's a real point in
`AquaApp`'s favor, but not on its own a substitute for the simulation's gas/frontier numbers —
it doesn't close this ADR by itself. Deliverable is a simulation notebook plus an
architecture-decision writeup that picks the mechanism and justifies the form with numbers.

## Consequences

- Every ADR in this log written against the `AquaApp` assumption may need a follow-up ADR (or an
  amendment noted here) once M1 concludes, if the chosen form is the swapVM-instruction or
  hybrid path instead.
- `lib/swap-vm` is vendored to keep the swapVM-instruction and hybrid paths live options, not
  dead weight — see `foundry.toml`'s `swap-vm/` remapping.
- If M1 leans toward the instruction or hybrid path despite the unilateral-deployability gap,
  the writeup needs to name who owns getting the opcode into 1inch's router (a PR to
  `1inch/swap-vm`? a direct ask via the Tanner relationship?) as an explicit, tracked
  dependency — not something to discover after M2 is already underway.
- This ADR should flip to **Accepted** (or split into a superseding ADR) once M1's writeup picks
  a form — until then, treat the architecture doc's L2 component diagram as illustrative of the
  AquaApp case, not as a settled contract boundary.

## References

- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — explicit "working assumption, not a closed
  decision" note, and the "Key technical decisions" summary
- `lib/aqua/src/AquaApp.sol` — the entire `AquaApp` base (69 lines: reentrancy lock +
  taker-push verification, nothing else)
- `lib/swap-vm/src/opcodes/AquaOpcodes.sol` — the fixed opcode table
- `lib/swap-vm/src/routers/AquaSwapVMRouter.sol`, `lib/swap-vm/src/SwapVM.sol` — the router a
  new instruction would have to live in
- `lib/swap-vm/src/instructions/Invalidators.sol` — proof instructions can hold persistent,
  non-static-context-gated storage
- `lib/swap-vm/src/instructions/XYCSwap.sol` — proof the existing curve instructions are `pure`
  by choice, not by framework constraint
