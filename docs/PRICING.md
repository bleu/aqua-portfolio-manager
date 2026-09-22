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
This applies to every group, including single-token groups.
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

`maxDeviationBps == 0` disables both deviation checks. Otherwise:

- Before a swap, PM checks `abs(SP - WAD) * PM_BPS / WAD` for the traded pair.
- During validation, the validator checks each group's relative deviation from its target share of total portfolio value.

These checks use the same threshold but different measurements. They are not equivalent for general weights or group counts.
A failed pre-trade check blocks corrective trades too.
See [ADR-0012](adr/0012-price-deviation-circuit-breaker.md) for recovery and tradeoffs.

The [invariant proof](DONATION-RESISTANCE-PROOF.md) uses real-number arithmetic without implementation rounding.
The rounding rules implement conservative quotes for the supplied balances, weights, and fee.
