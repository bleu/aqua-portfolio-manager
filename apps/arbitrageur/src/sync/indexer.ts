import type { GraphQLClient } from "graphql-request";
import { eq } from "drizzle-orm";
import type { Db } from "../db/client.js";
import { strategies, feedPrices, syncCursors } from "../db/schema.js";
import { fetchAllStrategies, fetchPriceSnapshotsAfter } from "./indexerClient.js";

/// All four feeds this service currently watches (see apps/indexer/ponder.config.ts's
/// CHAINLINK_PROXIES comment) are 8-decimal, USD-quoted -- verified via each feed's own decimals()
/// call, not assumed. A feed with a different decimals count would need this made per-feed
/// (carried alongside the feed address in config, the way src/oracle.ts's caller already does
/// for the live-RPC path) rather than a single constant.
const CHAINLINK_FEED_DECIMALS = 8;

/// Mirrors src/oracle.ts's readOraclePriceWad normalization exactly -- same rule, applied to an
/// indexed answer instead of a live eth_call result.
export function normalizeToWad(rawAnswer: bigint, decimals: number): bigint {
  if (decimals < 18) return rawAnswer * 10n ** BigInt(18 - decimals);
  if (decimals > 18) return rawAnswer / 10n ** BigInt(decimals - 18);
  return rawAnswer;
}

/// Strategy Catalog sync: full paginated re-scan (see fetchAllStrategies's own doc comment for
/// why), each row upserted by its indexer-assigned id. Eligibility/program-decoding is a
/// separate concern (src/domains/strategyCatalog.ts reads these rows, doesn't compute here) --
/// this function's only job is mirroring what Envio has, not judging it.
export async function syncStrategies(db: Db, indexerClient: GraphQLClient): Promise<number> {
  const rows = await fetchAllStrategies(indexerClient);
  if (rows.length === 0) return 0;

  await db.transaction(async (tx) => {
    for (const row of rows) {
      await tx
        .insert(strategies)
        .values({
          id: row.id,
          maker: row.maker,
          app: row.app,
          strategyHash: row.strategyHash,
          encodedOrder: row.encodedOrder,
          tokens: row.tokens,
          isActive: row.isActive,
          shippedAt: BigInt(row.shippedAt),
          dockedAt: row.dockedAt === null ? null : BigInt(row.dockedAt),
          updatedAt: new Date(),
        })
        .onConflictDoUpdate({
          target: strategies.id,
          set: {
            tokens: row.tokens,
            isActive: row.isActive,
            dockedAt: row.dockedAt === null ? null : BigInt(row.dockedAt),
            updatedAt: new Date(),
          },
        });
    }
  });

  return rows.length;
}

/// Exported for testing; also used directly by the sync functions below. A missing cursor means
/// "nothing synced yet" -- `logIndex: -1` so the very first indexed row (logIndex 0) at block 0
/// still compares as strictly after it.
export function parseCursor(cursor: string | undefined): { block: bigint; logIndex: number } {
  if (!cursor) return { block: 0n, logIndex: -1 };
  const [block, logIndex] = cursor.split(":");
  return { block: BigInt(block), logIndex: Number(logIndex) };
}

export function formatCursor(block: bigint, logIndex: number): string {
  return `${block}:${logIndex}`;
}

/// Price State sync: one transaction per batch, cursor advance included -- a crash mid-batch
/// rolls back everything, so a retry re-fetches the same batch instead of silently skipping it.
/// Each row *replaces* `feed_prices`' one row per feed rather than accumulating -- Candidate
/// Evaluation only ever wants the newest usable Price Snapshot (ADR-0014's Price and slippage
/// rules), so there is nothing to sum here. A batch can carry several updates for the same feed;
/// applying them in fetched (block, logIndex) order means the last write for a feed in a batch is
/// the one that survives, which is correct -- it's the newest one in that batch.
export async function syncPriceSnapshots(db: Db, indexerClient: GraphQLClient): Promise<number> {
  const cursorRow = await db.query.syncCursors.findFirst({ where: eq(syncCursors.entity, "PriceSnapshot") });
  const { block, logIndex } = parseCursor(cursorRow?.cursor);

  const rows = await fetchPriceSnapshotsAfter(indexerClient, block, logIndex);
  if (rows.length === 0) return 0;

  await db.transaction(async (tx) => {
    for (const row of rows) {
      const priceWad = normalizeToWad(BigInt(row.answer), CHAINLINK_FEED_DECIMALS);
      await tx
        .insert(feedPrices)
        .values({
          feedProxy: row.feedProxy,
          priceWad,
          updatedAt: BigInt(row.updatedAt),
          blockTimestamp: BigInt(row.blockTimestamp),
        })
        .onConflictDoUpdate({
          target: feedPrices.feedProxy,
          set: { priceWad, updatedAt: BigInt(row.updatedAt), blockTimestamp: BigInt(row.blockTimestamp) },
        });
    }

    const last = rows[rows.length - 1]!;
    await tx
      .insert(syncCursors)
      .values({
        entity: "PriceSnapshot",
        cursor: formatCursor(BigInt(last.blockNumber), last.logIndex),
        updatedAt: new Date(),
      })
      .onConflictDoUpdate({
        target: syncCursors.entity,
        set: { cursor: formatCursor(BigInt(last.blockNumber), last.logIndex), updatedAt: new Date() },
      });
  });

  return rows.length;
}

/// The `sync-indexer` queue job (ADR-0014's Queue rules): pulls both synced record types once.
/// Each sync function pages internally, so one call here can apply more than one batch.
export async function runIndexerSync(db: Db, indexerClient: GraphQLClient) {
  const [strategyCount, priceCount] = await Promise.all([
    syncStrategies(db, indexerClient),
    syncPriceSnapshots(db, indexerClient),
  ]);
  return { strategyCount, priceCount };
}
