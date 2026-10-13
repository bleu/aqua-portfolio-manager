"use client";

import { erc20Abi } from "viem";
import { useReadContracts } from "wagmi";
import { base } from "wagmi/chains";
import { TOKEN_FEEDS } from "./tokenFeeds";
import type { SafeToken } from "./mockBaskets";

const AGGREGATOR_ABI = [
  {
    type: "function",
    name: "latestRoundData",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "roundId", type: "uint80" },
      { name: "answer", type: "int256" },
      { name: "startedAt", type: "uint256" },
      { name: "updatedAt", type: "uint256" },
      { name: "answeredInRound", type: "uint80" },
    ],
  },
] as const;

/** Real, live balances and Chainlink-priced USD values for every token in TOKEN_FEEDS, for the
 *  connected Safe -- one batched multicall (balance + decimals + price per token) instead of 120
 *  separate RPC calls. */
export function useSafeBalances(safeAddress: `0x${string}` | undefined) {
  const { data, isLoading, isError } = useReadContracts({
    contracts: TOKEN_FEEDS.flatMap((feed) => [
      {
        address: feed.tokenAddress as `0x${string}`,
        abi: erc20Abi,
        functionName: "balanceOf",
        args: [safeAddress ?? "0x0000000000000000000000000000000000000000"],
        chainId: base.id,
      },
      {
        address: feed.tokenAddress as `0x${string}`,
        abi: erc20Abi,
        functionName: "decimals",
        chainId: base.id,
      },
      {
        address: feed.feedProxy as `0x${string}`,
        abi: AGGREGATOR_ABI,
        functionName: "latestRoundData",
        chainId: base.id,
      },
    ]),
    query: { enabled: !!safeAddress },
  });

  const tokens: SafeToken[] = !data
    ? []
    : TOKEN_FEEDS.map((feed, i) => {
        const [balanceResult, decimalsResult, priceResult] = [data[i * 3], data[i * 3 + 1], data[i * 3 + 2]];
        const rawBalance = balanceResult?.status === "success" ? (balanceResult.result as bigint) : 0n;
        const tokenDecimals = decimalsResult?.status === "success" ? (decimalsResult.result as number) : 18;
        const roundData =
          priceResult?.status === "success"
            ? (priceResult.result as readonly [bigint, bigint, bigint, bigint, bigint])
            : undefined;
        const answer = roundData ? roundData[1] : 0n;
        const price = Number(answer) / 10 ** feed.feedDecimals;
        const balance = Number(rawBalance) / 10 ** tokenDecimals;
        return { symbol: feed.symbol, address: feed.tokenAddress, balance, value: balance * price };
      });

  return { tokens, isLoading, isError };
}
