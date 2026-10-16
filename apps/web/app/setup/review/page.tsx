"use client";

import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { ReviewPortfolioManagerPage } from "@/components/pages/ReviewPortfolioManagerPage";
import { loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { loadDraftParameters } from "@/lib/parametersDraftStorage";
import { loadDraftTargets } from "@/lib/targetsDraftStorage";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useSafeThreshold } from "@/lib/useSafeThreshold";

export default function Page() {
  const router = useRouter();
  const { address } = useAccount();
  const { tokens } = useSafeBalances(address);
  const { threshold } = useSafeThreshold(address);

  if (!address) {
    return <div className="min-h-screen" />;
  }

  const draftBaskets = loadDraftBaskets(address) ?? initialBaskets;
  const draftTargets = loadDraftTargets(address) ?? {};
  const draftParameters = loadDraftParameters(address);

  const total = draftBaskets.reduce((sum, basket) => {
    const basketTokens = tokens.filter((t) => basket.tokenAddresses.includes(t.address));
    return sum + basketTokens.reduce((s, t) => s + t.value, 0);
  }, 0);

  const baskets = draftBaskets.map((basket) => {
    const basketTokens = tokens.filter((t) => basket.tokenAddresses.includes(t.address));
    const currentValue = basketTokens.reduce((sum, t) => sum + t.value, 0);
    return {
      id: basket.id,
      name: basket.name,
      color: basket.color,
      tokenSymbols: basketTokens.map((t) => t.symbol),
      currentValue,
      currentPct: total > 0 ? (currentValue / total) * 100 : 0,
      targetPct: draftTargets[basket.id] ?? (total > 0 ? (currentValue / total) * 100 : 0),
    };
  });

  return (
    <ReviewPortfolioManagerPage
      network="Base"
      safeAddress={address}
      baskets={baskets}
      priceDeviationPct={draftParameters?.priceDeviationPct ?? 0}
      lpFeePct={draftParameters?.lpFeePct ?? 0}
      signaturesRequired={threshold ?? 1}
      onBack={() => router.push("/setup/parameters")}
      onCreateTransaction={() => router.push("/setup/waiting-for-signatures")}
    />
  );
}
