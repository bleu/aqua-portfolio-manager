import { eq } from "drizzle-orm";
import type { Address, Hex } from "viem";
import type { Db } from "../db/client.js";
import { strategies, type StrategyRow } from "../db/schema.js";
import { decodeProgram, ProgramDecodeError } from "./programDecoder.js";
import { decodeOrder, extractProgram } from "./orderDecoder.js";

export interface EligibilityResult {
  eligible: boolean;
  reason: string | undefined;
}

/// A Strategy is eligible only if every declared token is on the allow list -- ADR-0014's
/// Decision section: "The service records unsupported Strategies but does not trade them."
/// Reasons are short and machine-readable (matched by exact string elsewhere, e.g. the
/// Operations API), not prose.
export function evaluateEligibility(
  decoded: { groups: { members: { token: Address }[] }[] },
  allowedTokens: ReadonlySet<Address>,
): EligibilityResult {
  const tokens = decoded.groups.flatMap((g) => g.members.map((m) => m.token.toLowerCase() as Address));
  const unsupported = [...new Set(tokens.filter((t) => !allowedTokens.has(t)))];
  if (unsupported.length > 0) {
    return { eligible: false, reason: `unsupported-token:${unsupported.join(",")}` };
  }
  return { eligible: true, reason: undefined };
}

/// Strategy Catalog domain: decodes one Strategy row's `encodedOrder` (the ABI-encoded Order --
/// see src/domains/orderDecoder.ts for why that's not the bare program bytes) down to its
/// program, and writes back the resolver KYC token (if gated, per ADR-0015) and eligibility
/// reason (if any). Idempotent -- safe to re-run for a Strategy whose order hasn't changed (it
/// can't: Aqua strategies are immutable once shipped), so a re-run after a crash just recomputes
/// the same result.
export async function evaluateStrategyCatalog(
  db: Db,
  strategy: StrategyRow,
  allowedTokens: ReadonlySet<Address>,
): Promise<void> {
  try {
    const order = decodeOrder(strategy.encodedOrder as Hex);
    const program = extractProgram(order.traits, order.data);
    const decoded = decodeProgram(program);
    const { reason } = evaluateEligibility(decoded, allowedTokens);
    await db
      .update(strategies)
      .set({ resolverKycToken: decoded.resolverKycToken ?? null, ineligibilityReason: reason ?? null })
      .where(eq(strategies.id, strategy.id));
  } catch (err) {
    // A malformed order/program should be structurally impossible for anything actually
    // reachable from `Shipped` (PortfolioManagerStrategyValidator.attestBuildParameters gates
    // real trading, per ADR-0013) -- but the indexer mirrors every Shipped event regardless of
    // whether it was ever attested, so this path is real, not defensive dead code. ADR-0014's own
    // rule: "stays in the catalog with an eligibility reason. It cannot create a Candidate."
    const message = err instanceof ProgramDecodeError ? err.message : err instanceof Error ? err.message : "unknown";
    const reason = `decode-failed:${message}`;
    await db.update(strategies).set({ ineligibilityReason: reason }).where(eq(strategies.id, strategy.id));
  }
}

/// Recomputes every Strategy's eligibility on every call -- wasteful once the catalog is large,
/// since a Strategy's program (and so its eligibility) never changes after Shipped. Matches
/// syncStrategies' own full-rescan tradeoff (src/sync/indexer.ts): correct and simple at today's
/// scale, a real follow-up (skip rows already evaluated) once the catalog grows enough to matter.
export async function evaluateAllStrategyCatalog(db: Db, allowedTokens: ReadonlySet<Address>): Promise<number> {
  const rows = await db.query.strategies.findMany();
  await Promise.all(rows.map((row) => evaluateStrategyCatalog(db, row, allowedTokens)));
  return rows.length;
}
