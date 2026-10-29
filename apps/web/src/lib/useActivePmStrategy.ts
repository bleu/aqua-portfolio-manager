"use client";

import { useEffect, useState } from "react";
import type { Address, Hex } from "viem";
import { PM_ROUTER_ADDRESS } from "./contracts";

/** The connected Safe's own active Portfolio Manager strategy, read from the indexer -- the real
 *  source of truth for what Aqua.dock() needs (strategyHash and the exact token set it shipped
 *  with), independent of any local wizard state. shippedAt is Ponder's bigint seconds-since-epoch,
 *  serialized as a string over GraphQL to avoid precision loss -- multiply by 1000 for a JS Date. */
export type ActivePmStrategy = {
  strategyHash: Hex;
  tokens: Address[];
  shippedAt: string;
  /** Aqua's own Shipped `strategy` bytes -- lets the dashboard decode real basket groups and
   *  target shares (see portfolioManagerEncoding.ts's decodeOrderGroups) for a strategy that was
   *  never shipped through this app's own wizard, so has no local draft snapshot to fall back on. */
  encodedOrder: Hex;
  /** Null when shipped without a matching attestBuildParameters call, or one that declined to
   *  name groups -- see ponder.schema.ts's own strategy.groupNames comment. */
  groupNames: string[] | null;
};

const QUERY = `
  query ActivePmStrategy($maker: String!, $app: String!) {
    strategys(where: { maker: $maker, app: $app, isActive: true }, limit: 1) {
      items { strategyHash tokens shippedAt encodedOrder groupNames }
    }
  }
`;

export function useActivePmStrategy(safeAddress: Address | undefined) {
  const [strategy, setStrategy] = useState<ActivePmStrategy>();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    const indexerUrl = process.env.NEXT_PUBLIC_INDEXER_GRAPHQL_URL;
    if (!safeAddress || !indexerUrl) {
      setStrategy(undefined);
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
      .then((json: { data?: { strategys: { items: ActivePmStrategy[] } }; errors?: unknown }) => {
        if (cancelled) return;
        if (json.errors || !json.data) {
          throw new Error(JSON.stringify(json.errors));
        }
        setStrategy(json.data.strategys.items[0]);
      })
      .catch((err) => {
        if (cancelled) return;
        console.error("Failed to load the active Portfolio Manager strategy:", err);
        setError("Couldn't reach the indexer to look up your active strategy.");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [safeAddress]);

  return { strategy, isLoading, error };
}
