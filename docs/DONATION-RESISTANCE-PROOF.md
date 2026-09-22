# Curve invariant and donation resistance

This proof covers Portfolio Manager (PM) trades and donations that add tokens without taking any out.
It uses real-number arithmetic without implementation rounding.
It does not prove preservation of market value under arbitrary wallet activity or oracle changes.
See [pricing](PRICING.md) for units and implementation rounding.

## Assumptions

- Reserves `B_i`, `B_o` are positive and use a common value unit.
- Weights `w_i`, `w_o` are positive and fixed. Other groups' reserves remain fixed during the trade.
- Oracle valuations remain fixed across the balance changes being compared.
- The curve fee satisfies `0 <= f < 1`.
- The reserve receives the full curve input, including the retained LP fee.

The DAO cut is separate from curve input. PM prices the input after that cut.
A failed DAO transfer leaves additional value in the wallet rather than reducing the curve input.

## Claim

The invariant `V` combines reserves and weights. Each exact-in trade must leave it unchanged or increase it:

```text
V = B_i^w_i * B_o^w_o
V_after >= V_before
```

Equality holds when `f = 0` or `A_i = 0`.

## Proof

Let `A_i_eff = A_i * (1 - f)`. The pricing formula gives:

```text
A_o = B_o * (1 - (B_i / (B_i + A_i_eff))^(w_i/w_o))
B_o - A_o = B_o * (B_i / (B_i + A_i_eff))^(w_i/w_o)
(B_o - A_o)^w_o = B_o^w_o * (B_i / (B_i + A_i_eff))^w_i
```

The input reserve receives `A_i`, so:

```text
V_after = (B_i + A_i)^w_i * (B_o - A_o)^w_o
        = (B_i + A_i)^w_i * B_o^w_o * (B_i / (B_i + A_i_eff))^w_i
        = B_i^w_i * B_o^w_o * ((B_i + A_i) / (B_i + A_i_eff))^w_i
        = V_before * ((B_i + A_i) / (B_i + A_i_eff))^w_i
```

Since `A_i_eff <= A_i`, the ratio is at least one.
Since `w_i > 0`, its power is also at least one.
Thus `V_after >= V_before`, with strict inequality for positive input and a positive fee.

Solving the same formula for input gives exact-out pricing, so the proof also applies to it.

## Trades and donations

A sequence of supported curve trades cannot decrease `V` under these assumptions.
A positive donation increases a reserve without taking tokens out, so it increases `V` too.

Returning every reserve to its starting value would return `V` to its starting value.
That is impossible after any strict increase if subsequent operations cannot decrease `V`.
Likewise, ending with every reserve no greater, and at least one smaller, would contradict the rule that `V` cannot decrease.
These statements concern reserve changes, not profit from external price changes or trading venues.

## Limits

A different strategy can remove one token while adding another under a different pricing rule.
Its trade can decrease PM's invariant. It is not a pure donation.

[ADR-0011](adr/0011-safe-wallet-with-basket-scope-guard.md) restricts other strategies' declared groups, subject to the Guard's call coverage.
A within-group trade can still change the group's oracle-valued total.
Group membership alone therefore does not establish the invariant assumption for all cross-strategy activity.
Direct withdrawals and changing oracle valuations also fall outside this derivation.

The proof requires current reserves.
An exponential moving average (EMA) or time-weighted average (TWAP) would use past balances in pricing.
That would require a separate proof.
Taker profitability and correction frequency do not enter this per-trade proof.

[Pricing tests](../packages/contracts/test/PortfolioManagerPricing.t.sol) check fixed-point behavior, including independent integer invariants for selected weight ratios.
Approximate tests with tolerances provide additional coverage, not a proof for every input.
