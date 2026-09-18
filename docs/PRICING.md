# Pricing formula

The constant-mean weighted curve this strategy prices with (ADR-0004, ADR-0007) — the published Balancer weighted-pool formula (Martinelli & Mushegian, 2019, "Balancer: A non-custodial portfolio manager, liquidity provider, and price sensor"), reimplemented from scratch here, not Balancer's GPL Solidity (see ADR-0001/ADR-0004 for why). Stated here precisely enough to implement and to prove the round-trip invariant against.

## Inputs

For a swap between token *i* (in) and token *o* (out), both belonging to declared groups in the strategy's config:

- `B_i`, `B_o` — the group's **current, real** exposure reading, straight from `balanceOf` on the maker wallet (ADR-0002 — not `AQUA.safeBalances()`, which is a same-strategy-only ledger, not a wallet-wide reading), valued via the Oracle Adapter (ADR-0005) if the group holds more than one token (ADR-0003). No EMA/TWAP — ADR-0006 dropped the moving average (2026-08-18) and rejected a tolerance band entirely; the deviation circuit breaker (ADR-0012, below) is a stateless function of this same current reading, not a separate lagging variable.
- `w_i`, `w_o` — the group's target weight, normalized so all weights in the strategy sum to 1. Fixed at `ship()` time (part of the immutable `strategyHash`), never updated in place.
- `f` — the protocol fee, in scope for Milestone 1 as the flat 2 bps referenced in ADR-0008; taken on the input side.

Because `B_i`/`B_o` is the same real balance Aqua actually moves on pull/push, this is a plain Balancer weighted pool in the one respect that matters for the donation-resistance proof: the balance that sets the price and the balance a trade updates are the same variable, so Balancer's own round-trip argument transfers directly — see `DONATION-RESISTANCE-PROOF.md`.

## Spot price

    SP(i→o) = (B_i / w_i) / (B_o / w_o)

Token *i* priced in terms of token *o*, before fees. Standard constant-mean result — see Martinelli & Mushegian (2019), cited above, for the full derivation.

## Deviation circuit breaker (ADR-0012)

`SP(i→o)` equals exactly `1` (WAD) when a group pair's real composition matches its declared target weights, regardless of the weight ratio, and diverges from `1` in proportion to how far off-target the pair has drifted. An optional, opt-in `maxDeviationBps` bounds that divergence: if `|SP(i→o) - 1|` (in bps) exceeds it, both the swap-time pairwise check (`PortfolioManagerSwap`, checked against current pre-trade state) and the ship-time whole-portfolio check (`PortfolioManagerStrategyFactory`, checked once at `ship()`) revert rather than price or ship against an already-extreme composition. `maxDeviationBps == 0` disables both checks — this is not part of the pricing formula itself, just a bound checked against its output.

## Exact-in swap

Trader specifies `A_i` (amount of token *i* they're sending in); solve for `A_o`.

Fee is taken off the top of the input before it counts toward the priced amount, but the *full* `A_i` (fee included) is what actually lands in the wallet's real balance — this is what lets the fee show up as a strict invariant increase, not just revenue that's accounted for separately:

    A_i_eff = A_i * (1 - f)
    A_o = B_o * (1 - (B_i / (B_i + A_i_eff))^(w_i / w_o))

**Rounding: floor `A_o`.** Same direction `BasketXYCSwap.sol`'s PoC already uses for the `xy=k` special case — the pool keeps the remainder, never the trader.

## Exact-out swap

Trader specifies `A_o` (amount of token *o* they want out); solve for `A_i`, the gross amount they must pay including fee.

    A_i_eff = B_i * ((B_o / (B_o - A_o))^(w_o / w_i) - 1)
    A_i = ceil(A_i_eff / (1 - f))

**Rounding: ceil throughout** — both the intermediate `A_i_eff` and the final fee grossed-up `A_i`. Same direction as exact-in: every rounding choice favors the pool, never the trader. `B_o > A_o` is a required precondition (checked, not assumed) — the curve is only defined while there's balance left to trade against, same as any constant-mean pool.

## Degenerate cases

- **`B_i == 0` or `B_o == 0`:** revert. A weighted pool's price is undefined at a zero balance on either side — same requirement `BasketXYCSwap.sol`'s PoC already enforces (`BasketXYCSwapRequiresNonZeroBalances`).
- **No separate minimum-*balance* threshold, but `A_o` computing to the pool's entire `B_o` or more must revert.** `DONATION-RESISTANCE-PROOF.md`'s invariant proof is scale-invariant (holds for any `B_i, B_o > 0`, no minimum-size assumption), and no arbitrary balance threshold is needed for that property to hold. But the *implementation* has its own failure mode distinct from the proof's real-number math: at a sufficiently skewed `w_i/w_o` combined with a small `B_i`, the fixed-point power computation can underflow to exactly zero (the true value is real but below WAD's representable precision), which without a guard computes `A_o` as exactly `B_o` — the entire pool, for an ordinary-sized trade. Exact-in must check this the same way exact-out already required `A_o < B_o` as a precondition — as a postcondition on the computed result, since exact-in doesn't know `A_o` in advance.
- **`w_i == w_o`:** the formula reduces exactly to `xy=k` (the PoC's case) — `(w_i/w_o) = 1`, so `A_o = B_o * (1 - B_i/(B_i + A_i_eff))`, which is algebraically identical to the constant-product formula the PoC already implements and tests. This is a useful sanity check for the implementation: the equal-weight case must reproduce the PoC's existing, tested numbers exactly.
- **Single-token groups vs. multi-token groups (ADR-0003):** every group's `B_i`/`B_o` is its *oracle-valued total* — `Σ (token_balance_j × oracle_price_j)` over every token `j` the group holds, all converted to the same numeraire — not any one token's balance; this applies uniformly, even to a single-member group (`PortfolioManagerSwap.sol` never special-cases "skip the oracle"). Which token within a group actually moves on a given trade is resolved by the group config before this formula is invoked (`PortfolioManagerSwap._resolve`), not something this formula itself decides.
- **`A_i`/`A_o` must be converted into and back out of that same oracle-value numeraire around this formula's call, by the caller, not by this formula.** `B_i`/`B_o` are value-scaled (WAD, one common numeraire across every group member), but the actual traded amount a taker specifies/receives is always in the specific traded token's own native units — those are only the same number when that token happens to be worth ~1 unit of the numeraire per native unit (e.g. a stablecoin at 18 decimals), which is *not* generally true (a non-stable token like WETH is off by orders of magnitude). `PortfolioManagerSwap._portfolioManagerSwapXD` does this conversion explicitly on both sides of the `exactIn`/`exactOut` call using the specific traded token's own price/decimals — this formula itself stays opaque to it, per its own scope note above, exactly the same way it's opaque to how `B_i`/`B_o` were resolved.
- **Any group member's oracle price stale beyond its configured max age (ADR-0005):** revert. Applies per-feed, so a multi-token group needs every member fresh, not just the two tokens actually being swapped — see ADR-0005's Consequences for why that's accepted rather than narrowed to "only the tokens changing hands."

## Invariant proof

This formula is what `DONATION-RESISTANCE-PROOF.md` proves the round-trip/donation-resistance property against — see that file for the full proof (closed, no open half).
