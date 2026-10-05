/// Single source of truth for the Base mainnet addresses this repo needs in more than one place.
/// Solidity still needs a generated constants file since it can't import TS (see
/// scripts/generate-solidity.ts), but every TS consumer imports this package directly.
export type Token = {
  symbol: string;
  address: string;
  feedPair: string;
  feedProxy: string;
  seedAggregator: string;
};

export const AQUA = "0x499943E74FB0cE105688beeE8Ef2ABec5D936d31";
export const MULTI_SEND_CALL_ONLY = "0x9641d764fc13c8B624c04430C7356C1C7C8102e2";
export const MAX_STALENESS_SECONDS = 43200;

export const TOKENS: Token[] = [
  {
    symbol: "WETH",
    address: "0x4200000000000000000000000000000000000006",
    feedPair: "ETH/USD",
    feedProxy: "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70",
    seedAggregator: "0x05c84a58FE042275b37db038bAAcD15F410c7bB0",
  },
  {
    symbol: "CBBTC",
    address: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
    feedPair: "cbBTC/USD",
    feedProxy: "0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D",
    seedAggregator: "0x51cE3091Cf646587E02Cad83b580992f8723e718",
  },
  {
    symbol: "USDC",
    address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    feedPair: "USDC/USD",
    feedProxy: "0x7e860098F58bBFC8648a4311b374B1D669a2bc6B",
    seedAggregator: "0x68bE4C50235205Ede361ac8244B1ee221CDDA5E2",
  },
  {
    symbol: "USDT",
    address: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",
    feedPair: "USDT/USD",
    feedProxy: "0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9",
    seedAggregator: "0x84640bB7b71B0963E8EB57AD379A0B204eb2fdc8",
  },
];

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
// Solidity generator, the config-drift check, and apps/indexer's own runtime import).
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
