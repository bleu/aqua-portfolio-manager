/**
 * One-time, off-chain pre-existing-strategy check for BasketScopeGuard onboarding (BLEUDEV-321).
 *
 * BasketScopeGuard (ADR-0011) only governs ship() calls made AFTER it's installed on a
 * Safe -- it has no way to see or undo strategies shipped before installation. Before
 * installing the Guard on a candidate Safe, this scans that Safe's shipping history and
 * refuses to proceed if any pre-existing strategy already violates the group boundary the
 * Guard is about to start enforcing.
 *
 * How a pre-existing strategy's declared tokens are reconstructed: Aqua's `Shipped` event
 * (see lib/aqua's IAqua.sol) does NOT carry the strategy's token list -- only
 * `(maker, app, strategyHash, strategy)`. But `ship()` also emits one `Pushed` event per
 * declared token, in the SAME transaction, during the same loop that sets each token's
 * initial balance. And `Aqua.ship()` enforces `StrategiesMustBeImmutable`: a given
 * (maker, app, strategyHash) can only ever be shipped once, so that one transaction's
 * `Pushed` events are the complete, permanent token set for that strategy -- not just a
 * snapshot. Reading them straight off that transaction's receipt is exact and cheap (one
 * receipt fetch, no separate log scan over a block range).
 *
 * None of Shipped/Pushed's params are `indexed` (checked directly against IAqua.sol),
 * so `eth_getLogs` can't topic-filter by maker -- every Shipped log in the scanned range
 * has to be fetched and decoded, then filtered client-side. Fine for this PoC's scope; a
 * production version serving many onboarding checks against a busy deployment would want
 * a real indexer (Envio HyperIndex, e.g. -- already used elsewhere at Bleu) instead of raw
 * eth_getLogs over a growing block range, same tradeoff the ENS marketplace project hit at
 * scale.
 */

import type { Address, Hex, PublicClient } from "viem";
import { decodeEventLog } from "viem";
import aquaArtifact from "./fixtures/aqua-artifact.json" with { type: "json" };

/** Deployment bytecode only, from the same compiled artifact -- see src/fixtures/README.md. */
export const AQUA_BYTECODE = aquaArtifact.bytecode as Hex;

/**
 * Hand-written, `as const`-typed ABI fragment for exactly what this tool calls/decodes,
 * checked directly against lib/aqua's IAqua.sol (ship, Shipped, Pushed). A JSON import
 * (like aqua-artifact.json's full `abi`) loses TypeScript's literal typing, which is what
 * gives viem precise argument/return inference -- writing this out explicitly is what
 * makes `decodeEventLog`/`writeContract` type-check the way they're used below, not a
 * stylistic choice.
 */
