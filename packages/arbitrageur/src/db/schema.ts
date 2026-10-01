import { pgTable, text, boolean, bigint, numeric, integer, jsonb, timestamp, primaryKey } from "drizzle-orm/pg-core";

/// Postgres `bigint` is a signed int64 (max ~9.22e18) -- too small for an 18-decimal WAD value
/// representing anything above ~$9.22 (e.g. one ETH's WAD price, ~2.69e21, overflows it outright).
/// `numeric` has no such ceiling; `{ mode: "bigint" }` still round-trips as a JS bigint like the
/// `bigint` columns elsewhere in this file, so callers don't need to know which one a field uses.
const usdWad = (name: string) => numeric(name, { mode: "bigint" });

/// One row per indexed Aqua strategy, mirrored from `packages/indexer`'s `Strategy` entity via
/// the `sync-indexer` job (see `src/sync/indexer.ts`). ADR-0014's Strategy Catalog domain.
/// `id` matches the indexer's own composite id (`${maker}-${app}-${strategyHash}`, lowercase) so
/// syncing is a plain upsert, never a lookup-then-insert.
export const strategies = pgTable("strategies", {
  id: text("id").primaryKey(),
  maker: text("maker").notNull(),
  app: text("app").notNull(),
  strategyHash: text("strategy_hash").notNull(),
  tokens: jsonb("tokens").$type<string[]>().notNull(),
  isActive: boolean("is_active").notNull(),
  // `abi.encode(ISwapVM.Order)` -- what Aqua's Shipped event actually carries (see
  // @aqua-portfolio-manager/decoding's orderDecoder.ts doc comment for why this isn't the bare
  // program bytes).
  // Always set at sync time; src/domains/strategyCatalog.ts decodes it, doesn't wait for it.
  encodedOrder: text("encoded_order").notNull(),
  resolverKycToken: text("resolver_kyc_token"),
  // null while still eligible; set to a short machine-readable reason otherwise (e.g.
  // "unsupported-token", "decode-failed") -- ADR-0014's "malformed or unsupported Strategy stays
  // in the catalog with an eligibility reason" rule. A Strategy Catalog row always exists once
  // Shipped fires; eligibility is evaluated, and can change, independently of that.
  ineligibilityReason: text("ineligibility_reason"),
  shippedAt: bigint("shipped_at", { mode: "bigint" }).notNull(),
  dockedAt: bigint("docked_at", { mode: "bigint" }),
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

/// Materialized current balance per (wallet, token) -- ADR-0014's Balance State domain. Not a
/// history table: seeded by a one-time multicall at Strategy discovery, then kept current by
/// applying each new indexed `WalletBalanceChange` delta as `sync-indexer` pulls it in. See that
/// job for why a materialized total, not stored deltas, is the right shape here.
export const strategyWalletBalances = pgTable(
  "strategy_wallet_balances",
  {
    wallet: text("wallet").notNull(),
    token: text("token").notNull(),
    balance: bigint("balance", { mode: "bigint" }).notNull(),
    updatedAt: timestamp("updated_at").notNull().defaultNow(),
  },
  (table) => [primaryKey({ columns: [table.wallet, table.token] })],
);

/// Latest usable price per feed -- ADR-0014's Price State domain. Not a history table: Candidate
/// Evaluation only ever wants "the newest usable Price Snapshot" (ADR-0014's own Price and
/// slippage rules section), so this holds exactly that, one row per feed, overwritten on every
/// new indexed `PriceSnapshot` `sync-indexer` pulls in. Full history stays in the indexer itself.
export const feedPrices = pgTable("feed_prices", {
  feedProxy: text("feed_proxy").primaryKey(),
  priceWad: usdWad("price_wad").notNull(), // 18-decimal normalized, matches src/oracle.ts's own normalization
  updatedAt: bigint("updated_at", { mode: "bigint" }).notNull(), // Chainlink's own reported update time
  blockTimestamp: bigint("block_timestamp", { mode: "bigint" }).notNull(),
});

/// Durable cursor for `sync-indexer` -- one row per synced Envio entity type, so a restart
/// resumes each independently instead of re-pulling everything or blocking on the slowest one.
export const syncCursors = pgTable("sync_cursors", {
  entity: text("entity").primaryKey(), // "Strategy" | "WalletBalanceChange" | "PriceSnapshot"
  cursor: text("cursor").notNull(), // opaque: the last-synced row's own id, used as a `> cursor` filter
  updatedAt: timestamp("updated_at").notNull().defaultNow(),
});

/// One row per ranked Candidate a Candidate Evaluation tick produced -- ADR-0014's Candidate
/// Evaluation output, consumed by `simulate-candidate` and read by the Operations API.
export const candidates = pgTable("candidates", {
  id: text("id").primaryKey(), // `${strategyId}-${tokenIn}-${tokenOut}-${stateVersion}-${retryCount}`
  strategyId: text("strategy_id")
    .notNull()
    .references(() => strategies.id),
  tokenIn: text("token_in").notNull(),
  tokenOut: text("token_out").notNull(),
  amountIn: bigint("amount_in", { mode: "bigint" }).notNull(),
  quotedOut: bigint("quoted_out", { mode: "bigint" }).notNull(), // the PM curve's own quoted output, from the pre-filter pass
  fairOut: bigint("fair_out", { mode: "bigint" }).notNull(),
  profitUsdWad: usdWad("profit_usd_wad").notNull(), // pre-filter estimate: curve quote vs. oracle fair value
  // ADR-0014's Profit Headroom: the real Fynd route's expected return, less principal, less the
  // return-token (tokenIn) value of the Profit Floor -- ranks Candidates that passed the
  // pre-filter and got a real Fynd quote. In tokenIn's own decimals, not USD: it's what the
  // executor actually needs (amountIn) more/less than, not a dollar figure.
  profitHeadroom: bigint("profit_headroom", { mode: "bigint" }).notNull(),
  fyndTarget: text("fynd_target").notNull(),
  fyndSpender: text("fynd_spender").notNull(),
  fyndCalldata: text("fynd_calldata").notNull(),
  minCurveAmountOut: bigint("min_curve_amount_out", { mode: "bigint" }).notNull(),
  deadline: bigint("deadline", { mode: "bigint" }).notNull(), // unix seconds
  stateVersion: text("state_version").notNull(),
  // Carried from the evaluate-strategy job that produced this Candidate, so a simulation or
  // execution failure knows how many retries this Strategy State has already used (ADR-0014:
  // "allows three retries for one Strategy State") without threading it through every downstream
  // queue job payload.
  retryCount: integer("retry_count").notNull().default(0),
  // null until `simulate-candidate` runs; "eligible" | "simulated" | "simulation_failed" |
  // "executed" | "execution_failed" | "superseded" (a newer State Version replaced this one
  // before it reached execution -- see `evaluate-strategy`'s "replace an older State Version" rule).
  status: text("status").notNull().default("eligible"),
  rejectionReason: text("rejection_reason"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

/// One row per `execute-candidate` attempt -- ADR-0014's Execution domain output and Operations
/// API `/v1/execution-attempts` source. A retried Candidate produces multiple rows here, one per
/// attempt, per the ADR's "the service never submits the same parameters again" rule (a retry
/// re-evaluates and re-simulates, producing a new Candidate and a new attempt, not a resubmission
/// of this same row).
export const executionAttempts = pgTable("execution_attempts", {
  id: text("id").primaryKey(),
  candidateId: text("candidate_id")
    .notNull()
    .references(() => candidates.id),
  executorAddress: text("executor_address").notNull(),
  executorVersion: text("executor_version").notNull(),
  txHash: text("tx_hash"),
  // "simulating" | "confirmed" | "final" | "failed" -- "final" only once the indexer itself
  // reaches the configured confirmation depth (ADR-0014's Operations section), not just one
  // on-chain confirmation.
  status: text("status").notNull(),
  failureReason: text("failure_reason"),
  submittedAt: timestamp("submitted_at"),
  confirmedAt: timestamp("confirmed_at"),
  finalizedAt: timestamp("finalized_at"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

export type StrategyRow = typeof strategies.$inferSelect;
export type StrategyWalletBalanceRow = typeof strategyWalletBalances.$inferSelect;
export type FeedPriceRow = typeof feedPrices.$inferSelect;
export type CandidateRow = typeof candidates.$inferSelect;
export type ExecutionAttemptRow = typeof executionAttempts.$inferSelect;
