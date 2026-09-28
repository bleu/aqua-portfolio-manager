# ADR-0015: Ship both a gated and an ungated PM strategy builder

**Status:** Accepted.

## Context

1inch's Aqua access-control model requires every strategy to carry a `tx.origin`-based credential check before Pathfinder routes trades to it: "Assembler attaches `withTxOriginAccessToken(aquaKycToken)` to every strategy" ([1inch's Aqua docs](https://business.1inch.com/portal/documentation/aqua/liquidity-layer/access-resolvers-and-pathfinder)). Makers stay open by design; the check gates the taker/resolver role.

The real per-chain resolver credential contract address is not confirmed yet. Mainnet-test strategies still need to ship, and Aqua strategies are immutable once shipped, so a strategy built without the gate today cannot gain one later without re-shipping under a new strategy hash.

## Decision

One router, two program builders.

`PortfolioManagerOpcodes` wires `Controls._onlyTxOriginTokenBalanceNonZero` in as opcode 1, alongside the existing curve-swap opcode 0. The credential token address lives in the gate instruction's own program bytes, not a router-level constant, so whether a given strategy's program includes the gate is a per-strategy choice, not a per-router one.

`PortfolioManagerProgramBuilder` stays unchanged: it never references opcode 1, so its programs stay ungated. Use it for strategies that need to ship before a confirmed credential exists.

`GatedPortfolioManagerProgramBuilder` appends the gate instruction after the curve instruction, calling `PortfolioManagerProgramBuilder.build()` for the curve prefix so the two builders can never encode that part differently. The gate comes after the curve instruction, not before: `PortfolioManagerStrategyValidator._args()` requires `program[0] == CURVE_OPCODE` for every PM strategy. This does not weaken the gate -- `runLoop` executes both instructions in the same call, so a failing gate still reverts the whole transaction, including whatever the curve instruction already did.

## Alternatives considered

- **Two router contracts**, mirroring swap-vm's own `AquaSwapVMRouter`/`AquaSwapVMRouterDebug` split: a real, precedented option, but more to deploy and verify for the same outcome. Not chosen because the gate is documented as a per-strategy attachment, not a per-router one -- a second builder matches that model directly.
- **Prepend the gate before the curve instruction**: rejected. `PortfolioManagerStrategyValidator._args()`'s `program[0] == CURVE_OPCODE` requirement would reject every gated strategy's attestation.
- `Controls._onlyTakerTokenBalanceNonZero` **(checks `msg.sender`) instead of the `tx.origin` variant**: rejected. 1inch's docs specify the `tx.origin` variant; `msg.sender` would check the wrong address whenever a contract sits between the resolver EOA and the router.

## Consequences

- A strategy shipped with `PortfolioManagerProgramBuilder` before a confirmed credential exists stays ungated permanently -- adding the gate later means re-shipping under a new strategy hash, not a config change.
- Both builders share the curve-instruction encoding through delegation, so a change to `PortfolioManagerArgsCodec` or the curve wire format cannot silently diverge between gated and ungated strategies.
- The credential token address is not yet confirmed for any chain. `GatedPortfolioManagerProgramBuilder` is tested against a mock token until it is.

See [`Controls.sol`](../../lib/swap-vm/src/instructions/Controls.sol), [`PortfolioManagerOpcodes.sol`](../../packages/contracts/src/PortfolioManagerOpcodes.sol), [`GatedPortfolioManagerProgramBuilder.sol`](../../packages/contracts/src/utils/GatedPortfolioManagerProgramBuilder.sol), and [`PortfolioManagerStrategyValidator.sol`](../../packages/contracts/src/PortfolioManagerStrategyValidator.sol).
