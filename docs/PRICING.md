# Pricing

Portfolio Manager (PM) sets trade prices using a weighted formula and the chosen group shares.
It independently implements the constant-mean weighted-pool formula from Martinelli and Mushegian's 2019 Balancer whitepaper.
See [ADR-0004](adr/0004-constant-mean-weighted-curve-pricing.md) for the decision and [third-party notices](../THIRD_PARTY_NOTICES.md) for licensing.

## Units and inputs

| Symbol | Meaning |
|---|---|
| `B_i`, `B_o` | Current values of the input and output groups, calculated from price feeds. |
| `w_i`, `w_o` | Target shares (weights) of the token groups. All group weights sum to one. |
| `A_i`, `A_o` | Traded amounts in the same value unit as the group totals. |
| `f` | Liquidity provider's (LP's) fee as a fraction of input. The simulation default is 2 basis points (bps), or 0.02%. |

A group total is `Σ (member balance × member price)`, expressed in one currency, such as USD.
Values use WAD scaling: `1e18` represents one unit. Conversion accounts for each token's and feed's decimal places.
This applies to every group, including single-token groups -- except each group's own optional
numeraire member (ADR-0017), at most one per group, whose own native balance already is its value
and needs no feed at all. Different groups may use different numeraires, or none; the curve
formulas below only need each group's own members to agree on one unit, not the whole strategy.
Balances come from the maker wallet's `balanceOf`, without averaging past balances.

`PortfolioManagerSwap` converts amounts from each token's own units to value units before calling the pricing library.
It converts the result back afterward.
Weights and fees cannot change after the strategy is registered with Aqua (`ship()`).

## Spot price

```text
SP(i→o) = (B_i / w_i) / (B_o / w_o)
```

The spot price is the input value per unit of output value for a very small trade, before fees.
It equals one when the two groups match their relative target weights.

## Exact-in

Exact-in fixes how much the trader pays. Given input `A_i`, compute output `A_o`:

```text
A_i_eff = A_i * (1 - f)
A_o = B_o * (1 - (B_i / (B_i + A_i_eff))^(w_i / w_o))
```

The maker retains the curve fee, so the reserve increases by the full curve input `A_i`.
Round effective input, weight ratio, and output down.
Round the balance ratio up and use `FixedPointMath.powUp`.
An upper power bound reduces the output because the formula subtracts the power from one.

## Exact-out

Exact-out fixes how much the trader receives. Given output `A_o`, compute input `A_i`, including the LP fee:

```text
A_i_eff = B_i * ((B_o / (B_o - A_o))^(w_o / w_i) - 1)
A_i = ceil(A_i_eff / (1 - f))
```

Round the balance ratio, weight ratio, effective input, and fee adjustment up.
Use `FixedPointMath.powUp`.
Require `A_o < B_o`. Zero output requires zero input.

## Protocol fee

Three fees are skimmed from the LP curve fee (`feeBps`), computed independently of each other, not split from one combined amount.
[PortfolioManagerFee](../packages/contracts/src/utils/PortfolioManagerFee.sol) holds only the pure rate-application math; `PortfolioManagerSwap` holds the configured rates and recipients.

