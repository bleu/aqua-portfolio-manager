"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import type { Address } from "viem";
import { useAccount } from "wagmi";
import { PortfolioManagerHistoryPage } from "@/components/pages/PortfolioManagerHistoryPage";
import { buildReshipSteps, executeShipSteps } from "@/lib/safeProposal";
import { symbolForToken } from "@/lib/tokenFeeds";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useStrategyHistory } from "@/lib/useStrategyHistory";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  const router = useRouter();
  const { chain, isConnected, connector } = useAccount();
  const address = useVerifiedSafeAddress();
  const { entries, isLoading, error } = useStrategyHistory(address as Address | undefined);
  const { tokens, rawBalances } = useSafeBalances(address);
  const [reshippingStrategyHash, setReshippingStrategyHash] = useState<string>();
  const [reshipError, setReshipError] = useState<string>();

  useEffect(() => {
    if (!isConnected) router.push("/");
  }, [isConnected, router]);

  /** Mirrors the ship wizard's own describeCreateTransactionError -- scoped to the one thing
   *  that can go wrong reshipping (no multi-step UI here to attribute an error to a specific
   *  step). */
  function describeReshipError(err: unknown): string {
    console.error("Failed to reship this strategy:", err);
    const message = err instanceof Error ? err.message : String(err);
    if (/user rejected|user denied|denied the request/i.test(message)) {
      return "You declined a signature request in your wallet. Nothing was changed.";
    }
    return "Something went wrong reshipping this strategy. Try again, or contact the team if this keeps happening.";
  }

  async function handleReship(strategyHash: string) {
    const entry = entries?.find((e) => e.strategyHash === strategyHash);
    if (!connector || !address || !entry) return;
    setReshipError(undefined);
    setReshippingStrategyHash(strategyHash);
    try {
      const tokenSymbols = Object.fromEntries(tokens.map((t) => [t.address, t.symbol])) as Record<Address, string>;
      const steps = await buildReshipSteps({
        encodedOrder: entry.encodedOrder,
        tokens: entry.tokens,
        groupNames: entry.groupNames,
        balances: rawBalances as Record<Address, bigint>,
        tokenSymbols,
      });
      // Not /setup/activated: that page renders its summary from local wizard drafts
      // (basketDraftsStorage etc.), which a History-page reship never went through -- it would
      // show a stale or empty draft instead of the strategy that was actually just reshipped.
      // The dashboard reads the real active strategy from the indexer, so it's correct either way.
      await executeShipSteps({ steps, safeAddress: address as Address, connector });
      router.push("/dashboard");
    } catch (err) {
      setReshipError(describeReshipError(err));
    } finally {
      setReshippingStrategyHash(undefined);
    }
  }

  if (!isConnected || !address) return null;

  return (
    <PortfolioManagerHistoryPage
      network={chain?.name ?? "Base"}
      safeAddress={address}
      entries={entries}
      isLoading={isLoading}
      error={error}
      symbolForToken={symbolForToken}
      onReship={handleReship}
      reshippingStrategyHash={reshippingStrategyHash}
      reshipError={reshipError}
      onSelectTab={(label) => {
        if (label === "Portfolio Manager") router.push("/dashboard");
      }}
    />
  );
}
