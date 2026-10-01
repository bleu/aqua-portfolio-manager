import { createPublicClient, createWalletClient, http, type Address, type Hex, type PublicClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrageurAbi, erc20Abi } from "./abi.js";
import type { Config } from "./config.js";
import type { DecodedOrder } from "./domains/orderDecoder.js";

export function makeClients(config: Config) {
  const account = privateKeyToAccount(config.privateKey);
  const transport = http(config.rpcUrl);

  const publicClient = createPublicClient({ transport });
  const walletClient = createWalletClient({ account, transport });

  return { account, publicClient, walletClient };
}

export async function tokenDecimals(client: PublicClient, token: Address): Promise<number> {
  return withRateLimitRetry(() => client.readContract({ address: token, abi: erc20Abi, functionName: "decimals" }));
}

/// Live balance, not the indexer's synced copy -- the curve itself prices off `balanceOf` at
/// quote time (PortfolioManagerSwap._groupValueWad), so a group-value computation meant to match
/// it reads the same real-time source, not a snapshot that can lag by a sync interval.
export async function tokenBalance(client: PublicClient, token: Address, owner: Address): Promise<bigint> {
  return withRateLimitRetry(() =>
    client.readContract({ address: token, abi: erc20Abi, functionName: "balanceOf", args: [owner] }),
  );
}

/// Base's public RPC returns a non-standard JSON-RPC error code (-32016, "over rate limit") for
/// throttling -- viem's own default retry logic only recognizes the standard codes (-32005,
/// -32603, 429), so it never retries this one on its own.
function isRateLimitError(err: unknown): boolean {
  return String(err).toLowerCase().includes("rate limit");
}

async function withRateLimitRetry<T>(fn: () => Promise<T>, tries = 3, delayMs = 500): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt >= tries - 1 || !isRateLimitError(err)) throw err;
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
}

/// Reads `Arbitrageur.quoteExactIn` via `eth_call` -- no transaction, no gas spent, safe to call
/// on every search step.
///
/// `account` matters, not just style: `runLoop` executes every instruction in the program for a
/// `quote()` call exactly like it does for a real `swap()`, so a resolver-KYC-gated strategy
/// (ADR-0015) checks `tx.origin` here too, not only at execution time (see
/// packages/contracts/test/e2e/ArbitrageurFlashE2E.t.sol). An `eth_call`'s own `from` field is
/// both msg.sender and tx.origin for that simulated call, so
/// omitting `account` here would make every quote against a gated strategy revert, not just
/// execution -- this isn't optional for gated strategies, even though it's inert for ungated ones.
export async function quoteExactIn(
  publicClient: PublicClient,
  account: ReturnType<typeof privateKeyToAccount>,
  arbitrageurAddress: Address,
  order: DecodedOrder,
  tokenIn: Address,
  tokenOut: Address,
  amountIn: bigint,
): Promise<bigint> {
  return withRateLimitRetry(() =>
    publicClient.readContract({
      address: arbitrageurAddress,
      account,
      abi: arbitrageurAbi,
      functionName: "quoteExactIn",
      args: [order, tokenIn, tokenOut, amountIn],
    }),
  );
}

export interface FlashArbParams {
  order: DecodedOrder;
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  minCurveAmountOut: bigint;
  fyndTarget: Address;
  fyndSpender: Address;
  fyndCalldata: Hex;
  deadline: number;
}

export interface FlashExecuteResult {
  txHash: Hex;
}

/// Transaction Simulation domain (ADR-0014): `eth_call`s `executeFlashArbitrage` without
/// submitting anything -- no gas spent, safe to run on every Candidate. Returns the exact
/// request `submitFlashArbitrage` below can replay, or throws (a revert reason from the real
/// contract, not a guess) if the Candidate wouldn't actually succeed right now.
export async function simulateFlashArbitrage(
  publicClient: PublicClient,
  account: ReturnType<typeof privateKeyToAccount>,
  arbitrageurAddress: Address,
  params: FlashArbParams,
) {
  const { request } = await publicClient.simulateContract({
    address: arbitrageurAddress,
    abi: arbitrageurAbi,
    functionName: "executeFlashArbitrage",
    args: [params],
    account,
  });
  return request;
}

/// Execution domain (ADR-0014): submits an already-simulated request and waits for it to be
/// mined. Split from simulation deliberately -- Transaction Simulation and Execution are
/// separate domains with separate queues (simulate-candidate, execute-candidate), and only
/// Execution's worker (concurrency 1, per the ADR's "one wallet owns all nonces" rule) should
/// ever actually submit.
export async function submitFlashArbitrage(
  walletClient: ReturnType<typeof makeClients>["walletClient"],
  publicClient: PublicClient,
  request: Awaited<ReturnType<typeof simulateFlashArbitrage>>,
): Promise<FlashExecuteResult> {
  const txHash = await walletClient.writeContract(request);
  await publicClient.waitForTransactionReceipt({ hash: txHash });
  return { txHash };
}
