import { readFileSync } from "node:fs";
import { parseUnits, type Address, type Hex } from "viem";

export interface Order {
  maker: Address;
  traits: bigint;
  data: Hex;
}

export interface TokenFeed {
  token: Address;
  feed: Address;
}

/// One PM strategy this bot watches: its own order (opaque, immutable calldata) and its own
/// two-group basket. `arbitrageurAddress`/`privateKey`/etc. stay global on `Config` -- one bot
/// process, one contract, one EOA, watching however many strategies are declared here.
export interface Strategy {
  order: Order;
  groupA: TokenFeed[];
  groupB: TokenFeed[];
}

export interface Config {
  rpcUrl: string;
  privateKey: Hex;
  arbitrageurAddress: Address;
  strategies: Strategy[];
  fyndUrl: string;
  fyndChain: string;
  fyndSlippageBps: bigint;
  blockPollingIntervalMs: number;
  minProfitUsdWad: bigint;
  minTradeAmount: bigint;
  maxTradeAmount: bigint;
  searchSteps: number;
  deadlineBufferSeconds: number;
  slippageBufferBps: bigint;
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

/// A group is a comma-separated token-address list plus a positionally-matched comma-separated
/// feed-address list -- e.g. `GROUP_A_TOKENS=USDT,USDC` / `GROUP_A_FEEDS=USDT/USD,USDC/USD`.
/// Mirrors the PM strategy's own declared universe (`PortfolioManagerArgsCodec.Group`): each
/// group's members are only ever traded against the *other* group's members, never against each
/// other (see `PortfolioManagerSwap._resolve`'s `groupInIdx != groupOutIdx` check).
function requiredGroup(tokensVar: string, feedsVar: string): TokenFeed[] {
  const tokens = required(tokensVar)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const feeds = required(feedsVar)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  if (tokens.length === 0) {
    throw new Error(`${tokensVar} must declare at least one token`);
  }
  if (tokens.length !== feeds.length) {
    throw new Error(`${tokensVar} and ${feedsVar} must have the same length (positionally matched)`);
  }

  return tokens.map((token, i) => ({ token: token as Address, feed: feeds[i] as Address }));
}

function asRecord(raw: unknown, path: string): Record<string, unknown> {
  if (typeof raw !== "object" || raw === null) {
    throw new Error(`${path} must be an object`);
  }
  return raw as Record<string, unknown>;
}

function parseGroup(raw: unknown, path: string): TokenFeed[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new Error(`${path} must be a non-empty array`);
  }
  return raw.map((entry, i) => {
    const rec = asRecord(entry, `${path}[${i}]`);
    if (typeof rec.token !== "string" || typeof rec.feed !== "string") {
      throw new Error(`${path}[${i}] must be {"token": "0x...", "feed": "0x..."}`);
    }
    return { token: rec.token as Address, feed: rec.feed as Address };
  });
}

/// Parses a `STRATEGIES_FILE`'s already-`JSON.parse`d contents -- pulled out of
/// `loadStrategiesFromFile` so it's testable without touching the filesystem.
export function parseStrategies(raw: unknown): Strategy[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new Error("STRATEGIES_FILE must contain a non-empty JSON array of strategies");
  }
  return raw.map((entry, i) => {
    const path = `strategies[${i}]`;
    const { orderMaker, orderTraits, orderData, groupA, groupB } = asRecord(entry, path);
    if (typeof orderMaker !== "string" || typeof orderTraits !== "string" || typeof orderData !== "string") {
      throw new Error(`${path} must declare orderMaker/orderTraits/orderData as strings`);
    }
    return {
      order: { maker: orderMaker as Address, traits: BigInt(orderTraits), data: orderData as Hex },
      groupA: parseGroup(groupA, `${path}.groupA`),
      groupB: parseGroup(groupB, `${path}.groupB`),
    };
  });
}

function loadStrategiesFromFile(path: string): Strategy[] {
  return parseStrategies(JSON.parse(readFileSync(path, "utf-8")));
}

/// Two ways to declare what this bot watches: a `STRATEGIES_FILE` JSON array (see
/// `parseStrategies`) for any number of strategies, or -- for local single-strategy testing,
/// matching how the E2E fixtures and existing docs are already set up -- the original inline
/// `PM_ORDER_*`/`GROUP_*_*` env vars, wrapped as a one-strategy list. Order fields are three
/// separate values rather than one blob so each is independently typed -- an LP's shipped
/// strategy is opaque, immutable calldata, not something this server reconstructs itself. See
/// docs/guides/ for how an LP ships a strategy in the first place.
function loadStrategies(): Strategy[] {
  const strategiesFile = process.env.STRATEGIES_FILE;
  if (strategiesFile) {
    return loadStrategiesFromFile(strategiesFile);
  }

  const order: Order = {
    maker: required("PM_ORDER_MAKER") as Address,
    traits: BigInt(required("PM_ORDER_TRAITS")),
    data: required("PM_ORDER_DATA") as Hex,
  };
  return [
    {
      order,
      groupA: requiredGroup("GROUP_A_TOKENS", "GROUP_A_FEEDS"),
      groupB: requiredGroup("GROUP_B_TOKENS", "GROUP_B_FEEDS"),
    },
  ];
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
    strategies: loadStrategies(),
    fyndUrl: required("FYND_URL"),
    fyndChain: optionalString("FYND_CHAIN", "base"),
    fyndSlippageBps: optionalBigInt("FYND_SLIPPAGE_BPS", 50n),
    blockPollingIntervalMs: optionalInt("BLOCK_POLLING_INTERVAL_MS", 2_000),
    minProfitUsdWad: parseUnits(optionalString("MIN_PROFIT_USD", "5"), 18),
    minTradeAmount,
    maxTradeAmount,
    searchSteps: optionalInt("SEARCH_STEPS", 12),
    deadlineBufferSeconds: optionalInt("DEADLINE_BUFFER_SECONDS", 60),
    slippageBufferBps: optionalBigInt("SLIPPAGE_BUFFER_BPS", 50n),
    dryRun: process.env.DRY_RUN === "true",
  };
}
