import { eq } from "drizzle-orm";
import type { Address, Hex, PublicClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { Db } from "../db/client.js";
import { strategies, candidates } from "../db/schema.js";
import { decodeOrder } from "@aqua-portfolio-manager/decoding";
import { simulateFlashArbitrage, type FlashArbParams } from "../chain.js";

export interface BuiltFlashArbParams {
  params: FlashArbParams;
}

/// Rebuilds the exact on-chain call a Candidate represents, from durable Postgres state -- not
/// from anything passed between queue jobs. `simulate-candidate` and `execute-candidate` both
/// call this fresh (see execution.ts's own doc comment for why execute-candidate re-simulates
/// instead of reusing simulate-candidate's result), so a Candidate row plus its Strategy row is
/// the single source of truth, not a `request` object serialized through Redis.
export async function buildFlashArbParams(db: Db, candidateId: string): Promise<BuiltFlashArbParams | undefined> {
  const candidate = await db.query.candidates.findFirst({ where: eq(candidates.id, candidateId) });
  if (!candidate) return undefined;
  const strategy = await db.query.strategies.findFirst({ where: eq(strategies.id, candidate.strategyId) });
  if (!strategy) return undefined;

  const order = decodeOrder(strategy.encodedOrder as Hex);
  return {
    params: {
      order,
      tokenIn: candidate.tokenIn as Address,
      tokenOut: candidate.tokenOut as Address,
      amountIn: candidate.amountIn,
      minCurveAmountOut: candidate.minCurveAmountOut,
      fyndTarget: candidate.fyndTarget as Address,
      fyndSpender: candidate.fyndSpender as Address,
      fyndCalldata: candidate.fyndCalldata as Hex,
      deadline: Number(candidate.deadline),
    },
  };
}

export type SimulationResult = { ok: true } | { ok: false; reason: string };

/// Transaction Simulation domain (ADR-0014): validates a Candidate with a real `eth_call`
/// (src/chain.ts's simulateFlashArbitrage) before it's ever allowed into the execute-candidate
/// queue, and records the outcome on the Candidate row either way.
export async function simulateCandidate(
  db: Db,
  publicClient: PublicClient,
  account: ReturnType<typeof privateKeyToAccount>,
  arbitrageurAddress: Address,
  candidateId: string,
): Promise<SimulationResult> {
  const built = await buildFlashArbParams(db, candidateId);
  if (!built) return { ok: false, reason: "candidate-or-strategy-not-found" };

  try {
    await simulateFlashArbitrage(publicClient, account, arbitrageurAddress, built.params);
    await db.update(candidates).set({ status: "simulated" }).where(eq(candidates.id, candidateId));
    return { ok: true };
  } catch (err) {
    const reason = err instanceof Error ? err.message : "unknown";
    await db
      .update(candidates)
      .set({ status: "simulation_failed", rejectionReason: reason })
      .where(eq(candidates.id, candidateId));
    return { ok: false, reason };
  }
}