export const AQUA_ABI = [
  {
    type: "function",
    name: "ship",
    stateMutability: "nonpayable",
    inputs: [
      { name: "app", type: "address" },
      { name: "strategy", type: "bytes" },
      { name: "tokens", type: "address[]" },
      { name: "amounts", type: "uint256[]" },
    ],
    outputs: [{ name: "strategyHash", type: "bytes32" }],
  },
  {
    type: "event",
    name: "Shipped",
    inputs: [
      { name: "maker", type: "address", indexed: false },
      { name: "app", type: "address", indexed: false },
      { name: "strategyHash", type: "bytes32", indexed: false },
      { name: "strategy", type: "bytes", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Pushed",
    inputs: [
      { name: "maker", type: "address", indexed: false },
      { name: "app", type: "address", indexed: false },
      { name: "strategyHash", type: "bytes32", indexed: false },
      { name: "token", type: "address", indexed: false },
      { name: "amount", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
] as const;

export interface ShippedStrategy {
  maker: Address;
  app: Address;
  strategyHash: Hex;
  txHash: Hex;
  blockNumber: bigint;
}

export interface ReconstructedStrategy extends ShippedStrategy {
  tokens: Address[];
}

export type ViolationReason = "cross-group" | "outside-universe";

export interface Violation {
  strategy: ReconstructedStrategy;
  reason: ViolationReason;
  detail: string;
}

export interface OnboardingCheckResult {
  maker: Address;
  strategiesFound: number;
  violations: Violation[];
  compliant: boolean;
}

/** token address (lowercased) -> group id. A token missing from this map is "outside the declared universe". */
export type GroupConfig = Record<string, string>;

/**
 * Finds every Shipped event for `maker` against `aquaAddress`, in [fromBlock, toBlock].
 * Not indexed server-side (see module docstring) -- fetches every Shipped log in range and
 * decodes+filters client-side.
 */
export async function fetchShippedStrategies(
  client: PublicClient,
  aquaAddress: Address,
  maker: Address,
  fromBlock: bigint,
  toBlock: bigint,
): Promise<ShippedStrategy[]> {
  const shippedEventAbi = AQUA_ABI[1];
  const logs = await client.getLogs({
    address: aquaAddress,
    event: shippedEventAbi,
    fromBlock,
    toBlock,
    strict: true,
  });

  const makerLower = maker.toLowerCase();
  return logs
    .filter((log) => log.args.maker.toLowerCase() === makerLower)
    .map((log) => ({
      maker: log.args.maker,
      app: log.args.app,
      strategyHash: log.args.strategyHash,
      txHash: log.transactionHash!,
      blockNumber: log.blockNumber!,
    }));
}

/**
 * Reconstructs a shipped strategy's declared token set from the Pushed events emitted in
 * its own ship() transaction. Exact, not a snapshot -- see module docstring for why.
 */
export async function reconstructDeclaredTokens(
  client: PublicClient,
  aquaAddress: Address,
  strategy: ShippedStrategy,
): Promise<ReconstructedStrategy> {
  const receipt = await client.getTransactionReceipt({ hash: strategy.txHash });
  const aquaAddressLower = aquaAddress.toLowerCase();

  const tokens: Address[] = [];
  for (const log of receipt.logs) {
    if (log.address.toLowerCase() !== aquaAddressLower) continue;
    let decoded;
    try {
      decoded = decodeEventLog({ abi: AQUA_ABI, data: log.data, topics: log.topics });
    } catch {
      continue; // not a Pushed log (or not decodable against this ABI) -- skip
    }
    if (decoded.eventName !== "Pushed") continue;
    const { maker, app, strategyHash, token } = decoded.args;
    if (
      maker.toLowerCase() === strategy.maker.toLowerCase() &&
      app.toLowerCase() === strategy.app.toLowerCase() &&
      strategyHash.toLowerCase() === strategy.strategyHash.toLowerCase()
    ) {
      tokens.push(token);
    }
  }

  return { ...strategy, tokens };
}

/**
 * Classifies one reconstructed strategy against the candidate group config, mirroring
 * BasketScopeGuard.sol's own on-chain rule exactly: PM's own trusted strategy hash is
 * always allowed (it's the mechanism meant to price across groups); any other strategy
 * must keep every declared token inside a single group, and every token must belong to
 * some declared group.
 */
export function classifyStrategy(
  strategy: ReconstructedStrategy,
  groupConfig: GroupConfig,
  trustedStrategyHash: Hex,
): Violation | null {
  if (strategy.strategyHash.toLowerCase() === trustedStrategyHash.toLowerCase()) {
    return null; // PM's own strategy -- always allowed, same as the on-chain Guard
  }

  const groupsTouched = new Set<string>();
  for (const token of strategy.tokens) {
    const group = groupConfig[token.toLowerCase()];
    if (group === undefined) {
      return {
        strategy,
        reason: "outside-universe",
        detail: `token ${token} is not in the declared universe`,
      };
    }
    groupsTouched.add(group);
  }

  if (groupsTouched.size > 1) {
    return {
      strategy,
      reason: "cross-group",
      detail: `strategy ${strategy.strategyHash} touches ${groupsTouched.size} groups: ${[...groupsTouched].join(", ")}`,
    };
  }

  return null;
}

/**
 * Top-level check: scan `maker`'s shipping history and refuse (return `compliant: false`)
 * if any pre-existing strategy already violates the group boundary the Guard is about to
 * enforce. Run this once, before installing BasketScopeGuard on a candidate Safe.
 */
export async function checkOnboarding(
  client: PublicClient,
  aquaAddress: Address,
  maker: Address,
  groupConfig: GroupConfig,
  trustedStrategyHash: Hex,
  fromBlock: bigint,
  toBlock: bigint,
): Promise<OnboardingCheckResult> {
  const shipped = await fetchShippedStrategies(client, aquaAddress, maker, fromBlock, toBlock);
  const violations: Violation[] = [];

  for (const strategy of shipped) {
    const reconstructed = await reconstructDeclaredTokens(client, aquaAddress, strategy);
    const violation = classifyStrategy(reconstructed, groupConfig, trustedStrategyHash);
    if (violation) violations.push(violation);
  }

  return {
    maker,
    strategiesFound: shipped.length,
    violations,
    compliant: violations.length === 0,
  };
}
