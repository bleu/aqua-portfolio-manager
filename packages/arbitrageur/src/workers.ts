import { Worker, type Job } from "bullmq";
import type IORedis from "ioredis";
import { eq, isNull, and } from "drizzle-orm";
import type { PublicClient } from "viem";
import type { Db } from "./db/client.js";
import { strategies } from "./db/schema.js";
import type { Config } from "./config.js";
import type { makeClients } from "./chain.js";
import type { FyndClient } from "./fynd.js";
import { runIndexerSync } from "./sync/indexer.js";
import { evaluateAllStrategyCatalog } from "./domains/strategyCatalog.js";
import { evaluateStrategy } from "./domains/candidateEvaluation.js";
import { simulateCandidate } from "./domains/transactionSimulation.js";
import { executeCandidate } from "./domains/execution.js";
import { checkTransactionFinality } from "./domains/tracking.js";
import { notifySlack, formatExecutionSubmitted, formatExecutionFinal, formatExecutionFailed, formatCriticalFault } from "./domains/notification.js";
import {
  makeQueues,
  enqueueEvaluateStrategy,
  type Queues,
  type EvaluateStrategyJob,
  type SimulateCandidateJob,
  type ExecuteCandidateJob,
  type TrackTransactionJob,
  type RetryEvaluationJob,
} from "./queue/queues.js";

export interface WorkerDeps {
  db: Db;
  clients: ReturnType<typeof makeClients>;
  publicClient: PublicClient;
  fyndClient: FyndClient;
  indexerClient: import("graphql-request").GraphQLClient;
  config: Config;
  queues: Queues;
}

/// A fresh State Version per sync tick -- ADR-0014's own definition ("Strategy Payload version,
/// balance cursor, Price Snapshot block, Fynd Route time or block, and executor version")
/// resolves to real per-source versions the worker would need to correlate across three
/// independent sources; this uses the sync tick's own wall-clock time as a single, monotonic
/// stand-in instead. Good enough to let `evaluate-strategy`'s "replace an older State Version"
/// rule work correctly (a later tick's version always compares greater), not a literal encoding
/// of which underlying rows changed.
function newStateVersion(): string {
  return Date.now().toString();
}

async function notifyCriticalFault(config: Config, context: string, err: unknown): Promise<void> {
  if (!config.slackWebhookUrl) return;
  const reason = err instanceof Error ? err.message : String(err);
  await notifySlack(config.slackWebhookUrl, formatCriticalFault(context, reason)).catch(() => {});
}

/// sync-indexer: pulls new Envio data into Postgres, re-evaluates Strategy Catalog eligibility,
/// then starts evaluation for every active, eligible Strategy -- the practical stand-in for "A
/// Strategy, balance, or oracle event starts evaluation" (Candidate evaluation section) without a
/// row-level change-notification mechanism from Postgres. Runs on SYNC_INTERVAL_MS via the
/// repeatable job scheduled in startWorkers, doubling as the ADR's own "low-rate recovery job"
/// when nothing has actually changed.
function makeSyncIndexerWorker(deps: WorkerDeps): Worker {
  return new Worker(
    "sync-indexer",
    async () => {
      const result = await runIndexerSync(deps.db, deps.indexerClient);
      await evaluateAllStrategyCatalog(deps.db, new Set(deps.config.allowedTokens));

      const eligible = await deps.db.query.strategies.findMany({
        where: and(eq(strategies.isActive, true), isNull(strategies.ineligibilityReason)),
      });
      const stateVersion = newStateVersion();
      await Promise.all(
        eligible.map((s) => enqueueEvaluateStrategy(deps.queues, s.id, stateVersion)),
      );

      return result;
    },
    { connection: deps.queues.syncIndexer.opts.connection as IORedis },
  );
}

