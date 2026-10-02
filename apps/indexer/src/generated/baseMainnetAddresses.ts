// GENERATED FILE -- do not edit by hand.
// Regenerate from packages/addresses/base-mainnet.json via
// `pnpm --filter @aqua-portfolio-manager/addresses generate`.

// Each proxy's `aggregator()` result as of 2026-09-28 (see config.yaml's ChainlinkAggregator
// seed comment) -- covers the AnswerUpdated handler for the case where an aggregator's very
// first indexed event predates any ChainlinkAggregatorFeed row for it (nothing has ever pointed
// an AggregatorConfirmed at it yet, because it was already the live one at indexer setup).
export const SEED_AGGREGATOR_TO_PROXY: Record<string, string> = {
  "0x05c84a58fe042275b37db038baacd15f410c7bb0": "0x71041dddad3595f9ced3dccfbe3d1f4b0a16bb70", // ETH/USD
  "0x51ce3091cf646587e02cad83b580992f8723e718": "0x07da0e54543a844a80abe69c8a12f22b3aa59f9d", // cbBTC/USD
  "0x84640bb7b71b0963e8eb57ad379a0b204eb2fdc8": "0xf19d560eb8d2adf07bd6d13ed03e1d11215721f9", // USDT/USD
  "0x68be4c50235205ede361ac8244b1ee221cdda5e2": "0x7e860098f58bbfc8648a4311b374b1d669a2bc6b", // USDC/USD
};
