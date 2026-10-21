"use client";

import { useEffect, useRef, useState } from "react";
import type { Address } from "viem";

/** docs/adr/0011-safe-wallet-with-basket-scope-guard.md: the on-chain Guard only checks direct
 *  `Aqua.ship()` calls made after it's installed -- it can't inspect a Safe's event history, so
 *  a strategy that already spans tokens from more than one basket, shipped before the Guard
 *  existed, stays active forever with no on-chain check ever catching it. This hook is that
 *  missing check, done off-chain against the indexer before the Portfolio Manager (and its
 *  Guard) gets created. */

export type IndexedStrategy = { id: string; app: Address; strategyHash: string; tokens: Address[] };

/** Mirrors BasketScopeGuard.sol's two revert reasons (packages/contracts/src/BasketScopeGuard.sol)
 *  exactly -- "cross-basket" is `CrossBasketStrategyForbidden` (tokens split across two declared
 *  baskets), "basket-foreign" is `TokenNotInAnyBasket` (a token the Guard's basketOf mapping
 *  wouldn't recognize at all). A strategy can carry either reason, or both at once. */
export type ScopeConflictType = "cross-basket" | "basket-foreign";

export type BasketScopeConflict = {
  strategyHash: string;
  app: Address;
  types: ScopeConflictType[];
  basketNames: string[];
  foreignTokens: Address[];
};

const QUERY = `
  query ActiveStrategies($maker: String!) {
    strategys(where: { maker: $maker, isActive: true }, limit: 1000) {
      items { id app strategyHash tokens }
    }
  }
`;

export function useBasketScopeConflict(
  safeAddress: Address | undefined,
  baskets: { name: string; tokenAddresses: Address[] }[],
) {
  const [conflicts, setConflicts] = useState<BasketScopeConflict[]>();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string>();
  // `baskets` is a fresh array every render; a ref avoids re-fetching on every render while still
  // reading the latest basket set once the fetch (keyed only on `safeAddress`+`basketsKey` below)
  // actually resolves.
  const basketsRef = useRef(baskets);
  basketsRef.current = baskets;
  const basketsKey = JSON.stringify(baskets.map((b) => b.tokenAddresses));

  useEffect(() => {
    const indexerUrl = process.env.NEXT_PUBLIC_INDEXER_GRAPHQL_URL;
    if (!safeAddress || !indexerUrl) {
      setConflicts(undefined);
      return;
    }

    let cancelled = false;
    setIsLoading(true);
    setError(undefined);

    fetch(indexerUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ query: QUERY, variables: { maker: safeAddress.toLowerCase() } }),
    })
      .then((res) => res.json())
      .then((json: { data?: { strategys: { items: IndexedStrategy[] } }; errors?: unknown }) => {
        if (cancelled) return;
        if (json.errors || !json.data) {
          throw new Error(JSON.stringify(json.errors));
        }
        setConflicts(findConflicts(json.data.strategys.items, basketsRef.current));
      })
      .catch((err) => {
        if (cancelled) return;
        console.error("Failed to check for prior active strategies:", err);
        setError("Couldn't reach the indexer to check for conflicting prior strategies.");
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [safeAddress, basketsKey]);

  return { conflicts, isLoading, error };
}

/** A strategy conflicts for either (or both) of BasketScopeGuard.sol's own reasons:
 *  - "basket-foreign": it holds a token that isn't declared in any of the new baskets at all
 *    (the Guard's `basketOf[token] == 0` case, `TokenNotInAnyBasket`).
 *  - "cross-basket": its tokens span two or more of the new baskets (`CrossBasketStrategyForbidden`).
 *  The Guard reverts on whichever it hits first while scanning the token array; this check
 *  reports every reason that actually holds, which is more useful off-chain than picking one. */
export function findConflicts(
  strategies: IndexedStrategy[],
  baskets: { name: string; tokenAddresses: Address[] }[],
): BasketScopeConflict[] {
  const basketOf = new Map<string, string>();
  for (const basket of baskets) {
    for (const token of basket.tokenAddresses) basketOf.set(token.toLowerCase(), basket.name);
  }

  const conflicts: BasketScopeConflict[] = [];
  for (const strategy of strategies) {
    const spannedBaskets = new Set<string>();
    const foreignTokens: Address[] = [];
    for (const token of strategy.tokens) {
      const basketName = basketOf.get(token.toLowerCase());
      if (basketName) spannedBaskets.add(basketName);
      else foreignTokens.push(token);
    }

    const types: ScopeConflictType[] = [];
    if (foreignTokens.length > 0) types.push("basket-foreign");
    if (spannedBaskets.size > 1) types.push("cross-basket");

    if (types.length > 0) {
      conflicts.push({
        strategyHash: strategy.strategyHash,
        app: strategy.app,
        types,
        basketNames: [...spannedBaskets],
        foreignTokens,
      });
    }
  }
  return conflicts;
}
