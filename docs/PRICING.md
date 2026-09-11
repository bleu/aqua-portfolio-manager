# Pricing formula

The constant-mean weighted curve this strategy prices with (ADR-0004, ADR-0007) — the published Balancer weighted-pool formula (Martinelli & Mushegian, 2019, "Balancer: A non-custodial portfolio manager, liquidity provider, and price sensor"), reimplemented from scratch here, not Balancer's GPL Solidity (see ADR-0001/ADR-0004 for why). Stated here precisely enough to implement and to prove the round-trip invariant against.

## Inputs

For a swap between token *i* (in) and token *o* (out), both belonging to declared groups in the strategy's config:

- `B_i`, `B_o` — the group's **current, real** exposure reading, straight from `balanceOf` on the maker wallet (ADR-0002 — not `AQUA.safeBalances()`, which is a same-strategy-only ledger, not a wallet-wide reading), valued via the Oracle Adapter (ADR-0005) if the group holds more than one token (ADR-0003). No EMA/TWAP — ADR-0006 dropped the moving average (2026-08-18); the tolerance band, where it applies, is a stateless function of this same current reading, not a separate lagging variable.
- `w_i`, `w_o` — the group's target weight, normalized so all weights in the strategy sum to 1. Fixed at `ship()` time (part of the immutable `strategyHash`), never updated in place.
- `f` — the protocol fee, in scope for Milestone 1 as the flat 2 bps referenced in ADR-0008; taken on the input side.

Because `B_i`/`B_o` is the same real balance Aqua actually moves on pull/push, this is a plain Balancer weighted pool in the one respect that matters for the donation-resistance proof: the balance that sets the price and the balance a trade updates are the same variable, so Balancer's own round-trip argument transfers directly — see `DONATION-RESISTANCE-PROOF.md`.

## Spot price

    SP(i→o) = (B_i / w_i) / (B_o / w_o)

Token *i* priced in terms of token *o*, before fees. Standard constant-mean result — see Martinelli & Mushegian (2019), cited above, for the full derivation.

## Exact-in swap

Trader specifies `A_i` (amount of token *i* they're sending in); solve for `A_o`.

Fee is taken off the top of the input before it counts toward the priced amount, but the *full* `A_i` (fee included) is what actually lands in the wallet's real balance — this is what lets the fee show up as a strict invariant increase, not just revenue that's accounted for separately:

    A_i_eff = A_i * (1 - f)
    A_o = B_o * (1 - (B_i / (B_i + A_i_eff))^(w_i / w_o))

**Rounding: floor `A_o`.** Same direction `BasketXYCSwap.sol`'s PoC already uses for the `xy=k` special case — the pool keeps the remainder, never the trader.

## Exact-out swap

Trader specifies `A_o` (amount of token *o* they want out); solve for `A_i`, the gross amount they must pay including fee.

    A_i_eff = B_i * ((B_o / (B_o - A_o))^(w_i / w_o) - 1)
    A_i = ceil(A_i_eff / (1 - f))

**Rounding: ceil throughout** — both the intermediate `A_i_eff` and the final fee grossed-up `A_i`. Same direction as exact-in: every rounding choice favors the pool, never the trader. `B_o > A_o` is a required precondition (checked, not assumed) — the curve is only defined while there's balance left to trade against, same as any constant-mean pool.

## Degenerate cases

- **`B_i == 0` or `B_o == 0`:** revert. A weighted pool's price is undefined at a zero balance on either side — same requirement `BasketXYCSwap.sol`'s PoC already enforces (`BasketXYCSwapRequiresNonZeroBalances`).
- **`w_i == w_o`:** the formula reduces exactly to `xy=k` (the PoC's case) — `(w_i/w_o) = 1`, so `A_o = B_o * (1 - B_i/(B_i + A_i_eff))`, which is algebraically identical to the constant-product formula the PoC already implements and tests. This is a useful sanity check for the implementation: the equal-weight case must reproduce the PoC's existing, tested numbers exactly.
- **Single-token groups vs. multi-token groups (ADR-0003):** when a group holds more than one token, `B_i`/`B_o` above is the group's *oracle-valued total* — `Σ (token_balance_j × oracle_price_j)` over every token `j` the group holds, all converted to the same numeraire — not any one token's balance. Which token within a multi-token group actually moves on a given trade is a routing detail the group config resolves before this formula is invoked, not something this formula itself decides; the oracle-valuation sum above is what this formula does need, and does receive, from that resolution step.
- **Any group member's oracle price stale beyond its configured max age (ADR-0005):** revert. Applies per-feed, so a multi-token group needs every member fresh, not just the two tokens actually being swapped — see ADR-0005's Consequences for why that's accepted rather than narrowed to "only the tokens changing hands."

## Invariant proof

This formula is what `DONATION-RESISTANCE-PROOF.md` proves the round-trip/donation-resistance property against — see that file for the full proof (closed, no open half).
