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
This applies to every group, including single-token groups -- except the strategy's optional
numeraire member (ADR-0017), at most one across every group, whose own native balance already is
its value and needs no feed at all.
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

The protocol fee goes to the 1inch DAO treasury. It is separate from the LP curve fee.
[PortfolioManagerFee](../packages/contracts/src/utils/PortfolioManagerFee.sol) derives its rate from `feeBps`:

- At or below `1_225_000`: divide by four.
- Above `1_225_000`: divide by six.

Rates use `PM_BPS = 1e9` for 100%, despite the `Bps` suffix. One conventional basis point equals `100_000` in this scale.
The threshold implements 0.1225%, the approximate boundary cited by [1IP-103](https://gov.1inch.network/t/fast-track-1ip-103-aqua-launch-framework-aqua-interface-authorization-protocol-fee-activation/979).
Pending: confirm the exact boundary against 1inch's deployed constant.
Payment for Bleu's work as operator remains undecided and separate from the DAO fee.

For exact-in, the curve prices input after the DAO cut.
For exact-out, the instruction adds the DAO fee after computing the curve's required input.
The contract attempts the DAO transfer without requiring it to succeed. Failure emits `ProtocolFeeSkipped`, and the swap continues.
Quotes compute the amounts but skip the transfer.

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
Both formulas above only ever compare `balanceIn`/`balanceOut` ratios in whatever unit the
strategy uses, so a strategy denominated in a numeraire member (ADR-0017) instead of USD checks
identically -- the ratio is the same regardless of what the shared unit represents.

The [invariant proof](DONATION-RESISTANCE-PROOF.md) uses real-number arithmetic without implementation rounding.
The rounding rules implement conservative quotes for the supplied balances, weights, and fee.
