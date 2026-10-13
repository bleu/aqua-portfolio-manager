"use client";

import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { PortfolioManagerActivatedPage } from "@/components/pages/PortfolioManagerActivatedPage";
import { saveActiveStrategy } from "@/lib/activeStrategyStorage";
import { clearDraftBaskets, loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { clearDraftParameters, loadDraftParameters } from "@/lib/parametersDraftStorage";
import { clearDraftTargets, loadDraftTargets } from "@/lib/targetsDraftStorage";
import { useSafeBalances } from "@/lib/useSafeBalances";

export default function Page() {
  const router = useRouter();
  const { address } = useAccount();
  const { tokens } = useSafeBalances(address);

  if (!address) {
    return <div className="min-h-screen" />;
  }

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
      activationTxHash="0x0000000000000000000000000000000000000000000000000000000000000000"
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
        clearDraftTargets(address);
        clearDraftParameters(address);
        router.push("/dashboard");
      }}
    />
  );
}
