"use client";

import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { ActivePortfolioManagerDashboardPage } from "@/components/pages/ActivePortfolioManagerDashboardPage";
import { EmptyDashboardPage } from "@/components/pages/EmptyDashboardPage";
import { loadActiveStrategy } from "@/lib/activeStrategyStorage";
import { useSafeBalances } from "@/lib/useSafeBalances";

export default function Page() {
  const router = useRouter();
  const { address } = useAccount();
  const { tokens } = useSafeBalances(address);

  if (!address) {
    return <div className="min-h-screen" />;
  }

  const activeStrategy = loadActiveStrategy(address);

  if (!activeStrategy) {
    return (
      <EmptyDashboardPage network="Base" safeAddress={address} onStartSetup={() => router.push("/setup/baskets")} />
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
      network="Base"
      safeAddress={address}
      updatedAt={activeStrategy.activatedAt}
      managedValue={managedValue}
      netLpFeesEarned={0}
      routedVolume={0}
      routedTransactionCount={0}
      baskets={baskets}
      chartSeries={chartSeries}
    />
  );
}
