# ADR-0014: Production arbitrageur design

**Status:** Proposed

## Context

The current arbitrageur experiment uses a static strategy file and a Uniswap V4 flash-borrow path. It does not use indexed Strategy State, queues, REST operations, or durable execution records.

The production arbitrageur must discover Aqua Strategies on Base, evaluate them with indexed balances and oracle events, execute an atomic Aave V3 and Fynd trade, and operate from one shared wallet.

## Decision

Run one Base-only arbitrageur application. It uses Postgres, Redis and BullMQ, Envio, local Fynd, Base RPC, Chainlink feeds, and Aave V3. It starts in dry-run mode. A configuration change enables transaction submission.

The token allow list contains USDC, USDT, WETH, and WBTC. Each token record contains its address, decimals, Chainlink feed, and Aave V3 reserve status. The service records unsupported Strategies but does not trade them.

## System topology

```mermaid
flowchart LR
    operator[Internal operator] --> api[Read-only Operations API]
    api --> app[Arbitrageur application]
    app --> postgres[(Postgres)]
    app --> redis[(Redis and BullMQ)]
    app --> fynd[Local Fynd]
    app --> rpc[Base RPC]
    indexer[Envio indexer] --> app
    base[Base contracts and events] --> indexer
    fynd --> rpc
    rpc --> base
    app --> slack[Slack]
```

Envio and Fynd are local dependencies. They are not parts of the arbitrageur application.

## Domains

| Domain | Responsibility | Services it uses |
| --- | --- | --- |
| Strategy Catalog | Store Shipped and Docked Strategies, raw program data, decoded data, and eligibility. | Envio and Postgres |
| Balance State | Store supported-token balances for each Strategy Wallet. | Envio, Base RPC, and Postgres |
| Price State | Store usable Chainlink Price Snapshots. | Envio and Postgres |
| Candidate Evaluation | Screen a Strategy State, find a Fynd Route, solve the input size, and rank Candidates. | Fynd, Postgres, Redis, and shared math |
| Transaction Simulation | Validate a Candidate against current Base state. | Base RPC, Aave V3, executor, and Postgres |
| Execution | Serialize nonces, send transactions, track results, and retry. | Base RPC, Redis, Postgres, and Slack |
| Operations API | Return authenticated, read-only operational data. | Postgres and health checks |
| Notification | Send transaction and critical-fault messages. | Slack |

## Domain and service interaction

```mermaid
flowchart TB
    subgraph App[Arbitrageur application]
        catalog[Strategy Catalog]
        balance[Balance State]
        price[Price State]
        evaluate[Candidate Evaluation]
        simulate[Transaction Simulation]
        execute[Execution]
        api[Operations API]
        notice[Notification]
    end

    envio[Envio] --> catalog
    envio --> balance
    envio --> price
    catalog --> evaluate
    balance --> evaluate
    price --> evaluate
    evaluate --> fynd[Local Fynd]
    evaluate --> redis[(BullMQ)]
    redis --> simulate
    simulate --> rpc[Base RPC]
    simulate --> redis
    redis --> execute
    execute --> rpc
    execute --> notice
    notice --> slack[Slack]
    catalog --> postgres[(Postgres)]
    balance --> postgres
    price --> postgres
    evaluate --> postgres
    simulate --> postgres
    execute --> postgres
    api --> postgres
```

## Indexed state

Extend Envio with these records.

| Record | Source | Required data |
| --- | --- | --- |
| Strategy Payload | `Shipped` and `Docked` | Raw program data, decoded trade data, active state, block, transaction, and log index. |
| Wallet Balance Change | `Transfer` for allow-listed tokens and Strategy Wallets | Wallet, token, signed change, block, transaction, and log index. |
| Oracle Price | Chainlink feed update event | Feed, answer, decimals, time, block, transaction, and log index. |

At Strategy discovery, the application reads supported token balances with one multicall. It then uses indexed transfers as the normal balance source. It uses one new multicall only for the selected Candidate before simulation.

A malformed or unsupported Strategy stays in the catalog with an eligibility reason. It cannot create a Candidate.

## Queue rules

BullMQ payloads contain record identifiers and a State Version. Postgres stores the full history.

| Queue | Rule |
| --- | --- |
| `sync-indexer` | Read new indexer data and store a durable cursor. |
| `evaluate-strategy` | Keep one queued job per Strategy. Replace an older State Version. |
| `simulate-candidate` | Simulate the best Candidate for a Strategy State. |
| `execute-candidate` | Run one job at a time because one wallet owns all nonces. |
| `track-transaction` | Track submission, confirmation, and indexer finality. |
| `retry-evaluation` | Re-evaluate a Candidate with new state. |

A State Version includes the Strategy Payload version, balance cursor, Price Snapshot block, Fynd Route time or block, and executor version. A worker discards an old State Version.

The service allows three retries for one Strategy State. A new Strategy, balance, oracle, or market event resets the retry count. Each retry creates new quotes, limits, and a simulation.

## Candidate evaluation

```mermaid
sequenceDiagram
    participant Envio
    participant State as State modules
    participant Queue as BullMQ
    participant Evaluator
    participant Fynd
    participant Simulator
    participant Executor
    participant Base

    Envio->>State: Strategy, balance, or oracle event
    State->>Queue: Coalesced evaluation
    Queue->>Evaluator: Latest State Version
    Evaluator->>Evaluator: Screen and solve input size
    Evaluator->>Fynd: Request Fynd Route
    Fynd-->>Evaluator: Encoded route
    Evaluator->>Queue: Ranked Candidate
    Queue->>Simulator: Candidate
    Simulator->>Base: Multicall and eth_call
    Base-->>Simulator: Result
    Simulator->>Queue: Execute or retry
    Queue->>Executor: Best Candidate
    Executor->>Base: Submit transaction
```

