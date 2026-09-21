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

/// Approves `spender` (the Arbitrageur contract) for `amount` of `token` if the owner's current
/// allowance is insufficient. A plain `approve(amount)`, not `approve(max)` -- this server only
/// ever needs an allowance for the specific trade size it's about to execute, and re-approving
/// per trade avoids leaving a standing unlimited allowance on a long-running EOA.
export async function ensureAllowance(
  clients: ReturnType<typeof makeClients>,
  token: Address,
  spender: Address,
  amount: bigint,
): Promise<void> {
  const { account, publicClient } = clients;
  const current = await publicClient.readContract({
    address: token,
    abi: erc20Abi,
    functionName: "allowance",
    args: [account.address, spender],
  });

  if (current >= amount) return;

  // Some tokens (USDT and similar) revert on changing a nonzero allowance directly to a
  // different nonzero value -- reset to zero first whenever there's an insufficient leftover
  // from a smaller previous trade.
  if (current > 0n) {
    await _approve(clients, token, spender, 0n);
  }
  await _approve(clients, token, spender, amount);
}

async function _approve(
  clients: ReturnType<typeof makeClients>,
  token: Address,
  spender: Address,
  amount: bigint,
): Promise<void> {
  const { account, publicClient, walletClient } = clients;
  const { request } = await publicClient.simulateContract({
    address: token,
    abi: erc20Abi,
    functionName: "approve",
    args: [spender, amount],
    account,
  });
  const txHash = await walletClient.writeContract(request);
  await publicClient.waitForTransactionReceipt({ hash: txHash });
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

export interface ExecuteResult {
  txHash: Hex;
  amountOut: bigint;
}

/// Submits the real `executeArbitrage` transaction and waits for it to be mined. Slippage and
/// deadline enforcement both happen on-chain (see Arbitrageur.sol's own doc comments) -- this
/// function does not re-validate either itself.
export async function executeArbitrage(
  clients: ReturnType<typeof makeClients>,
  arbitrageurAddress: Address,
  order: Order,
  tokenIn: Address,
  tokenOut: Address,
  amountIn: bigint,
  minAmountOut: bigint,
  deadline: number,
): Promise<ExecuteResult> {
  const { account, publicClient, walletClient } = clients;

  const { request, result } = await publicClient.simulateContract({
    address: arbitrageurAddress,
    abi: arbitrageurAbi,
    functionName: "executeArbitrage",
    args: [order, tokenIn, tokenOut, amountIn, minAmountOut, deadline],
    account,
  });

  const txHash = await walletClient.writeContract(request);
  await publicClient.waitForTransactionReceipt({ hash: txHash });

  return { txHash, amountOut: result };
}
