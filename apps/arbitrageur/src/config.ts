import { parseUnits, type Address, type Hex } from "viem";

export interface Config {
  rpcUrl: string;
  privateKey: Hex;
  arbitrageurAddress: Address;
  executorVersion: string;

  databaseUrl: string;
  redisUrl: string;

  indexerGraphqlUrl: string;
  indexerAdminSecret: string | undefined;

  allowedTokens: Address[];
  allowedFeeds: Address[];

  fyndUrl: string;
  fyndChain: string;
  fyndSlippageBps: bigint;
  fyndMinResponses: number;
  fyndTimeoutMs: number;

  minTradeUsdWad: bigint;
  maxTradeUsdWad: bigint;
  minProfitUsdWad: bigint;
  maxPriceStalenessSeconds: bigint;
  slippageBufferBps: bigint;
  deadlineBufferSeconds: number;

  confirmationDepth: number;
  maxRetries: number;
  syncIntervalMs: number;
  recoveryIntervalMs: number;

  slackWebhookUrl: string | undefined;

  operationsApiPort: number;
  operationsApiToken: string;

  dryRun: boolean;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var ${name} -- see .env.example`);
  }
  return value;
}

function optionalBigInt(name: string, fallback: bigint): bigint {
  const value = process.env[name];
  return value ? BigInt(value) : fallback;
}

function optionalInt(name: string, fallback: number): number {
  const value = process.env[name];
  return value ? Number.parseInt(value, 10) : fallback;
}

function optionalString(name: string, fallback: string): string {
  return process.env[name] ?? fallback;
}

/// Comma-separated addresses, lowercased so every consumer (Strategy Catalog's eligibility check
/// in particular, which already lowercases a strategy's own declared tokens/feeds) compares
/// consistently -- an address with no hex letters (like WETH's) survives a checksum-case mismatch
/// by luck; every other one silently fails a case-sensitive Set membership check otherwise.
function requiredAddressList(name: string): Address[] {
  const addresses = required(name)
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  if (addresses.length === 0) {
    throw new Error(`${name} must declare at least one address`);
  }
  return addresses as Address[];
}

export function loadConfig(): Config {
  // USD-denominated, not a raw token-unit amount -- a fixed raw-unit bound can't sensibly apply
  // to every leg's trade size when the basket spans tokens with different decimals (18 for WETH,
  // 8 for cbBTC, 6 for USDC/USDT); each leg converts against its own oracle price at evaluation
  // time (see pricing.ts's amountForUsdWad). The in-given-price formula computes the exact
  // optimal trade size directly, not a range to search -- these two bounds now gate that result
  // instead of scoping a search: MIN_TRADE_USD skips an optimum too small to be worth a quote and
  // gas, MAX_TRADE_USD caps risk per trade even when the curve math says a bigger one would be
  // more profitable still.
  const minTradeUsdWad = parseUnits(optionalString("MIN_TRADE_USD", "1"), 18);
  const maxTradeUsdWad = parseUnits(optionalString("MAX_TRADE_USD", "1000"), 18);
  if (maxTradeUsdWad <= minTradeUsdWad) {
    throw new Error("MAX_TRADE_USD must be greater than MIN_TRADE_USD");
  }

  return {
    rpcUrl: required("RPC_URL"),
    privateKey: required("PRIVATE_KEY") as Hex,
    arbitrageurAddress: required("ARBITRAGEUR_ADDRESS") as Address,
    executorVersion: optionalString("EXECUTOR_VERSION", "v1"),

    databaseUrl: required("DATABASE_URL"),
    redisUrl: required("REDIS_URL"),

    indexerGraphqlUrl: required("INDEXER_GRAPHQL_URL"),
    indexerAdminSecret: process.env.INDEXER_ADMIN_SECRET,

    // ADR-0014's Decision section: "The token allow list contains USDC, USDT, WETH, and WBTC"
    // (cbBTC replaces WBTC here -- more liquid on Base). Any strategy declaring a token outside
    // this list is recorded but not traded (Strategy Catalog's own eligibility check).
    allowedTokens: requiredAddressList("ALLOWED_TOKENS"),
    // Defense in depth against a strategy declaring a real allowed token with an
    // attacker-controlled feed address. Must match apps/indexer/config.yaml's ChainlinkProxy
    // list exactly.
    allowedFeeds: requiredAddressList("ALLOWED_FEEDS"),

    fyndUrl: required("FYND_URL"),
    fyndChain: optionalString("FYND_CHAIN", "base"),
    fyndSlippageBps: optionalBigInt("FYND_SLIPPAGE_BPS", 50n),
    fyndMinResponses: optionalInt("FYND_MIN_RESPONSES", 1),
    fyndTimeoutMs: optionalInt("FYND_TIMEOUT_MS", 5_000),

    minTradeUsdWad,
    maxTradeUsdWad,
    minProfitUsdWad: parseUnits(optionalString("MIN_PROFIT_USD", "5"), 18),
    maxPriceStalenessSeconds: optionalBigInt("MAX_PRICE_STALENESS_SECONDS", 3600n),
    slippageBufferBps: optionalBigInt("SLIPPAGE_BUFFER_BPS", 50n),
    deadlineBufferSeconds: optionalInt("DEADLINE_BUFFER_SECONDS", 60),

    confirmationDepth: optionalInt("CONFIRMATION_DEPTH", 5),
    maxRetries: optionalInt("MAX_RETRIES", 3), // ADR-0014: "allows three retries for one Strategy State"
    syncIntervalMs: optionalInt("SYNC_INTERVAL_MS", 5_000),
    recoveryIntervalMs: optionalInt("RECOVERY_INTERVAL_MS", 60_000),

    slackWebhookUrl: process.env.SLACK_WEBHOOK_URL,

    operationsApiPort: optionalInt("OPERATIONS_API_PORT", 3_001), // not 3000: Fynd's own local server default
    operationsApiToken: required("OPERATIONS_API_TOKEN"),

    dryRun: process.env.DRY_RUN === "true",
  };
}
