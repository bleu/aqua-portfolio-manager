# ADR-0010: Deploy an independent SwapVM router

**Status:** Accepted.

## Context

PM needs a weighted curve and access to multiple token balances.
A SwapVM instruction can read external balances and hold persistent state.
However, its opcode must exist in the deployed router's fixed opcode table.
A maker's program can sequence existing opcodes but cannot add one.

## Decision

Deploy an independent router that inherits SwapVM and registers the PM instruction.
The multi-token prototype established that an instruction can read balances beyond the two traded tokens.
The decision favored independent deployment and preceded a full comparison of deployment forms by gas cost.

## Alternatives considered

| Option | Reason not selected |
|---|---|
| Custom `AquaApp` | Requires bespoke entrypoints and settlement integration instead of the SwapVM order interface. |
| Add PM to 1inch's router | Requires 1inch to merge and redeploy the opcode table. Remains a possible future path. |
| Hybrid `AquaApp` and deployed SwapVM | Instruction functions are internal. External `quote()` and `swap()` require full orders and settlement semantics. |
| Off-chain keeper/controller | Can ship, dock, or trade but does not supply the grant's intended on-chain pricing mechanism. |

Aqua's `app` is a ledger address, not a requirement to inherit `AquaApp`.
Our router is an Aqua app through its settlement calls.

## Consequences

- Our deployed audit surface includes SwapVM's signatures, taker traits, callbacks, token handling, and reentrancy lock.
- The router uses SwapVM's per-order lock rather than `AquaApp`'s modifier.
- Deploying independently does not ensure Pathfinder discovery.
- **Integration record, 2026-09-09:** 1inch confirmed that it must manually include the router. Inclusion depends on a frozen mainnet router address.
- That review recorded no self-hosted or fork-testable equivalent of closed-source Pathfinder. Routing validation requires 1inch coordination.
- A future shared-router integration requires explicit coordination with 1inch.
- The license obligations in [ADR-0001](0001-license-under-aqua-source-not-mit.md) also apply to this design.

## References

- [PM router](../../packages/contracts/src/PortfolioManagerRouter.sol) and [opcode table](../../packages/contracts/src/PortfolioManagerOpcodes.sol).
- [SwapVM](../../packages/contracts/lib/swap-vm/src/SwapVM.sol) and its [Aqua opcode table](../../packages/contracts/lib/swap-vm/src/opcodes/AquaOpcodes.sol).
- [Multi-token prototype](../../packages/contracts/src/BasketXYCSwap.sol).
