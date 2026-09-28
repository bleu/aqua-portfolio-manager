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
  return client.readContract({ address: token, abi: erc20Abi, functionName: "decimals" });
}

/// Reads `Arbitrageur.quoteExactIn` via `eth_call` -- no transaction, no gas spent, safe to call
/// on every search step.
export async function quoteExactIn(
  publicClient: PublicClient,
  arbitrageurAddress: Address,
  order: DecodedOrder,
  tokenIn: Address,
  tokenOut: Address,
  amountIn: bigint,
): Promise<bigint> {
  return publicClient.readContract({
    address: arbitrageurAddress,
    abi: arbitrageurAbi,
    functionName: "quoteExactIn",
    args: [order, tokenIn, tokenOut, amountIn],
  });
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
