import { Queue } from "bullmq";
import type IORedis from "ioredis";

/// ADR-0014's Queue rules, as typed job payloads. Each queue's own worker (src/workers/*.ts)
/// interprets these; this file only defines the shape and the enqueue helpers whose semantics
/// aren't a plain `queue.add`.

export interface SyncIndexerJob {
  // No payload -- always pulls everything new since each entity's own durable cursor.
}

export interface EvaluateStrategyJob {
  strategyId: string;
  stateVersion: string;
  retryCount: number;
}

export interface SimulateCandidateJob {
  candidateId: string;
}

export interface ExecuteCandidateJob {
  candidateId: string;
}

export interface TrackTransactionJob {
  executionAttemptId: string;
  txHash: string;
}

export interface RetryEvaluationJob {
  strategyId: string;
  stateVersion: string;
  retryCount: number;
}

export interface Queues {
  syncIndexer: Queue<SyncIndexerJob>;
  evaluateStrategy: Queue<EvaluateStrategyJob>;
  simulateCandidate: Queue<SimulateCandidateJob>;
  executeCandidate: Queue<ExecuteCandidateJob>;
  trackTransaction: Queue<TrackTransactionJob>;
  retryEvaluation: Queue<RetryEvaluationJob>;
}

export function makeQueues(connection: IORedis): Queues {
  return {
    syncIndexer: new Queue("sync-indexer", { connection }),
    evaluateStrategy: new Queue("evaluate-strategy", { connection }),
    simulateCandidate: new Queue("simulate-candidate", { connection }),
    executeCandidate: new Queue("execute-candidate", { connection }),
    trackTransaction: new Queue("track-transaction", { connection }),
    retryEvaluation: new Queue("retry-evaluation", { connection }),
  };
}

/// "Keep one queued job per Strategy. Replace an older State Version." (ADR-0014's Queue rules).
/// BullMQ's `add` with an existing `jobId` leaves the existing job untouched rather than updating
/// it -- including a *completed* or *failed* one, not just waiting/delayed -- so replacement is
/// explicit here: drop any prior job for this Strategy before adding the new State Version under
/// the same id. Without this, a Strategy's first evaluation would be its last: every later tick's
/// `add` would silently no-op against the same jobId forever once it reached a terminal state
/// (found live -- a real Strategy evaluated exactly once across hundreds of successful
/// sync-indexer ticks before this fix). A job already `active` is the one exception, left alone --
/// its worker reads current Strategy/Balance/Price state itself when it runs, so an in-flight
/// evaluation on a now-stale State Version wastes at most one evaluation, never trades on stale
/// data.
export async function enqueueEvaluateStrategy(
  queues: Queues,
  strategyId: string,
  stateVersion: string,
  retryCount = 0,
): Promise<void> {
  const existing = await queues.evaluateStrategy.getJob(strategyId);
  if (existing) {
    const state = await existing.getState();
    if (state !== "active") {
      await existing.remove();
    }
  }
  await queues.evaluateStrategy.add(
    "evaluate-strategy",
    { strategyId, stateVersion, retryCount },
    { jobId: strategyId },
  );
}
