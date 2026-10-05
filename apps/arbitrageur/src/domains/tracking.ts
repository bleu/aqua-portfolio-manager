import { eq } from "drizzle-orm";
import type { Hex, PublicClient } from "viem";
import type { Db } from "../db/client.js";
import { executionAttempts } from "../db/schema.js";

export type TrackingStatus = "pending" | "final" | "not-found";

/// Execution domain's finality check (ADR-0014's Operations section): "marks the transaction
/// final after one confirmation. It keeps checking until the indexer reaches its configured
/// confirmation depth."
///
/// Deliberate simplification: this checks confirmation depth against the live chain
/// (`publicClient.getBlockNumber()`), not against how far `apps/indexer`'s own sync has
/// progressed. The ADR's literal design waits for the *indexer* to catch up, so a downstream
/// consumer reading Postgres never sees an execution as final before its own effects (balance
/// changes, etc.) are indexed and synced. Chain-depth confirmation is what's implemented here --
/// correct for "is this transaction unlikely to be reorged out," not for "has everything this
/// transaction did been synced into this service's own Postgres." Tracking indexer sync progress
/// specifically (e.g. via a query against its own confirmed block height) is a real, separate
/// follow-up, not done here.
export async function checkTransactionFinality(
  db: Db,
  publicClient: PublicClient,
  executionAttemptId: string,
  confirmationDepth: number,
): Promise<TrackingStatus> {
  const attempt = await db.query.executionAttempts.findFirst({
    where: eq(executionAttempts.id, executionAttemptId),
  });
  if (!attempt || !attempt.txHash) return "not-found";

  const [receipt, currentBlock] = await Promise.all([
    publicClient.getTransactionReceipt({ hash: attempt.txHash as Hex }),
    publicClient.getBlockNumber(),
  ]);

  const confirmations = currentBlock - receipt.blockNumber;
  if (confirmations < BigInt(confirmationDepth)) return "pending";

  await db
    .update(executionAttempts)
    .set({ status: "final", finalizedAt: new Date() })
    .where(eq(executionAttempts.id, executionAttemptId));
  return "final";
}
