"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { ReviewPortfolioManagerPage } from "@/components/pages/ReviewPortfolioManagerPage";
import { loadDraftBaskets } from "@/lib/basketDraftsStorage";
import { initialBaskets } from "@/lib/mockBaskets";
import { loadDraftParameters } from "@/lib/parametersDraftStorage";
import { proposeShipStrategyTransaction } from "@/lib/safeProposal";
import { loadDraftTargets } from "@/lib/targetsDraftStorage";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useSafeThreshold } from "@/lib/useSafeThreshold";

export default function Page() {
  const router = useRouter();
  const { address, connector } = useAccount();
  const { tokens, rawBalances } = useSafeBalances(address);
  const { threshold } = useSafeThreshold(address);
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string>();

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

  const priceDeviationPct = draftParameters?.priceDeviationPct ?? 0;
  const lpFeePct = draftParameters?.lpFeePct ?? 0;

  async function handleCreateTransaction() {
    if (!connector) return;
    setCreateError(undefined);
    setIsCreating(true);
    try {
      const provider = await connector.getProvider();
      const { safeTxHash } = await proposeShipStrategyTransaction({
        safeAddress: address as `0x${string}`,
        provider: provider as { request: (args: { method: string; params?: unknown[] | object }) => Promise<unknown> },
        groups: draftBaskets.map((basket) => ({
          name: basket.name,
          targetPct: draftTargets[basket.id] ?? 0,
          tokenAddresses: basket.tokenAddresses as `0x${string}`[],
        })),
        feeBpsPm: BigInt(Math.round(lpFeePct * 1e7)),
        maxDeviationBpsPm: BigInt(Math.round(priceDeviationPct * 1e7)),
        balances: rawBalances as Record<`0x${string}`, bigint>,
      });
      router.push(`/setup/waiting-for-signatures?tx=${safeTxHash}`);
    } catch (err) {
      setCreateError(err instanceof Error ? err.message : "Failed to create the Safe transaction.");
    } finally {
      setIsCreating(false);
    }
  }

  return (
    <ReviewPortfolioManagerPage
      network="Base"
      safeAddress={address}
      baskets={baskets}
      priceDeviationPct={priceDeviationPct}
      lpFeePct={lpFeePct}
      signaturesRequired={threshold ?? 1}
      onBack={() => router.push("/setup/parameters")}
      onCreateTransaction={handleCreateTransaction}
      isCreatingTransaction={isCreating}
      createTransactionError={createError}
    />
  );
}