function makeEvaluateStrategyWorker(deps: WorkerDeps): Worker<EvaluateStrategyJob> {
  return new Worker<EvaluateStrategyJob>(
    "evaluate-strategy",
    async (job: Job<EvaluateStrategyJob>) => {
      const { strategyId, stateVersion, retryCount } = job.data;
      const candidateId = await evaluateStrategy(
        deps.db,
        deps.publicClient,
        deps.clients.account,
        deps.fyndClient,
        strategyId,
        stateVersion,
        retryCount,
        {
          minTradeUsdWad: deps.config.minTradeUsdWad,
          maxTradeUsdWad: deps.config.maxTradeUsdWad,
          minProfitUsdWad: deps.config.minProfitUsdWad,
          maxPriceStalenessSeconds: deps.config.maxPriceStalenessSeconds,
          fyndSlippageBps: deps.config.fyndSlippageBps,
          fyndMinResponses: deps.config.fyndMinResponses,
          fyndTimeoutMs: deps.config.fyndTimeoutMs,
          slippageBufferBps: deps.config.slippageBufferBps,
          deadlineBufferSeconds: deps.config.deadlineBufferSeconds,
          arbitrageurAddress: deps.config.arbitrageurAddress,
        },
      );
      if (candidateId) {
        await deps.queues.simulateCandidate.add("simulate-candidate", { candidateId });
      }
    },
    { connection: deps.queues.evaluateStrategy.opts.connection as IORedis },
  );
}

/// Bounded by ADR-0014's own rule: "The service allows three retries for one Strategy State."
/// `retryCount` travels with the job through evaluate -> simulate/execute -> retry -> evaluate
/// again, incremented once per lap; a new State Version (a real Strategy/balance/oracle event, or
/// the next sync tick) always starts a fresh strategy at retryCount 0, matching "a new ... event
/// resets the retry count."
async function maybeRetry(deps: WorkerDeps, strategyId: string, stateVersion: string, retryCount: number): Promise<void> {
  if (retryCount >= deps.config.maxRetries) return;
  await deps.queues.retryEvaluation.add("retry-evaluation", { strategyId, stateVersion, retryCount: retryCount + 1 });
}

function makeSimulateCandidateWorker(deps: WorkerDeps): Worker<SimulateCandidateJob> {
  return new Worker<SimulateCandidateJob>(
    "simulate-candidate",
    async (job: Job<SimulateCandidateJob>) => {
      const { candidateId } = job.data;
      const candidate = await deps.db.query.candidates.findFirst({ where: (c, { eq: e }) => e(c.id, candidateId) });
      if (!candidate) return;

      const result = await simulateCandidate(deps.db, deps.publicClient, deps.clients.account, deps.config.arbitrageurAddress, candidateId);
      if (result.ok) {
        await deps.queues.executeCandidate.add("execute-candidate", { candidateId });
      } else {
        await maybeRetry(deps, candidate.strategyId, candidate.stateVersion, candidate.retryCount);
      }
    },
    { connection: deps.queues.simulateCandidate.opts.connection as IORedis },
  );
}

function makeExecuteCandidateWorker(deps: WorkerDeps): Worker<ExecuteCandidateJob> {
  return new Worker<ExecuteCandidateJob>(
    "execute-candidate",
    async (job: Job<ExecuteCandidateJob>) => {
      const { candidateId } = job.data;
      const candidate = await deps.db.query.candidates.findFirst({ where: (c, { eq: e }) => e(c.id, candidateId) });
      if (!candidate) return;

      if (deps.config.dryRun) {
        return; // ADR-0014: "starts in dry-run mode. A configuration change enables transaction submission."
      }

      const result = await executeCandidate(deps.db, deps.clients, deps.config.arbitrageurAddress, deps.config.executorVersion, candidateId);
      if (result.ok) {
        if (deps.config.slackWebhookUrl) {
          await notifySlack(deps.config.slackWebhookUrl, formatExecutionSubmitted(candidateId, result.txHash)).catch(() => {});
        }
        await deps.queues.trackTransaction.add(
          "track-transaction",
          { executionAttemptId: result.executionAttemptId, txHash: result.txHash },
          { delay: 12_000 }, // ~one Base block before the first finality check is worth attempting
        );
      } else {
        if (deps.config.slackWebhookUrl) {
          await notifySlack(deps.config.slackWebhookUrl, formatExecutionFailed(candidateId, result.reason)).catch(() => {});
        }
        await maybeRetry(deps, candidate.strategyId, candidate.stateVersion, candidate.retryCount);
      }
    },
    // ADR-0014's Queue rules: "Run one job at a time because one wallet owns all nonces."
    { connection: deps.queues.executeCandidate.opts.connection as IORedis, concurrency: 1 },
  );
}

