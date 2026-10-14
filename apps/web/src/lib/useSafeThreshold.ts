"use client";

import { useReadContract } from "wagmi";
import { base } from "wagmi/chains";

const SAFE_THRESHOLD_ABI = [
  { type: "function", name: "getThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/** Reads the connected Safe's own multisig signature threshold -- "Signatures required" on the
 *  Review page. Every Safe exposes this via the same standard getThreshold() selector. */
export function useSafeThreshold(safeAddress: `0x${string}` | undefined) {
  const { data, isLoading } = useReadContract({
    address: safeAddress,
    abi: SAFE_THRESHOLD_ABI,
    functionName: "getThreshold",
    chainId: base.id,
    query: { enabled: !!safeAddress },
  });

  return { threshold: data !== undefined ? Number(data) : undefined, isLoading };
}