- **DAO fee (1inch's protocol fee)**: to `PROTOCOL_TREASURY`, at `PROTOCOL_FEE_RATE_BPS`. Both set once in `PortfolioManagerRouter`'s constructor and stored `immutable` -- changing either needs a new Router deployment. No setter exists for either, matching 1inch Operations' own request that their fee stay outside Bleu's control. Launches at a flat one sixth of `feeBps`.
- **1inch revenue share**: to `revenueShareTreasury`, at `revenueShareRateBps`. Both are ordinary mutable state, settable at any time by `REVENUE_SHARE_ADMIN` (an address fixed at construction, 1inch's own operational key) via `setRevenueShareTreasury`/`setRevenueShareRateBps` -- no new Router deployment needed. `setRevenueShareRateBps` rejects a rate at or above 100% as a sanity check. A separate, independently-tracked cut from the DAO fee above, even though both currently pay the same treasury address. Launches at one tenth of the DAO fee's own rate -- a flat one sixtieth of `feeBps` -- per 1inch's own ask (Kene), on top of, not instead of, the DAO fee.
- **Bleu/Trim fee**: to `operatorTreasury`, at `operatorFeeRateBps`. Both are ordinary mutable state, settable at any time by `OPERATOR` (an address fixed at construction) via `setOperatorTreasury`/`setOperatorFeeRateBps` -- no new Router deployment needed. `setOperatorFeeRateBps` rejects a rate at or above 100% as a sanity check. Launches at a flat one sixth of `feeBps` too, per the business decision recorded on BLEUDEV-457 (superseding an earlier 50/50-split arrangement and an earlier one-tenth figure).

All three treasury addresses and all three rates differ per deployment, not compiled constants -- including launching the DAO's side at 0% (a new Router) or the revenue-share or Bleu/Trim side at 0% (a setter call), and treasury addresses that aren't assumed to match across chains.

Nothing bounds any one rate alone against the other two sharing the same `feeBps` budget. Every setter that can move a mutable rate (`setOperatorFeeRateBps`, `setRevenueShareRateBps`), and the constructor itself, additionally requires the sum of all three rates to stay below `PM_BPS` (100%) -- `PortfolioManagerSwapCombinedFeeRateTooHigh` otherwise. Without this, the three rates reaching or exceeding 100% of `feeBps` would underflow `netBps` in the exact-out path and revert every exact-out swap for the strategy.

Rates use `PM_BPS = 1e9` for 100%, despite the `Bps` suffix. One conventional basis point equals `100_000` in this scale.
The DAO's launch rate matches the boundary cited by [1IP-103](https://gov.1inch.network/t/fast-track-1ip-103-aqua-launch-framework-aqua-interface-authorization-protocol-fee-activation/979); 1/6 isn't exactly representable at `PM_BPS` scale, so the deployed rate (`166_666_667`) is rounded to the nearest unit, not an exact 1/6. The revenue share's launch rate (`16_666_667`) is 1/60, rounded the same way.

For exact-in, the curve prices input after all three cuts.
For exact-out, the instruction adds all three fees after computing the curve's required input.
The contract attempts each transfer independently, without requiring it to succeed. A failed transfer emits `ProtocolFeeSkipped` for that recipient only, and the swap continues.
Quotes compute the amounts but skip all three transfers.

## Rounding and limits

- Group reserves and feed normalization round up for input and down for output.
- Token/value conversions round down for exact-in and up for exact-out.
- Zero reserves cause the trade to fail. Trades cannot drain the full output reserve.
- Exact-in requires `poweredRatio >= WAD / 1e9`, except when the exponent equals `WAD`.
- Calculations outside the supported number or exponent ranges cause the trade to fail. See [FixedPointMath](../packages/contracts/src/utils/FixedPointMath.sol) for power bounds.
- Equal weights reduce the formula to `xy=k`. Intermediate WAD rounding can produce more conservative quotes.
- The output token's own balance must cover the output, even when its group has enough total value.
- A price feed that is too old in either traded group causes the trade to fail, including a feed for a member that does not move.

## Deviation checks

`maxDeviationBps == 0` disables both deviation checks. Otherwise, both operate on the same
per-pair spot price `SP = (balanceIn/w_in) / (balanceOut/w_out)`, scaled the same way, but
against different baselines:

- Before a swap, PM caps how far the trade itself can move the traded pair's spot price:
  `abs(SP_after - SP_before) * PM_BPS / WAD <= maxDeviationBps`, checked after pricing the trade.
  No single trade -- corrective or worsening -- can move the pair by more than the threshold in
  one step, regardless of where it started.
- During validation, the validator checks every cross-group pair's spot-price deviation from
  parity: `abs(SP - WAD) * PM_BPS / WAD <= maxDeviationBps` for each pair -- the same metric the
  swap check applies to its "before" state, so an attested strategy is guaranteed tradeable in
  every direction right after shipping.

See [ADR-0012](adr/0012-price-deviation-circuit-breaker.md) and
[ADR-0016](adr/0016-per-trade-deviation-step-cap.md) for the swap-side check's design history.
The swap-side step cap only ever compares a trade's own before/after `SP`, so it checks
identically regardless of what unit a pair's two groups use -- no reconciliation needed, since
both sides of that comparison are computed the same way. The ship-time pairwise check compares
`SP` against parity (`WAD`), which only means "at target" when the pair's two groups already
share a unit. When they don't (two groups using different numeraires, per ADR-0017), a registered
`Bridge` feed converts one side into the other's unit first; a pair whose groups already share a
unit (including every pre-ADR-0017 strategy) needs no `Bridge` and checks exactly as before.

The [invariant proof](DONATION-RESISTANCE-PROOF.md) uses real-number arithmetic without implementation rounding.
The rounding rules implement conservative quotes for the supplied balances, weights, and fee.