A Strategy, balance, or oracle event starts evaluation. A low-rate recovery job also starts evaluation.

The evaluator first uses Price Snapshots and TypeScript contract math. It excludes a Strategy State when the possible price difference cannot meet fees and the Profit Floor. It calls Fynd only for remaining inputs.

The evaluator tests exact input amounts within Strategy limits, Strategy Wallet balance, Aave V3 liquidity, and route liquidity. It selects the amount with the highest Profit Headroom. `ProfitHeadroom` is expected return after principal less the return-token value of the Profit Floor.

Fynd finds the allowed market pools and returns an executable Fynd Route. The service configures its timeout and minimum response count. A route that cannot run in the executor is not eligible.

## Price and slippage rules

Price State uses Chainlink push-feed events. It stores one normalized price for each feed and event block. A stale, zero, negative, or unsupported price makes only affected Strategy Legs ineligible. This follows [ADR 0005](0005-chainlink-push-oracles.md).

At transaction build time, the evaluator converts the global USD Profit Floor to the expected return token with the newest usable Price Snapshot. It rejects a stale price. The executor receives that token amount as `minProfit`.

The evaluator sets minimum output amounts for both legs from pool state and configured slippage limits. The transaction reverts if either leg fails its minimum output.

TypeScript quote code must match Solidity integer math. Shared test vectors and Base-fork tests must cover rounding, invalid input, and Strategy State changes. Python simulation is not the live quote source.

## Atomic execution

Each executor version is an immutable Aave V3 contract. Postgres stores its address and version with every Execution Attempt.

```mermaid
sequenceDiagram
    participant App as Arbitrageur application
    participant RPC as Base RPC
    participant Executor as Aave executor
    participant Aave as Aave V3
    participant Strategy as Aqua Strategy
    participant Fynd as Fynd settlement

    App->>RPC: eth_call selected Candidate
    RPC->>Executor: Simulate call
    App->>RPC: Submit transaction
    RPC->>Executor: Execute call
    Executor->>Aave: Borrow input asset
    Aave->>Executor: Flash-loan callback
    Executor->>Strategy: Run Strategy Leg
    Strategy-->>Executor: Output asset
    Executor->>Fynd: Run encoded Market Leg
    Fynd-->>Executor: Borrowed asset
    Executor->>Aave: Repay principal and fee
    Executor->>Executor: Check minProfit
    Executor-->>RPC: Commit or revert
```

The executor borrows one input asset, runs the Strategy Leg, runs the Fynd Route, repays Aave V3, and checks `minProfit`. A failed step reverts the full transaction.

The executor has only required ERC-20 approvals for the approved Fynd settlement contract and supported tokens. It must call the Fynd Route in the Aave callback. It must not use a separate EOA swap.

The application rebuilds the transaction and runs `eth_call` against the latest Base state before submission. The contract also checks oracle freshness and `minProfit` during simulation and execution.

## Operations

Only the Execution domain reads `PRIVATE_KEY` from `.env`. Its worker concurrency is one. It sends transactions through public Base RPC.

The service records a submitted transaction and sends a Slack message. It marks the transaction final after one confirmation. It keeps checking until the indexer reaches its configured confirmation depth. It then stores the final result and sends a Slack message.

A failed Execution Attempt records its reason and enters the retry flow. The service never submits the same parameters again.

The service pauses new submissions when Envio, Price State, Fynd, Base RPC, Aave V3 simulation, or token configuration is unhealthy. It continues to index data and record Candidates. It resumes after healthy checks pass.

Configuration contains freshness limits, Fynd limits, slippage limits, Profit Floor, retry count, confirmation depth, and recovery interval.

## REST API

The internal REST API requires bearer-token authentication. It has no write endpoints.

| Endpoint | Data |
| --- | --- |
| `GET /health` | Application and dependency health, including pause state. |
| `GET /v1/strategies` | Strategies, Strategy State, and eligibility reasons. |
| `GET /v1/strategy-wallets` | Supported-token balance snapshots. |
| `GET /v1/candidates` | Candidates, estimates, rank, and rejection reason. |
| `GET /v1/execution-attempts` | Simulations, transactions, retries, and outcomes. |
| `GET /v1/config` | Safe read-only configuration. |

The API does not return secrets.

## Consequences

The service requires Envio, Fynd, Postgres, Redis, and a Base RPC provider. It does not require application-level horizontal scaling. BullMQ separates work and protects the single shared wallet from nonce conflicts.

The service must validate Aave V3 reserve support, Fynd route encoding, and executor approvals for each allow-listed token before it enables transaction submission.

Transaction submission is allowed only when the service discovers supported Strategies without restart, builds current Strategy State from indexed data, proves quote parity, simulates the full Aave V3 and Fynd transaction, bounds retries, pauses on stale dependencies, and stores every Execution Attempt.

## References

- [ADR 0005: Chainlink push oracles](0005-chainlink-push-oracles.md)
- [Aqua strategy indexer](../../packages/indexer/README.md)
- Existing arbitrageur branch: `origin/luizhatem/bleudev-349-arbitrageur-server-in-the-place-of-1inch-pathfinder-to-test`
