"use client";

import { useEffect, useState } from "react";
import type { Address, Hex } from "viem";
import { PM_ROUTER_ADDRESS } from "./contracts";

/** One strategy this Safe has ever shipped against the current router, active or docked. shippedAt
 *  and dockedAt are Ponder's bigint seconds-since-epoch, serialized as strings over GraphQL to
 *  avoid precision loss -- multiply by 1000 for a JS Date. dockedAt/dockedAtTxHash are null for a
 *  still-active strategy. */
export type StrategyHistoryEntry = {
  strategyHash: Hex;
  /** Aqua's own Shipped `strategy` bytes (abi.encode(ISwapVM.Order)) -- everything needed to
   *  reship an exact copy of this strategy (see safeProposal.ts's buildReshipSteps), independent
   *  of any local wizard draft. */
  encodedOrder: Hex;
  tokens: Address[];
  /** Null when this strategy was shipped without a matching attestBuildParameters call, or one
   *  that declined to name groups -- see ponder.schema.ts's own strategy.groupNames comment. */
  groupNames: string[] | null;
  isActive: boolean;
  shippedAt: string;
  shippedAtTxHash: Hex;
  dockedAt: string | null;
  dockedAtTxHash: Hex | null;
};

const QUERY = `
  query StrategyHistory($maker: String!, $app: String!) {
    strategys(where: { maker: $maker, app: $app }, orderBy: "shippedAt", orderDirection: "desc", limit: 100) {
      items { strategyHash encodedOrder tokens groupNames isActive shippedAt shippedAtTxHash dockedAt dockedAtTxHash }
    }
  }
`;

/** Every strategy this Safe has ever shipped or docked against the current router, newest first --
 *  the indexer's own history, independent of any local wizard state (BLEUDEV-419's History tab). */
export function useStrategyHistory(safeAddress: Address | undefined) {
  const [entries, setEntries] = useState<StrategyHistoryEntry[]>();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    const indexerUrl = process.env.NEXT_PUBLIC_INDEXER_GRAPHQL_URL;
    if (!safeAddress || !indexerUrl) {
      setEntries(undefined);
      return;
    }

    let cancelled = false;
    setIsLoading(true);
    setError(undefined);

    fetch(indexerUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        query: QUERY,
        variables: { maker: safeAddress.toLowerCase(), app: PM_ROUTER_ADDRESS.toLowerCase() },
      }),
    })
      .then((res) => res.json())
      .then((json: { data?: { strategys: { items: StrategyHistoryEntry[] } }; errors?: unknown }) => {
        if (cancelled) return;
        if (json.errors || !json.data) {
          throw new Error(JSON.stringify(json.errors));
        }
        setEntries(json.data.strategys.items);
      })
      .catch((err) => {
        if (cancelled) return;
        console.error("Failed to load strategy history:", err);
        setError("Couldn't reach the indexer to look up this Safe's strategy history.");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [safeAddress]);

  return { entries, isLoading, error };
}