function makeTrackTransactionWorker(deps: WorkerDeps): Worker<TrackTransactionJob> {
  return new Worker<TrackTransactionJob>(
    "track-transaction",
    async (job: Job<TrackTransactionJob>) => {
      const { executionAttemptId, txHash } = job.data;
      const status = await checkTransactionFinality(deps.db, deps.publicClient, executionAttemptId, deps.config.confirmationDepth);

      if (status === "pending") {
        await deps.queues.trackTransaction.add("track-transaction", job.data, { delay: 12_000 });
        return;
      }
      if (status === "final" && deps.config.slackWebhookUrl) {
        const attempt = await deps.db.query.executionAttempts.findFirst({
          where: (a, { eq: e }) => e(a.id, executionAttemptId),
        });
        const candidate = attempt
          ? await deps.db.query.candidates.findFirst({ where: (c, { eq: e }) => e(c.id, attempt.candidateId) })
          : undefined;
        if (candidate) {
          await notifySlack(
            deps.config.slackWebhookUrl,
            formatExecutionFinal(candidate.id, txHash, candidate.profitHeadroom, candidate.tokenIn),
          ).catch(() => {});
        }
      }
    },
    { connection: deps.queues.trackTransaction.opts.connection as IORedis },
  );
}

function makeRetryEvaluationWorker(deps: WorkerDeps): Worker<RetryEvaluationJob> {
  return new Worker<RetryEvaluationJob>(
    "retry-evaluation",
    async (job: Job<RetryEvaluationJob>) => {
      const { strategyId, stateVersion, retryCount } = job.data;
      await enqueueEvaluateStrategy(deps.queues, strategyId, stateVersion, retryCount);
    },
    { connection: deps.queues.retryEvaluation.opts.connection as IORedis },
  );
}

export interface Workers {
  syncIndexer: Worker;
  evaluateStrategy: Worker<EvaluateStrategyJob>;
  simulateCandidate: Worker<SimulateCandidateJob>;
  executeCandidate: Worker<ExecuteCandidateJob>;
  trackTransaction: Worker<TrackTransactionJob>;
  retryEvaluation: Worker<RetryEvaluationJob>;
}

/// Starts all six workers and schedules sync-indexer's own repeat. Every worker attaches a
/// `failed` listener that notifies Slack as a critical fault -- an uncaught error inside any
/// domain function is exactly what ADR-0014's Notification domain is for, not something that
/// should just vanish into BullMQ's own retry/backoff bookkeeping unnoticed.
export async function startWorkers(deps: WorkerDeps): Promise<Workers> {
  const workers: Workers = {
    syncIndexer: makeSyncIndexerWorker(deps),
    evaluateStrategy: makeEvaluateStrategyWorker(deps),
    simulateCandidate: makeSimulateCandidateWorker(deps),
    executeCandidate: makeExecuteCandidateWorker(deps),
    trackTransaction: makeTrackTransactionWorker(deps),
    retryEvaluation: makeRetryEvaluationWorker(deps),
  };

  for (const [name, worker] of Object.entries(workers)) {
    worker.on("failed", (job: Job | undefined, err: Error) => {
      void notifyCriticalFault(deps.config, `${name} (job ${job?.id ?? "unknown"})`, err);
    });
  }

  await deps.queues.syncIndexer.upsertJobScheduler("sync-indexer-repeat", { every: deps.config.syncIntervalMs });

  return workers;
}

export async function stopWorkers(workers: Workers): Promise<void> {
  await Promise.all(Object.values(workers).map((w) => w.close()));
}
