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

/** Result state keyed by the address it was actually fetched for -- not a bare `strategy`/
 *  `isLoading` pair. Two independent `useState`s updated from inside an effect leaves a real gap:
 *  on the very render where `safeAddress` first turns from undefined into a real address, this
 *  hook's own effect hasn't run yet, so `isLoading` is still sitting at its OLD value (false) and
 *  `strategy` at its OLD value (undefined) -- a caller that reacts to "no strategy" in that exact
 *  render (e.g. DashboardPageClient's own redirect-to-setup effect, which fires in the same commit)
 *  reads a false "definitely no active strategy" before the fetch for the NEW address has even
 *  started, let alone finished. Confirmed as a real bug, not a hypothetical: a user who had just
 *  shipped a real strategy was bounced straight back into the setup wizard on landing on
 *  /dashboard, purely because the redirect effect ran one tick before the indexer answered.
 *  Deriving `isLoading` from comparing `fetchedFor` against the current `safeAddress` prop, every
 *  render, closes that gap -- it's true the instant the address changes, with no state update (and
 *  therefore no extra render) needed first. */
type Result = { fetchedFor: Address | undefined; strategy?: ActivePmStrategy; error?: string };

export function useActivePmStrategy(safeAddress: Address | undefined) {
  const [result, setResult] = useState<Result>({ fetchedFor: undefined });

  useEffect(() => {
    const indexerUrl = process.env.NEXT_PUBLIC_INDEXER_GRAPHQL_URL;
    if (!safeAddress || !indexerUrl) {
      setResult({ fetchedFor: safeAddress });
      return;
    }

    let cancelled = false;

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
        setResult({ fetchedFor: safeAddress, strategy: json.data.strategys.items[0] });
      })
      .catch((err) => {
        if (cancelled) return;
        console.error("Failed to load the active Portfolio Manager strategy:", err);
        setResult({ fetchedFor: safeAddress, error: "Couldn't reach the indexer to look up your active strategy." });
      });

    return () => {
      cancelled = true;
    };
  }, [safeAddress]);

  const isLoading = safeAddress !== undefined && result.fetchedFor !== safeAddress;
  const strategy = result.fetchedFor === safeAddress ? result.strategy : undefined;
  const error = result.fetchedFor === safeAddress ? result.error : undefined;
  return { strategy, isLoading, error };
}
