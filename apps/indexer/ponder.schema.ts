// See docs/adr/0014-production-arbitrageur-design.md ("Indexed state") for the design this
// schema implements, and README.md for the overall picture.
import { index, onchainTable, primaryKey } from "ponder";

// One row per shipped strategy (any app, not just this repo's own Portfolio Manager) --
// ADR-0011's off-chain "check prior active strategies" check reads this by `maker`.
export const strategy = onchainTable(
  "strategy",
  (t) => ({
    // `${maker}-${app}-${strategyHash}`, lowercase -- matches Aqua's own balance-state key.
    id: t.text().notNull(),
    maker: t.hex().notNull(),
    app: t.hex().notNull(),
    strategyHash: t.hex().notNull(),
    // Shipped's own `strategy` bytes -- ADR-0014's Strategy Payload "raw program data". Note
    // this is `abi.encode(ISwapVM.Order)` (maker, packed traits, and the program bytecode
    // buried inside `data`), not the bare SwapVM program bytecode alone -- Aqua hashes and emits
    // exactly this blob (`strategyHash = keccak256(strategy)`, matching `ISwapVM.hash`'s
    // "keccak256(abi.encode(order)) for Aqua orders"). Consumers need to ABI-decode the Order
    // first.
    encodedOrder: t.hex().notNull(),
    // Declared at ship() time, via same-tx Pushed events (see src/index.ts).
    tokens: t.hex().array().notNull(),
    // true from Shipped; flips false on the matching Docked.
    isActive: t.boolean().notNull(),
    shippedAt: t.bigint().notNull(),
    // Also used to tell ship-time Pushed events from later trade-time ones.
    shippedAtTxHash: t.hex().notNull(),
    dockedAt: t.bigint(),
    dockedAtTxHash: t.hex(),
    // Display labels per group, in group order -- copied in from a matching strategyAttestation
    // row at Shipped time (see src/index.ts), since BuildParametersAttested only carries a
    // strategyHash, not the maker/app this row's id needs. Null when the attesting transaction
    // (always same-batch, strictly before Shipped per ShipStrategy.s.sol) declined to name
    // groups, or shipped without ever calling attestBuildParameters at all.
    groupNames: t.text().array(),
  }),
  (table) => ({
    pk: primaryKey({ columns: [table.id] }),
    makerIdx: index().on(table.maker),
    appIdx: index().on(table.app),
    isActiveIdx: index().on(table.isActive),
  }),
);

// One row per attestBuildParameters call, keyed purely by strategyHash since
// BuildParametersAttested doesn't carry maker/app. Looked up by the Shipped handler (same
// transaction, always strictly after attestation in ShipStrategy.s.sol's batch) to fill in
// strategy.groupNames -- never queried directly by consumers.
export const strategyAttestation = onchainTable(
  "strategy_attestation",
  (t) => ({
    strategyHash: t.hex().notNull(), // lowercase
    groupNames: t.text().array().notNull(),
  }),
  (table) => ({ pk: primaryKey({ columns: [table.strategyHash] }) }),
);

// Marks an address as a known Strategy Wallet (a maker with at least one indexed strategy), set
// alongside every strategy row so the Transfer handler can check membership in O(1) instead of
// scanning every indexed strategy by its composite id.
export const strategyWallet = onchainTable(
  "strategy_wallet",
  (t) => ({ address: t.hex().notNull() }), // lowercase, the maker address
  (table) => ({ pk: primaryKey({ columns: [table.address] }) }),
);

// One row per allow-listed-token Transfer touching a known Strategy Wallet -- ADR-0014's "Wallet
// Balance Change" record. `change` is signed: negative when the wallet is the Transfer's `from`,
// positive when it's the `to`. A wallet's current balance for a token is the sum of its `change`
// rows plus the one-time balance read taken at Strategy discovery (see the ADR's Indexed state
// section) -- this table only ever stores deltas, never a running total, so re-processing never
// double-counts.
export const walletBalanceChange = onchainTable(
  "wallet_balance_change",
  (t) => ({
    id: t.text().notNull(), // `${transactionHash}-${logIndex}`
    wallet: t.hex().notNull(),
    token: t.hex().notNull(),
    change: t.bigint().notNull(),
    blockNumber: t.bigint().notNull(),
    blockTimestamp: t.bigint().notNull(),
    transactionHash: t.hex().notNull(),
    logIndex: t.integer().notNull(),
  }),
  (table) => ({
    pk: primaryKey({ columns: [table.id] }),
    walletIdx: index().on(table.wallet),
    tokenIdx: index().on(table.token),
  }),
);

// Maps a live Chainlink aggregator address to the feed proxy it currently backs. The well-known
// feed addresses (the ones this repo's contracts and tests use) are `EACAggregatorProxy`
// contracts that never emit `AnswerUpdated` themselves -- only their current underlying
// aggregator does, and Chainlink can swap that aggregator over time. `AnswerUpdated` only
// identifies the emitting aggregator, not which feed it's for, so this table is how the handler
// recovers that. Seeded with each feed's aggregator as of setup (see ponder.config.ts's
// comment); updated whenever a proxy's `AggregatorConfirmed` fires.
export const chainlinkAggregatorFeed = onchainTable(
  "chainlink_aggregator_feed",
  (t) => ({
    aggregator: t.hex().notNull(), // lowercase
    feedProxy: t.hex().notNull(), // the well-known feed (proxy) address this aggregator backs
  }),
  (table) => ({
    pk: primaryKey({ columns: [table.aggregator] }),
    feedProxyIdx: index().on(table.feedProxy),
  }),
);

// One row per Chainlink price update for an allow-listed token's feed -- ADR-0014's "Oracle
// Price" record. `feedProxy` is the well-known, stable feed address, not the (swappable)
// aggregator that actually emitted the event -- see chainlinkAggregatorFeed.
export const priceSnapshot = onchainTable(
  "price_snapshot",
  (t) => ({
    id: t.text().notNull(), // `${transactionHash}-${logIndex}`
    feedProxy: t.hex().notNull(),
    answer: t.bigint().notNull(),
    updatedAt: t.bigint().notNull(), // Chainlink's own reported update time
    blockNumber: t.bigint().notNull(),
    blockTimestamp: t.bigint().notNull(),
    transactionHash: t.hex().notNull(),
    logIndex: t.integer().notNull(),
  }),
  (table) => ({
    pk: primaryKey({ columns: [table.id] }),
    feedProxyIdx: index().on(table.feedProxy),
  }),
);
