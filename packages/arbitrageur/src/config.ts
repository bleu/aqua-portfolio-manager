import type { Address, Hex } from "viem";

export interface Order {
  maker: Address;
  traits: bigint;
  data: Hex;
}

export interface TokenFeed {
  token: Address;
  feed: Address;
}

export interface Config {
  rpcUrl: string;
  privateKey: Hex;
  arbitrageurAddress: Address;
  order: Order;
  groupA: TokenFeed[];
  groupB: TokenFeed[];
  fyndUrl: string;
  fyndChain: string;
  fyndSlippageBps: bigint;
  blockPollingIntervalMs: number;
  minProfitBps: bigint;
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

/// Order fields are supplied as three separate env vars rather than one JSON blob so each is
/// independently required/typed -- an LP's shipped strategy is immutable and opaque calldata
/// (maker address, packed traits, program bytes), not something this server reconstructs itself.
/// See docs/guides/ for how an LP ships a strategy in the first place.
export function loadConfig(): Config {
  const order: Order = {
    maker: required("PM_ORDER_MAKER") as Address,
    traits: BigInt(required("PM_ORDER_TRAITS")),
    data: required("PM_ORDER_DATA") as Hex,
  };

  const minTradeAmount = optionalBigInt("MIN_TRADE_AMOUNT", 10n ** 15n);
  const maxTradeAmount = optionalBigInt("MAX_TRADE_AMOUNT", 10n ** 19n);
  if (maxTradeAmount <= minTradeAmount) {
    throw new Error("MAX_TRADE_AMOUNT must be greater than MIN_TRADE_AMOUNT");
  }

  return {
    rpcUrl: required("RPC_URL"),
    privateKey: required("PRIVATE_KEY") as Hex,
    arbitrageurAddress: required("ARBITRAGEUR_ADDRESS") as Address,
    order,
    groupA: requiredGroup("GROUP_A_TOKENS", "GROUP_A_FEEDS"),
    groupB: requiredGroup("GROUP_B_TOKENS", "GROUP_B_FEEDS"),
    fyndUrl: required("FYND_URL"),
    fyndChain: optionalString("FYND_CHAIN", "base"),
    fyndSlippageBps: optionalBigInt("FYND_SLIPPAGE_BPS", 50n),
    blockPollingIntervalMs: optionalInt("BLOCK_POLLING_INTERVAL_MS", 2_000),
    minProfitBps: optionalBigInt("MIN_PROFIT_BPS", 20n),
    minTradeAmount,
    maxTradeAmount,
    searchSteps: optionalInt("SEARCH_STEPS", 12),
    deadlineBufferSeconds: optionalInt("DEADLINE_BUFFER_SECONDS", 60),
    slippageBufferBps: optionalBigInt("SLIPPAGE_BUFFER_BPS", 50n),
    dryRun: process.env.DRY_RUN === "true",
  };
}
