"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";
import type { Address } from "viem";
import { useAccount } from "wagmi";
import { PortfolioManagerHistoryPage } from "@/components/pages/PortfolioManagerHistoryPage";
import { symbolForToken } from "@/lib/tokenFeeds";
import { useStrategyHistory } from "@/lib/useStrategyHistory";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  const router = useRouter();
  const { chain, isConnected } = useAccount();
  const address = useVerifiedSafeAddress();
  const { entries, isLoading, error } = useStrategyHistory(address as Address | undefined);

  useEffect(() => {
    if (!isConnected) router.push("/");
  }, [isConnected, router]);

  if (!isConnected || !address) return null;

  return (
    <PortfolioManagerHistoryPage
      network={chain?.name ?? "Base"}
      safeAddress={address}
      entries={entries}
      isLoading={isLoading}
      error={error}
      symbolForToken={symbolForToken}
      onSelectTab={(label) => {
        if (label === "Portfolio Manager") router.push("/dashboard");
      }}
    />
  );
}
