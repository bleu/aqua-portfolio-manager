"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { zeroAddress, type Address } from "viem";
import { useAccount } from "wagmi";
import { ActivePortfolioManagerDashboardPage } from "@/components/pages/ActivePortfolioManagerDashboardPage";
import { EmptyDashboardPage } from "@/components/pages/EmptyDashboardPage";
import { clearActiveStrategy, loadActiveStrategy } from "@/lib/activeStrategyStorage";
import { buildDockTransaction, buildRemoveGuardTransaction } from "@/lib/dockProposal";
import { readInstalledGuard, sendTransaction } from "@/lib/safeProposal";
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
   *  describeCreateTransactionError, scoped to the one thing that can go wrong docking a
   *  strategy (the guard-removal step below has its own, separate message). */
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

      // The strategy is already closed on Aqua's ledger at this point, so a failure past here
      // is a separate, non-blocking problem, not a reason to tell the user nothing happened --
      // see buildRemoveGuardTransaction's own doc comment for why a stale guard matters.
      try {
        const installedGuard = await readInstalledGuard(address as Address);
        if (installedGuard !== zeroAddress) {
          const guardStep = buildRemoveGuardTransaction(address as Address);
          await sendTransaction(guardStep.to, guardStep.data, address as Address, provider);
        }
      } catch (guardErr) {
        console.error("Docked the strategy, but failed to remove its basket-scope guard:", guardErr);
        setDeleteError(
          "The strategy was removed, but clearing its guard failed. It'll block a future strategy with different baskets until you clear it -- try again, or contact the team.",
        );
      }
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

  // The indexer, not the local snapshot below, is the real source of truth for whether a
  // strategy is active -- see useActivePmStrategy's own doc comment. The local snapshot is only
  // ever written when the /setup/activated page's "Go to dashboard" button is clicked, which a
  // real shipped strategy can easily never reach (a slow confirmation, a closed tab, an error
  // screen after the transaction had actually already succeeded). Gating on it alone left a
  // genuinely active, correctly-shipped strategy showing "set up a new PM" instead of the
  // dashboard -- confirmed happening on a real strategy, not a hypothetical.
  if (!activePmStrategy) {
    return (
      <EmptyDashboardPage
        network={network}
        safeAddress={address}
        onStartSetup={() => router.push("/setup/baskets")}
        onSelectTab={(label) => {
          if (label === "History") router.push("/dashboard/history");
        }}
      />
    );
  }

  const activeStrategy = loadActiveStrategy(address);

  let baskets: {
    id: string;
    name: string;
    color: string;
    managedValue: number;
    currentPct: number;
    targetPct: number;
    tokens: { symbol: string; name: string; address: string; iconUrl?: string; balance: number; value: number }[];
  }[];
  let updatedAt: number;

  if (activeStrategy) {
    // The nice path: a local snapshot exists, so basket names, colors, and the original target
    // split (never stored on-chain or in the indexer -- a pure wizard/UI concept) are available.
    baskets = activeStrategy.baskets.map((basket) => {
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
    updatedAt = activeStrategy.activatedAt;
  } else {
    // The indexer confirms an active strategy but nothing was ever saved locally -- show the real
    // managed tokens as one basket rather than fabricating a target split this app never recorded.
    const managedTokens = tokens.filter((t) =>
      activePmStrategy.tokens.some((managed) => managed.toLowerCase() === t.address.toLowerCase()),
    );
    const managedValue = managedTokens.reduce((sum, t) => sum + t.value, 0);
    baskets = [
      {
        id: "managed",
        name: "Managed tokens",
        color: "#6366f1",
        managedValue,
        currentPct: 100,
        targetPct: 100,
        tokens: managedTokens.map((t) => ({
          symbol: t.symbol,
          name: t.symbol,
          address: t.address,
          iconUrl: t.iconUrl,
          balance: t.balance,
          value: t.value,
        })),
      },
    ];
    updatedAt = Number(activePmStrategy.shippedAt) * 1000;
  }

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
      updatedAt={updatedAt}
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
      onSelectTab={(label) => {
        if (label === "History") router.push("/dashboard/history");
      }}
    />
  );
}
