# Pricing

PM independently implements the constant-mean weighted-pool formula from Martinelli and Mushegian's 2019 Balancer whitepaper.
See [ADR-0004](adr/0004-constant-mean-weighted-curve-pricing.md) for the decision and [third-party notices](../THIRD_PARTY_NOTICES.md) for licensing.

## Units and inputs

| Symbol | Meaning |
|---|---|
| `B_i`, `B_o` | Current oracle-valued totals of the input and output groups. |
| `w_i`, `w_o` | Target group weights. All declared group weights sum to one. |
| `A_i`, `A_o` | Traded amounts in the same value unit as the group totals. |
| `f` | LP curve fee as a fraction of input. The simulation default is 2 bps. |

A group total is `Σ (member balance × member price)`, with decimal conversion to a common WAD-scaled quote currency.
This applies to every group, including single-token groups.
Balances come from the maker wallet's `balanceOf`, without smoothing.

`PortfolioManagerSwap` converts native token amounts to value units before calling the pricing library and converts the result back afterward.
Weights and fees are fixed in the shipped strategy.

## Spot price

```text
SP(i→o) = (B_i / w_i) / (B_o / w_o)
```

This is input value per unit of output value, before fees.
It equals one when the two groups match their relative target weights.

## Exact-in

Given input `A_i`, compute output `A_o`:

```text
A_i_eff = A_i * (1 - f)
A_o = B_o * (1 - (B_i / (B_i + A_i_eff))^(w_i / w_o))
```

The maker retains the curve fee, so the reserve increases by the full curve input `A_i`.
Round effective input, weight ratio, and output down.
Round the balance ratio up and use `FixedPointMath.powUp`.
An upper power bound reduces the output because the formula subtracts the power from one.

## Exact-out

Given output `A_o`, compute gross input `A_i`:

```text
A_i_eff = B_i * ((B_o / (B_o - A_o))^(w_o / w_i) - 1)
A_i = ceil(A_i_eff / (1 - f))
```

Round the balance ratio, weight ratio, effective input, and fee adjustment up.
Use `FixedPointMath.powUp`.
Require `A_o < B_o`. Zero output requires zero input.

## Protocol fee

The DAO fee is separate from the LP curve fee.
[PortfolioManagerFee](../packages/contracts/src/utils/PortfolioManagerFee.sol) derives its rate from `feeBps`:

- At or below `1_225_000`: divide by four.
- Above `1_225_000`: divide by six.

Rates use `PM_BPS = 1e9` for 100%, despite the `Bps` suffix. One conventional basis point equals `100_000` in this scale.
The threshold implements 0.1225%, the approximate boundary cited by [1IP-103](https://gov.1inch.network/t/fast-track-1ip-103-aqua-launch-framework-aqua-interface-authorization-protocol-fee-activation/979).
Pending: confirm the exact boundary against 1inch's deployed constant.
Bleu's operator compensation remains unresolved and separate from the DAO fee.

For exact-in, the curve prices input after the DAO cut.
For exact-out, the instruction adds the DAO fee after computing the curve's required input.
The transfer to the DAO is best-effort. Failure emits `ProtocolFeeSkipped`, and the swap continues.
Quotes compute the amounts but skip the transfer.

## Rounding and limits

- Group reserves and feed normalization round up for input and down for output.
- Token/value conversions round down for exact-in and up for exact-out.
- Zero reserves revert. Trades cannot drain the full output reserve.
- Exact-in requires `poweredRatio >= WAD / 1e9`, except when the exponent equals `WAD`.
- Unsupported arithmetic or exponent ranges revert. See [FixedPointMath](../packages/contracts/src/utils/FixedPointMath.sol) for power bounds.
- Equal weights reduce the formula to `xy=k`. Intermediate WAD rounding can produce more conservative quotes.
- The output token's own balance must cover the output, even when its group has enough aggregate value.
- A stale feed in either traded group reverts the trade, including a feed for a member that does not move.

## Deviation checks

`maxDeviationBps == 0` disables both deviation checks. Otherwise:

- Before a swap, PM checks `abs(SP - WAD) * PM_BPS / WAD` for the traded pair.
- During validation, the validator checks each group's relative deviation from its target share of total portfolio value.

These checks use the same threshold but different metrics. They are not equivalent for general weights or group counts.
A failed pre-trade check blocks corrective trades too.
See [ADR-0012](adr/0012-price-deviation-circuit-breaker.md) for recovery and tradeoffs.

The [invariant proof](DONATION-RESISTANCE-PROOF.md) uses real arithmetic.
The rounding rules implement conservative quotes for the supplied balances, weights, and fee.
