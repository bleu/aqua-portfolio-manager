import { eq } from "drizzle-orm";
import type { Address } from "viem";
import type { Db } from "../db/client.js";
import { candidates, executionAttempts } from "../db/schema.js";
import { buildFlashArbParams } from "./transactionSimulation.js";
import { simulateFlashArbitrage, submitFlashArbitrage, makeClients } from "../chain.js";

export type ExecutionResult =
  | { ok: true; executionAttemptId: string; txHash: `0x${string}` }
  | { ok: false; executionAttemptId: string; reason: string };

/// Execution domain (ADR-0014): the only place that ever submits a transaction, and (via the
/// `execute-candidate` queue's own concurrency: 1, wired in src/workers/executeCandidate.ts) the
/// only place that ever does so more than once at a time -- one wallet owns all nonces.
///
/// Re-simulates immediately before submitting rather than reusing simulate-candidate's earlier
/// result: "The application rebuilds the transaction and runs eth_call against the latest Base
/// state before submission" (ADR-0014's Atomic execution section). This also sidesteps a real
/// practical problem -- viem's simulateContract `request` object (account, abi reference) isn't
/// JSON-serializable, so it can't cross a BullMQ job boundary anyway; rebuilding from Postgres
/// (buildFlashArbParams) and re-simulating here is the only design that both matches the ADR and
/// actually works.
export async function executeCandidate(
  db: Db,
  clients: ReturnType<typeof makeClients>,
  arbitrageurAddress: Address,
  executorVersion: string,
  candidateId: string,
): Promise<ExecutionResult> {
  const executionAttemptId = `${candidateId}-${Date.now()}`;
  const built = await buildFlashArbParams(db, candidateId);
  if (!built) {
    await db.insert(executionAttempts).values({
      id: executionAttemptId,
      candidateId,
      executorAddress: arbitrageurAddress,
      executorVersion,
      status: "failed",
      failureReason: "candidate-or-strategy-not-found",
    });
    return { ok: false, executionAttemptId, reason: "candidate-or-strategy-not-found" };
  }

  // Inserted before anything can throw, not after simulation succeeds -- the catch block below
  // updates this same row by id, and an update matching no row would silently drop the failure
  // record instead of persisting it.
  await db.insert(executionAttempts).values({
    id: executionAttemptId,
    candidateId,
    executorAddress: arbitrageurAddress,
    executorVersion,
    status: "simulating",
  });

  try {
    const request = await simulateFlashArbitrage(clients.publicClient, clients.account, arbitrageurAddress, built.params);
    await db
      .update(executionAttempts)
      .set({ status: "submitted", submittedAt: new Date() })
      .where(eq(executionAttempts.id, executionAttemptId));

    const result = await submitFlashArbitrage(clients.walletClient, clients.publicClient, request);

    await db.update(candidates).set({ status: "executed" }).where(eq(candidates.id, candidateId));
    await db
      .update(executionAttempts)
      .set({ txHash: result.txHash, status: "confirmed", confirmedAt: new Date() })
      .where(eq(executionAttempts.id, executionAttemptId));

    return { ok: true, executionAttemptId, txHash: result.txHash };
  } catch (err) {
    const reason = err instanceof Error ? err.message : "unknown";
    await db
      .update(candidates)
      .set({ status: "execution_failed", rejectionReason: reason })
      .where(eq(candidates.id, candidateId));
    await db
      .update(executionAttempts)
      .set({ status: "failed", failureReason: reason })
      .where(eq(executionAttempts.id, executionAttemptId));
    return { ok: false, executionAttemptId, reason };
  }
}
