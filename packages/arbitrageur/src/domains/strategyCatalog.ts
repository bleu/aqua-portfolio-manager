import { eq } from "drizzle-orm";
import type { Address, Hex } from "viem";
import type { Db } from "../db/client.js";
import { strategies, type StrategyRow } from "../db/schema.js";
import { decodeProgram, ProgramDecodeError, decodeOrder, extractProgram } from "@aqua-portfolio-manager/decoding";

export interface EligibilityResult {
  eligible: boolean;
  reason: string | undefined;
}

/// A Strategy is eligible only if every declared token AND every declared feed is on its own
/// allow list -- ADR-0014's Decision section: "The service records unsupported Strategies but
/// does not trade them," extended to feeds so a strategy can't pair a real allowed token with an
/// attacker-controlled feed address. Reasons are short and machine-readable (matched by exact
/// string elsewhere, e.g. the Operations API), not prose.
export function evaluateEligibility(
  decoded: { groups: { members: { token: Address; feed: Address }[] }[] },
  allowedTokens: ReadonlySet<Address>,
  allowedFeeds: ReadonlySet<Address>,
): EligibilityResult {
  const members = decoded.groups.flatMap((g) => g.members);

  const tokens = members.map((m) => m.token.toLowerCase() as Address);
  const unsupportedTokens = [...new Set(tokens.filter((t) => !allowedTokens.has(t)))];
  if (unsupportedTokens.length > 0) {
    return { eligible: false, reason: `unsupported-token:${unsupportedTokens.join(",")}` };
  }

  const feeds = members.map((m) => m.feed.toLowerCase() as Address);
  const unsupportedFeeds = [...new Set(feeds.filter((f) => !allowedFeeds.has(f)))];
  if (unsupportedFeeds.length > 0) {
    return { eligible: false, reason: `unsupported-feed:${unsupportedFeeds.join(",")}` };
  }

  return { eligible: true, reason: undefined };
}

/// Strategy Catalog domain: decodes one Strategy row's `encodedOrder` (the ABI-encoded Order --
/// see @aqua-portfolio-manager/decoding's orderDecoder.ts for why that's not the bare program
/// bytes) down to its program, and writes back the resolver KYC token (if gated, per ADR-0015)
/// and eligibility reason (if any). Idempotent -- safe to re-run for a Strategy whose order
/// hasn't changed (it can't: Aqua strategies are immutable once shipped), so a re-run after a
/// crash just recomputes the same result.
export async function evaluateStrategyCatalog(
  db: Db,
  strategy: StrategyRow,
  allowedTokens: ReadonlySet<Address>,
  allowedFeeds: ReadonlySet<Address>,
): Promise<void> {
  try {
    const order = decodeOrder(strategy.encodedOrder as Hex);
    const program = extractProgram(order.traits, order.data);
    const decoded = decodeProgram(program);
    const { reason } = evaluateEligibility(decoded, allowedTokens, allowedFeeds);
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
export async function evaluateAllStrategyCatalog(
  db: Db,
  allowedTokens: ReadonlySet<Address>,
  allowedFeeds: ReadonlySet<Address>,
): Promise<number> {
  const rows = await db.query.strategies.findMany();
  await Promise.all(rows.map((row) => evaluateStrategyCatalog(db, row, allowedTokens, allowedFeeds)));
  return rows.length;
}
