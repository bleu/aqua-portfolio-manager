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

`SP(i→o)` equals exactly `1` (WAD) when a group pair's real composition matches its declared target weights, regardless of the weight ratio, and diverges from `1` in proportion to how far off-target the pair has drifted. An optional, opt-in `maxDeviationBps` bounds that divergence: if `|SP(i→o) - 1|` (in bps) exceeds it, both the swap-time pairwise check (`PortfolioManagerSwap`, checked against current pre-trade state) and the ship-time whole-portfolio check (`PortfolioManagerStrategyValidator`, checked once at `ship()`) revert rather than price or ship against an already-extreme composition. `maxDeviationBps == 0` disables both checks — this is not part of the pricing formula itself, just a bound checked against its output.

## Rounding conventions

Group reserves, including feed normalization, round up on the input side and down on the output side. Native-token/value conversions round down for exact-in and up for exact-out. Shared arithmetic and decimal conversion helpers live in `FixedPointMath`; their API and power bounds are documented there.

## Exact-in swap

Trader specifies `A_i` (amount of token *i* they're sending in); solve for `A_o`.

Fee is taken off the top of the input before it counts toward the priced amount, but the *full* `A_i` (fee included) is what actually lands in the wallet's real balance — this is what lets the fee show up as a strict invariant increase, not just revenue that's accounted for separately:

    A_i_eff = A_i * (1 - f)
    A_o = B_o * (1 - (B_i / (B_i + A_i_eff))^(w_i / w_o))

**Rounding:** floor effective input, weight ratio, and final output; ceil the balance ratio and use `FixedPointMath.powUp`. The power is subtracted from one, so its upper bound reduces the output in the pool's favor.

## Exact-out swap

Trader specifies `A_o` (amount of token *o* they want out); solve for `A_i`, the gross amount they must pay including fee.

    A_i_eff = B_i * ((B_o / (B_o - A_o))^(w_o / w_i) - 1)
    A_i = ceil(A_i_eff / (1 - f))

**Rounding:** ceil the balance ratio, weight ratio, effective input, and fee gross-up; use `FixedPointMath.powUp`. Require `A_o < B_o`; zero output requires zero input.

## Degenerate cases

- **`B_i == 0` or `B_o == 0`:** revert. A weighted pool's price is undefined at a zero balance on either side — same requirement `BasketXYCSwap.sol`'s PoC already enforces (`BasketXYCSwapRequiresNonZeroBalances`).
- **No minimum balance beyond nonzero, but no full drain:** both paths require `A_o < B_o`.
- **Exact-in precision floor:** require `poweredRatio >= WAD / 1e9` unless the computed exponent equals `WAD`. Unsupported arithmetic or exponent ranges revert.
- **`w_i == w_o`:** the formula reduces to `xy=k`; intermediate WAD rounding can make quotes more conservative than a single constant-product division.
- **Single-token groups vs. multi-token groups (ADR-0003):** every group's `B_i`/`B_o` is its *oracle-valued total* — `Σ (token_balance_j × oracle_price_j)` over every token `j` the group holds, all converted to the same numeraire — not any one token's balance; this applies uniformly, even to a single-member group (`PortfolioManagerSwap.sol` never special-cases "skip the oracle"). Which token within a group actually moves on a given trade is resolved by the group config before this formula is invoked (`PortfolioManagerSwap._resolve`), not something this formula itself decides.
- **`A_i`/`A_o` must be converted into and back out of that same oracle-value numeraire around this formula's call, by the caller, not by this formula.** `B_i`/`B_o` are value-scaled (WAD, one common numeraire across every group member), but the actual traded amount a taker specifies/receives is always in the specific traded token's own native units — those are only the same number when that token happens to be worth ~1 unit of the numeraire per native unit (e.g. a stablecoin at 18 decimals), which is *not* generally true (a non-stable token like WETH is off by orders of magnitude). `PortfolioManagerSwap._portfolioManagerSwapXD` does this conversion explicitly on both sides of the `exactIn`/`exactOut` call using the specific traded token's own price/decimals — this formula itself stays opaque to it, per its own scope note above, exactly the same way it's opaque to how `B_i`/`B_o` were resolved.
- **Any group member's oracle price stale beyond its configured max age (ADR-0005):** revert. Applies per-feed, so a multi-token group needs every member fresh, not just the two tokens actually being swapped — see ADR-0005's Consequences for why that's accepted rather than narrowed to "only the tokens changing hands."

## Invariant proof

[`DONATION-RESISTANCE-PROOF.md`](DONATION-RESISTANCE-PROOF.md) proves the formula in real arithmetic. The rounding rules above conservatively implement its quotes for the supplied balances, weights, and fee.
