# Aqua Portfolio Manager

Aqua manages on-chain portfolio strategies whose prices depend on wallet balances and oracle values. This glossary defines the terms used by the protocol, indexer, and arbitrageur.

## Protocol

**Strategy**:
An immutable Aqua program that a maker ships through an app. It is active until it is docked.
_Avoid_: position, order

**Strategy Wallet**:
The maker wallet whose token balances the Strategy uses for pricing and settlement.
_Avoid_: position wallet, pool wallet

**Strategy State**:
The current active status, declared tokens, decoded program data, and token balances for a Strategy.
_Avoid_: position

**Shipped Strategy**:
A Strategy that Aqua has registered and made active.
_Avoid_: created strategy, deployed strategy

**Docked Strategy**:
A Strategy that Aqua has disabled.
_Avoid_: deleted strategy, cancelled strategy

**Strategy Leg**:
The exchange of the borrowed asset against a Strategy.
_Avoid_: first leg, buy leg

**Market Leg**:
The route that exchanges the asset received from a Strategy back into the borrowed asset.
_Avoid_: second leg, Fynd leg, sell leg

## Arbitrage

**Candidate**:
A Strategy State and a proposed trade size that may produce a profitable atomic arbitrage.
_Avoid_: opportunity, job

**Execution Attempt**:
One evaluated Candidate that the arbitrageur simulates or submits to Base.
_Avoid_: trade, transaction

**Profit Floor**:
The configured minimum profit in USD that the arbitrageur converts into the return token before execution.
_Avoid_: min profitable, profit threshold

**Profit Headroom**:
The estimated return after principal less the Profit Floor. It ranks Candidates after route estimation.
_Avoid_: distance to arbitrage, margin

**Price Snapshot**:
The latest usable oracle values for all tokens needed by a Candidate, identified by their source block.
_Avoid_: current price, oracle quote

**State Version**:
The indexed strategy, balance, oracle, and market state used for one Candidate evaluation.
_Avoid_: retry version

**Fynd Route**:
An executable market-leg route returned by the local Fynd aggregator.
_Avoid_: Fynd quote, swap path
