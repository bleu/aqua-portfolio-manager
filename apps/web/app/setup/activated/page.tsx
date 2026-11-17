"use client";

import { Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { PortfolioManagerActivatedPage } from "@/components/pages/PortfolioManagerActivatedPage";
import { saveActiveStrategy } from "@/lib/activeStrategyStorage";
import { clearDraftBaskets, loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { clearDraftParameters, loadDraftParameters } from "@/lib/parametersDraftStorage";
import { clearBalancesSnapshot, loadBalancesSnapshot } from "@/lib/safeBalancesSnapshot";
import { clearDraftTargets, loadDraftTargets } from "@/lib/targetsDraftStorage";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  return (
    <Suspense fallback={<div className="min-h-screen" />}>
      <ActivatedPageContent />
    </Suspense>
  );
}

/** useSearchParams() (for the real activation tx hash) forces this subtree into a Suspense
 *  boundary during static prerendering -- split out so Page itself can provide the fallback. */
function ActivatedPageContent() {
  const router = useRouter();
  const address = useVerifiedSafeAddress();
  const { tokens: liveTokens } = useSafeBalances(address);
  const searchParams = useSearchParams();
  const activationTxHash = searchParams.get("tx") ?? "";

  if (!address) {
    return <div className="min-h-screen" />;
  }

  // Same wizard-wide balance snapshot Targets/Review read -- keeps this screen's figures matching
  // what the user saw throughout, not a fresh live fetch.
  const tokens = loadBalancesSnapshot(address) ?? liveTokens;
  const draftBaskets = loadDraftBaskets(address) ?? initialBaskets;
  const draftTargets = loadDraftTargets(address) ?? {};
  const draftParameters = loadDraftParameters(address);

  const baskets = draftBaskets.map((basket) => {
    const basketTokens = tokens.filter((t) => basket.tokenAddresses.includes(t.address));
    return {
      id: basket.id,
      name: basket.name,
      color: basket.color,
      tokenSymbols: basketTokens.map((t) => t.symbol),
      currentPct: draftTargets[basket.id] ?? 0,
    };
  });
  const managedValue = draftBaskets.reduce((sum, basket) => {
    const basketTokens = tokens.filter((t) => basket.tokenAddresses.includes(t.address));
    return sum + basketTokens.reduce((s, t) => s + t.value, 0);
  }, 0);
  const tokenCount = new Set(draftBaskets.flatMap((b) => b.tokenAddresses)).size;

  return (
    <PortfolioManagerActivatedPage
      network="Base"
      safeAddress={address}
      managedValue={managedValue}
      baskets={baskets}
      tokenCount={tokenCount}
      lpFeePct={draftParameters?.lpFeePct ?? 0}
      activationTxHash={activationTxHash}
      onGoToDashboard={() => {
        // Snapshots the final config before clearing the in-progress draft -- the dashboard
        // (BLEUDEV-419) reads this, not the draft, since the draft's whole point is to not
        // resurface once the strategy has shipped. The real source of truth is on-chain/the
        // indexer; this placeholder stands in until that's wired up.
        if (draftParameters) {
          saveActiveStrategy(address, {
            baskets: draftBaskets,
            targetsPct: draftTargets,
            parameters: draftParameters,
            activatedAt: Date.now(),
          });
        }
        clearDraftBaskets(address);
        clearBalancesSnapshot(address);
        clearDraftTargets(address);
        clearDraftParameters(address);
        router.push("/dashboard");
      }}
      onSelectTab={(label) => {
        if (label === "Activity") router.push("/dashboard/history");
        if (label === "Home") router.push("/dashboard");
      }}
    />
  );
}
