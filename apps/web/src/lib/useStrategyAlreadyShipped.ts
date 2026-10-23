"use client";

import { useEffect, useState } from "react";
import type { Hex } from "viem";
import { PM_ROUTER_ADDRESS } from "./contracts";

/** Aqua.ship() permanently refuses to reuse a strategyHash once shipped (StrategiesMustBeImmutable
 *  in Aqua.sol), even after the strategy was later docked -- the hash has no nonce/timestamp, so
 *  recreating identical groups/fee/deviation always produces the same hash, which can never ship
 *  again. Checking the indexer for it before the user signs anything catches this before they
 *  burn a real approve+attest signature on a strategy that was always going to fail at the last
 *  step -- a real failure mode this hook was built to prevent, not a hypothetical one. */
export function useStrategyAlreadyShipped(strategyHash: Hex | undefined) {
  const [alreadyShipped, setAlreadyShipped] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    const indexerUrl = process.env.NEXT_PUBLIC_INDEXER_GRAPHQL_URL;
    if (!strategyHash || !indexerUrl) {
      setAlreadyShipped(false);
      return;
    }

    let cancelled = false;
    setIsLoading(true);
    setError(undefined);

    fetch(indexerUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        query: `query StrategyAlreadyShipped($strategyHash: String!, $app: String!) {
          strategys(where: { strategyHash: $strategyHash, app: $app }, limit: 1) { totalCount }
        }`,
        variables: { strategyHash: strategyHash.toLowerCase(), app: PM_ROUTER_ADDRESS.toLowerCase() },
      }),
    })
      .then((res) => res.json())
      .then((json: { data?: { strategys: { totalCount: number } }; errors?: unknown }) => {
        if (cancelled) return;
        if (json.errors || !json.data) {
          throw new Error(JSON.stringify(json.errors));
        }
        setAlreadyShipped(json.data.strategys.totalCount > 0);
      })
      .catch((err) => {
        if (cancelled) return;
        console.error("Failed to check whether this strategy was already shipped:", err);
        setError("Couldn't reach the indexer to check for a previously-shipped identical strategy.");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [strategyHash]);

  return { alreadyShipped, isLoading, error };
}
