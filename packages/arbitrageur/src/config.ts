import type { Address, Hex } from "viem";

export interface Order {
  maker: Address;
  traits: bigint;
  data: Hex;
}

export interface Config {
  rpcUrl: string;
  privateKey: Hex;
  arbitrageurAddress: Address;
  order: Order;
  tokenIn: Address;
  tokenOut: Address;
  feedIn: Address;
  feedOut: Address;
  pollIntervalMs: number;
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
    tokenIn: required("TOKEN_IN") as Address,
    tokenOut: required("TOKEN_OUT") as Address,
    feedIn: required("FEED_IN") as Address,
    feedOut: required("FEED_OUT") as Address,
    pollIntervalMs: optionalInt("POLL_INTERVAL_MS", 15_000),
    minProfitBps: optionalBigInt("MIN_PROFIT_BPS", 20n),
    minTradeAmount,
    maxTradeAmount,
    searchSteps: optionalInt("SEARCH_STEPS", 12),
    deadlineBufferSeconds: optionalInt("DEADLINE_BUFFER_SECONDS", 60),
    slippageBufferBps: optionalBigInt("SLIPPAGE_BUFFER_BPS", 50n),
    dryRun: process.env.DRY_RUN === "true",
  };
}
