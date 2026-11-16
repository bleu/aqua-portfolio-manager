"use client";


import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { zeroAddress, type Address } from "viem";
import { useAccount } from "wagmi";
import { ActivePortfolioManagerDashboardPage } from "@/components/pages/ActivePortfolioManagerDashboardPage";
import { clearActiveStrategy, loadActiveStrategy } from "@/lib/activeStrategyStorage";
import { BASKET_COLORS } from "@/lib/basketColors";
import { buildDockTransaction, buildRemoveGuardTransaction } from "@/lib/dockProposal";
import { decodeOrderGroups, type DecodedGroup } from "@/lib/portfolioManagerEncoding";
import { readInstalledGuard, sendTransaction } from "@/lib/safeProposal";
import { tokenAtRegistryIndex } from "@/lib/tokenFeeds";
import { useActivePmStrategy } from "@/lib/useActivePmStrategy";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

type DashboardBasketDraft = {
  id: string;
  name: string;
  color: string;
  managedValue: number;
  targetPct: number;
  tokens: { symbol: string; name: string; address: string; iconUrl?: string; balance: number; value: number }[];
};

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
      // setIsDeleting below) re-reads loadActiveStrategy(address) fresh and falls through to the
      // setup-wizard redirect above on its own, the same way the initial render reads it.
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

  // The dedicated "empty dashboard" screen (BLEUDEV-410) is gone -- a Safe with no active
  // strategy now goes straight into the setup wizard, whose first step shows the one-time
  // "Welcome to Trim" modal (see CreateBasketsPage) instead of a separate landing screen.
  //
  // Gated on activePmStrategy (the indexer), not loadActiveStrategy (the local snapshot below):
  // the local snapshot is only ever written when the /setup/activated page's "Go to dashboard"
  // button is clicked, which a real shipped strategy can easily never reach (a slow confirmation,
  // a closed tab, an error screen after the transaction had actually already succeeded). Gating on
  // it alone would redirect a genuinely active, correctly-shipped strategy back into setup --
  // confirmed happening on a real strategy, not a hypothetical.
  useEffect(() => {
    if (isConnected && address && !activePmStrategy) router.push("/setup/baskets");
  }, [isConnected, address, activePmStrategy, router]);

  if (!isConnected || !address || !activePmStrategy) return null;

  const network = chain?.name ?? "Base";

  const activeStrategy = loadActiveStrategy(address);

  function tokenRows(addresses: string[]) {
    const lower = addresses.map((a) => a.toLowerCase());
    return tokens
      .filter((t) => lower.includes(t.address.toLowerCase()))
      .map((t) => ({ symbol: t.symbol, name: t.symbol, address: t.address, iconUrl: t.iconUrl, balance: t.balance, value: t.value }));
  }

  let draftBaskets: DashboardBasketDraft[];
  let updatedAt: number;

  if (activeStrategy) {
    // The nice path: a local snapshot exists, so basket names and colors (never stored on-chain
    // or in the indexer -- a pure wizard/UI concept) are available.
    draftBaskets = activeStrategy.baskets.map((basket) => {
      const basketTokens = tokenRows(basket.tokenAddresses);
      return {
        id: basket.id,
        name: basket.name,
        color: basket.color,
        managedValue: basketTokens.reduce((sum, t) => sum + t.value, 0),
        targetPct: activeStrategy.targetsPct[basket.id] ?? 0,
        tokens: basketTokens,
      };
    });
    updatedAt = activeStrategy.activatedAt;
  } else {
    // No local snapshot (shipped outside this app's own wizard, or the snapshot was never
    // written) -- decode the real basket groups straight from Aqua's own Shipped bytes instead of
    // collapsing everything into one fake "Managed tokens" basket. See decodeOrderGroups' own doc
    // comment for why this is the honest source here, not activeStrategyStorage.ts's snapshot.
    let decodedGroups: DecodedGroup[] = [];
    try {
      decodedGroups = decodeOrderGroups(activePmStrategy.encodedOrder);
    } catch (err) {
      console.error("Failed to decode this strategy's basket groups:", err);
    }

    draftBaskets =
      decodedGroups.length > 0
        ? decodedGroups.map((group, i) => {
            const groupTokenAddresses = group.tokenIndices
              .map((tokenIndex) => tokenAtRegistryIndex(tokenIndex))
              .filter((a): a is string => !!a);
            const basketTokens = tokenRows(groupTokenAddresses);
            return {
              id: `group-${i}`,
              name: activePmStrategy.groupNames?.[i] ?? `Basket ${i + 1}`,
              color: BASKET_COLORS[i % BASKET_COLORS.length]!,
              managedValue: basketTokens.reduce((sum, t) => sum + t.value, 0),
              targetPct: (group.weightBps / 1_000_000_000) * 100,
              tokens: basketTokens,
            };
          })
        : // Decoding itself failed (logged above) -- fall back to one undifferentiated basket
          // rather than showing nothing, same intent as the old always-one-basket path.
          [
            {
              id: "managed",
              name: "Managed tokens",
              color: BASKET_COLORS[0]!,
              managedValue: tokenRows(activePmStrategy.tokens).reduce((sum, t) => sum + t.value, 0),
              targetPct: 100,
              tokens: tokenRows(activePmStrategy.tokens),
            },
          ];
    updatedAt = Number(activePmStrategy.shippedAt) * 1000;
  }

  const managedValue = draftBaskets.reduce((sum, b) => sum + b.managedValue, 0);
  // currentPct is always derived from real balances, for every basket -- never copied from
  // targetPct, which would make the dashboard claim "on target" regardless of actual holdings.
  const baskets = draftBaskets.map((b) => ({
    ...b,
    currentPct: managedValue > 0 ? (b.managedValue / managedValue) * 100 : 0,
  }));
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
        if (label === "Activity") router.push("/dashboard/history");
        if (label === "Home") router.push("/dashboard");
      }}
    />
  );
}
