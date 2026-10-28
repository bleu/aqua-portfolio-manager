"use client";

import { useReadContract } from "wagmi";
import { base } from "wagmi/chains";

const SAFE_THRESHOLD_ABI = [
  { type: "function", name: "getThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/** Reads the connected Safe's own multisig signature threshold -- "Signatures required" on the
 *  Review page. Every Safe exposes this via the same standard getThreshold() selector; a Base
 *  Wallet has no such concept (CoinbaseSmartWallet.sol's MultiOwnable lets any one owner sign
 *  alone, with no M-of-N threshold at all), so `enabled` should be false for that connection --
 *  calling it anyway would just revert every time, every render, against a real function that
 *  doesn't exist there. */
export function useSafeThreshold(safeAddress: `0x${string}` | undefined, enabled = true) {
  const { data, isLoading } = useReadContract({
    address: safeAddress,
    abi: SAFE_THRESHOLD_ABI,
    functionName: "getThreshold",
    chainId: base.id,
    query: { enabled: !!safeAddress && enabled },
  });

  return { threshold: data !== undefined ? Number(data) : undefined, isLoading };
}
