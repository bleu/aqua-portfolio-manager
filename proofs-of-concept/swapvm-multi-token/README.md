# PoC: a swapVM curve that prices against a 3-token basket

Standalone Foundry project — not part of the main repo's build. Answers a concrete question that came up while deciding the strategy's on-chain form ([ADR-0010](../../docs/adr/0010-on-chain-form-aquaapp-vs-swapvm-instruction.md)): swapVM's `Context` struct exposes only two token slots, seemingly built for pairwise swaps — does that block a multi-token portfolio strategy that needs to price against a whole group's balance, not just the two tokens being swapped?

**Answer: no, nothing in swap-vm's core needs to change.** `VM.sol`, `SwapVM.sol`, and the opcode dispatch loop are untouched. An instruction isn't limited to the two tokens in `Context` — it can hold its own `IAqua` reference and read any other token's balance directly (the same escape-hatch pattern `Fee.sol` already uses).

- `src/BasketXYCSwap.sol` — `xy=k` with `balanceOut` replaced by `balanceOut` + a third token's Aqua balance, read via the instruction's own `IAqua` reference. The third token is priced against but never pulled or pushed — only the two swapped tokens move.
- `src/PoCOpcodes.sol`, `src/PoCRouter.sol` — mirror `AquaOpcodes`/`AquaSwapVMRouter` exactly, registering this one instruction.
- `test/BasketXYCSwap.t.sol` — end-to-end against a real `AquaRouter` (not mocked): price tracks the basket formula, the third token never moves, and a zero basket balance reduces exactly to plain `xy=k`.

This is our own router, not 1inch's deployed one — it doesn't change the reachability dependency ADR-0010 discusses, it only proves the mechanism is buildable as a swapVM instruction. Not part of any milestone deliverable; the on-chain form decision itself was made on the unilateral-deployability criterion, with this PoC as supporting evidence ahead of the full simulation-based gas/frontier comparison ADR-0010 originally scoped.

## Running

```bash
git submodule update --init --recursive -- lib
forge build
forge test
```
