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

  fyndUrl: string;
  fyndChain: string;
  fyndSlippageBps: bigint;
  fyndMinResponses: number;
  fyndTimeoutMs: number;

  minTradeAmount: bigint;
  maxTradeAmount: bigint;
  searchSteps: number;
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

/// Comma-separated token addresses -- ADR-0014's Decision section: "The token allow list
/// contains USDC, USDT, WETH, and WBTC." Any strategy declaring a token outside this list is
/// recorded but not traded (Strategy Catalog's own eligibility check).
function requiredTokenList(name: string): Address[] {
  const tokens = required(name)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  if (tokens.length === 0) {
    throw new Error(`${name} must declare at least one token`);
  }
  return tokens as Address[];
}

export function loadConfig(): Config {
  const minTradeAmount = optionalBigInt("MIN_TRADE_AMOUNT", 10n ** 15n);
  const maxTradeAmount = optionalBigInt("MAX_TRADE_AMOUNT", 10n ** 19n);
  if (maxTradeAmount <= minTradeAmount) {
    throw new Error("MAX_TRADE_AMOUNT must be greater than MIN_TRADE_AMOUNT");
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

    allowedTokens: requiredTokenList("ALLOWED_TOKENS"),

    fyndUrl: required("FYND_URL"),
    fyndChain: optionalString("FYND_CHAIN", "base"),
    fyndSlippageBps: optionalBigInt("FYND_SLIPPAGE_BPS", 50n),
    fyndMinResponses: optionalInt("FYND_MIN_RESPONSES", 1),
    fyndTimeoutMs: optionalInt("FYND_TIMEOUT_MS", 5_000),

    minTradeAmount,
    maxTradeAmount,
    searchSteps: optionalInt("SEARCH_STEPS", 12),
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
