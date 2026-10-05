/// Single source of truth for the Base mainnet addresses this repo needs in more than one place.
/// The actual data lives in ../base-mainnet.json, shared with the Solidity side (read live via
/// vm.readFile/vm.parseJsonAddress in ShipStrategy.s.sol/Deploy.s.sol -- see that file's own
/// comment). This module just imports it and gives TS consumers a typed, validated shape.
import raw from "../base-mainnet.json" with { type: "json" };

export type Token = {
  symbol: string;
  address: string;
  feedPair: string;
  feedProxy: string;
  seedAggregator: string;
};

export const AQUA: string = raw.aqua;
export const MULTI_SEND_CALL_ONLY: string = raw.multiSendCallOnly;
export const MAX_STALENESS_SECONDS: number = raw.maxStalenessSeconds;

export const TOKENS: Token[] = Object.entries(raw.tokens).map(([symbol, t]) => ({ symbol, ...t }));

/// Each proxy's `aggregator()` result as of 2026-09-28 (see apps/indexer/config.yaml's
/// ChainlinkAggregator seed comment) -- covers EventHandlers.ts's AnswerUpdated handler for the
/// case where an aggregator's very first indexed event predates any ChainlinkAggregatorFeed row
/// for it (nothing has ever pointed an AggregatorConfirmed at it yet, because it was already the
/// live one at indexer setup).
export const SEED_AGGREGATOR_TO_PROXY: Record<string, string> = Object.fromEntries(
  TOKENS.map((t) => [t.seedAggregator.toLowerCase(), t.feedProxy.toLowerCase()]),
);

// TypeScript only checks these are strings, not that they're well-formed addresses or unique --
// catches a typo'd or duplicated entry here, at import time, for every consumer at once (the
// config-drift check and apps/indexer's own runtime import).
const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;
if (!ADDRESS_RE.test(AQUA)) throw new Error(`addresses: AQUA is not a well-formed address`);
if (!ADDRESS_RE.test(MULTI_SEND_CALL_ONLY)) {
  throw new Error(`addresses: MULTI_SEND_CALL_ONLY is not a well-formed address`);
}
const seenSymbols = new Set<string>();
for (const t of TOKENS) {
  if (seenSymbols.has(t.symbol)) throw new Error(`addresses: duplicate token symbol "${t.symbol}"`);
  seenSymbols.add(t.symbol);
  for (const [field, value] of [
    ["address", t.address],
    ["feedProxy", t.feedProxy],
    ["seedAggregator", t.seedAggregator],
  ] as const) {
    if (!ADDRESS_RE.test(value)) {
      throw new Error(`addresses: token "${t.symbol}"'s "${field}" is not a well-formed address`);
    }
  }
}
