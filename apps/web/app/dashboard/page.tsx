"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import type { Address } from "viem";
import { useAccount } from "wagmi";
import { ActivePortfolioManagerDashboardPage } from "@/components/pages/ActivePortfolioManagerDashboardPage";
import { EmptyDashboardPage } from "@/components/pages/EmptyDashboardPage";
import { clearActiveStrategy, loadActiveStrategy } from "@/lib/activeStrategyStorage";
import { buildDockTransaction } from "@/lib/dockProposal";
import { sendTransaction } from "@/lib/safeProposal";
import { useActivePmStrategy } from "@/lib/useActivePmStrategy";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  const router = useRouter();
  const { chain, isConnected, connector } = useAccount();
  const address = useVerifiedSafeAddress();
  const { tokens } = useSafeBalances(address);
  const { strategy: activePmStrategy } = useActivePmStrategy(address as Address | undefined);
  const [isDeleting, setIsDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string>();

  /** Maps a raw thrown error to a plain-language message -- same intent as the Review page's own
   *  describeCreateTransactionError, scoped to the one thing that can go wrong deleting a
   *  strategy (no multi-step flow here to attribute the error to a specific step). */
  function describeDeleteError(err: unknown): string {
    console.error("Failed to delete the Portfolio Manager:", err);
    const message = err instanceof Error ? err.message : String(err);
    if (/user rejected|user denied|denied the request/i.test(message)) {
      return "You declined the signature request in your wallet. Nothing was changed.";
    }
    return "Something went wrong deleting this Portfolio Manager. Try again, or contact the team if this keeps happening.";
  }

  async function handleDeleteStrategy() {
    if (!connector || !address || !activePmStrategy) return;
    setDeleteError(undefined);
    setIsDeleting(true);
    try {
      const provider = (await connector.getProvider()) as {
        request: (args: { method: string; params?: unknown[] | object }) => Promise<unknown>;
      };
      const { to, data } = buildDockTransaction(activePmStrategy.strategyHash, activePmStrategy.tokens);
      await sendTransaction(to, data, address as Address, provider);
      // No navigation needed: clearing storage here is enough -- the next render (triggered by
      // setIsDeleting below) re-reads loadActiveStrategy(address) fresh and falls through to
      // EmptyDashboardPage on its own, the same way the initial render reads it.
      clearActiveStrategy(address);
    } catch (err) {
      setDeleteError(describeDeleteError(err));
    } finally {
      setIsDeleting(false);
    }
  }

  // No Safe connected at all yet (e.g. this URL was opened directly) -- send back to the connect
  // flow instead of rendering a header for a wallet that isn't actually there. A *stale* connection
  // (looked connected but wasn't) is caught separately by useVerifiedSafeAddress itself.
  useEffect(() => {
    if (!isConnected) router.push("/");
  }, [isConnected, router]);

  if (!isConnected || !address) return null;

  const network = chain?.name ?? "Base";
  const activeStrategy = loadActiveStrategy(address);

  if (!activeStrategy) {
    return (
      <EmptyDashboardPage network={network} safeAddress={address} onStartSetup={() => router.push("/setup/baskets")} />
    );
  }

  const baskets = activeStrategy.baskets.map((basket) => {
    const basketTokens = tokens.filter((t) => basket.tokenAddresses.includes(t.address));
    const managedValue = basketTokens.reduce((sum, t) => sum + t.value, 0);
    return {
      id: basket.id,
      name: basket.name,
      color: basket.color,
      managedValue,
      currentPct: activeStrategy.targetsPct[basket.id] ?? 0,
      targetPct: activeStrategy.targetsPct[basket.id] ?? 0,
      tokens: basketTokens.map((t) => ({
        symbol: t.symbol,
        name: t.symbol,
        address: t.address,
        iconUrl: t.iconUrl,
        balance: t.balance,
        value: t.value,
      })),
    };
  });
  const managedValue = baskets.reduce((sum, b) => sum + b.managedValue, 0);
  const chartSeries = baskets.map((b) => ({
    id: b.id,
    name: `${b.name} current`,
    color: b.color,
    targetPct: b.targetPct,
    points: [{ date: "Today", pct: b.currentPct }],
  }));

  return (
    <ActivePortfolioManagerDashboardPage
      network={network}
      safeAddress={address}
      updatedAt={activeStrategy.activatedAt}
      managedValue={managedValue}
      netLpFeesEarned={0}
      routedVolume={0}
      routedTransactionCount={0}
      baskets={baskets}
      chartSeries={chartSeries}
      onDeleteStrategy={handleDeleteStrategy}
      isDeletingStrategy={isDeleting}
      deleteStrategyError={deleteError}
      canDeleteStrategy={!!activePmStrategy}
    />
  );
}
