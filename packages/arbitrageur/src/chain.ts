import { createPublicClient, createWalletClient, http, type Address, type Hex, type PublicClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrageurAbi, erc20Abi } from "./abi.js";
import type { Config, Order } from "./config.js";

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
  order: Order,
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
  order: Order;
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

/// Submits `executeFlashArbitrage` and waits for it to be mined -- this never touches the owner
/// EOA's own token balance or allowances: the traded token is borrowed and repaid entirely
/// inside the one transaction, on-chain (see Arbitrageur.sol's own doc comments on
/// `receiveFlashLoan`). No TS wrapper for the contract's self-funded `executeArbitrage`: the
/// bot's loop runs exclusively via this flash-loan path.
export async function executeFlashArbitrage(
  clients: ReturnType<typeof makeClients>,
  arbitrageurAddress: Address,
  params: FlashArbParams,
): Promise<FlashExecuteResult> {
  const { account, publicClient, walletClient } = clients;

  const { request } = await publicClient.simulateContract({
    address: arbitrageurAddress,
    abi: arbitrageurAbi,
    functionName: "executeFlashArbitrage",
    args: [params],
    account,
  });

  const txHash = await walletClient.writeContract(request);
  await publicClient.waitForTransactionReceipt({ hash: txHash });

  return { txHash };
}
