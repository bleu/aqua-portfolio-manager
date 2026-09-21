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

**Rounding: floor `A_o`.** The implementation floors the effective input and final output, ceilings the balance ratio, floors the weight ratio, and uses `FixedPointMath.powUp`. For a balance ratio at most one, decreasing the exponent increases the power. These choices therefore upper-bound the subtracted power and conservatively bound the library's output quote for its supplied inputs. At equal weights, the power is an exact identity. Unequal weights use the directed bounds described below, rather than an undirected PRBMath power estimate.

## Exact-out swap

Trader specifies `A_o` (amount of token *o* they want out); solve for `A_i`, the gross amount they must pay including fee.

    A_i_eff = B_i * ((B_o / (B_o - A_o))^(w_o / w_i) - 1)
    A_i = ceil(A_i_eff / (1 - f))

**Rounding: ceil throughout.** The implementation ceilings the balance ratio, weight ratio, intermediate `A_i_eff`, and final fee grossed-up `A_i`. Its `FixedPointMath.powUp` upper-bounds the power for a base of at least one using error bounds derived from the pinned PRBMath `log2` and `exp2` source. Those bounds must be rechecked when the dependency changes. This composition favors the pool, but can conservatively overquote tiny trades or revert when the upper bound exceeds the supported arithmetic or exponent domain. `B_o > A_o` is a checked precondition; zero output requires zero input.

## Shared arithmetic and unit conversion

`FixedPointMath` provides eight operation families: `mulDown`/`mulUp`, `divDown`/`divUp`, `powDown`/`powUp`, and `scaleDown`/`scaleUp`. Multiplication and division default to WAD and accept an optional explicit scale, with full-precision intermediate multiplication. `scaleDown(value, fromDecimals, toDecimals)` and `scaleUp(...)` name the rounding direction, not whether the decimal scale increases or decreases; increasing decimal precision is exact checked multiplication in both helpers.

Powers take WAD-scaled inputs and return lower or upper bounds. Above one they bound errors in the pinned PRBMath `log2`/`exp2` implementation; below one they use reciprocals with the corresponding directed bounds. An intermediate reciprocal power can exceed PRBMath's domain and revert even when the final fractional value would fit. Exact identities include `0^0 = 1`, positive powers of zero, and exponent one. These shortcuts can introduce small discontinuities in the bounds; directional accuracy does not imply strict monotonicity across every adjacent representable input.

`PortfolioManagerSwap` rounds both exact-in conversions down: native input to value and output value to native output. It rounds both exact-out conversions up: requested native output to value and required input value to native input. These inequalities are relative to the supplied WAD-normalized prices and group values. Oracle normalization, aggregate-value rounding, feed correctness, and settlement remain separate from the pricing library's quote guarantees.

## Degenerate cases

- **`B_i == 0` or `B_o == 0`:** revert. A weighted pool's price is undefined at a zero balance on either side — same requirement `BasketXYCSwap.sol`'s PoC already enforces (`BasketXYCSwapRequiresNonZeroBalances`).
- **No separate minimum-*balance* threshold, but `A_o` computing to the pool's entire `B_o` or more must revert.** The real-arithmetic invariant is scale-invariant for positive balances, but the implementation has finite arithmetic and exponent domains. Exact-in retains a postcondition requiring its computed `A_o < B_o`; exact-out checks the same inequality on the requested output before evaluating the formula. A previous undirected power approximation could underflow to zero and compute a full drain. The explicit guard remains alongside the directed power bound.
- **Exact-in retains a minimum powered ratio off the identity shortcut.** Unless the computed exponent equals `WAD`, `poweredRatio` must be at least `WAD / 1e9` (a real ratio of `1e-9`). This existing precision floor still rejects near-depletion quotes; the new directed power bound supplies the rounding guarantee independently of that guard. The exactly-one exponent shortcut returns the ceiled balance ratio directly, so it bypasses this floor while retaining the nonzero-balance and full-drain checks.
- **`w_i == w_o`:** the real-arithmetic formula reduces exactly to `xy=k` (the PoC's case) — `(w_i/w_o) = 1`, so `A_o = B_o * (1 - B_i/(B_i + A_i_eff))`. The power shortcut is exact, but the implementation's intermediate WAD-scaled ratio division can add conservative rounding compared with a single constant-product division. Tests check the algebraic equivalence within that rounding difference and verify the rounding direction separately.
- **Single-token groups vs. multi-token groups (ADR-0003):** every group's `B_i`/`B_o` is its *oracle-valued total* — `Σ (token_balance_j × oracle_price_j)` over every token `j` the group holds, all converted to the same numeraire — not any one token's balance; this applies uniformly, even to a single-member group (`PortfolioManagerSwap.sol` never special-cases "skip the oracle"). Which token within a group actually moves on a given trade is resolved by the group config before this formula is invoked (`PortfolioManagerSwap._resolve`), not something this formula itself decides.
- **`A_i`/`A_o` must be converted into and back out of that same oracle-value numeraire around this formula's call, by the caller, not by this formula.** `B_i`/`B_o` are value-scaled (WAD, one common numeraire across every group member), but the actual traded amount a taker specifies/receives is always in the specific traded token's own native units — those are only the same number when that token happens to be worth ~1 unit of the numeraire per native unit (e.g. a stablecoin at 18 decimals), which is *not* generally true (a non-stable token like WETH is off by orders of magnitude). `PortfolioManagerSwap._portfolioManagerSwapXD` does this conversion explicitly on both sides of the `exactIn`/`exactOut` call using the specific traded token's own price/decimals — this formula itself stays opaque to it, per its own scope note above, exactly the same way it's opaque to how `B_i`/`B_o` were resolved.
- **Any group member's oracle price stale beyond its configured max age (ADR-0005):** revert. Applies per-feed, so a multi-token group needs every member fresh, not just the two tokens actually being swapped — see ADR-0005's Consequences for why that's accepted rather than narrowed to "only the tokens changing hands."

## Invariant proof

`DONATION-RESISTANCE-PROOF.md` analyzes this formula in real arithmetic. Both pricing-library quote paths now compose directed bounds conservatively for their supplied inputs, with independent invariant tests checking the implementation. This does not extend the formula proof to every oracle-normalization, valuation, or settlement assumption.
