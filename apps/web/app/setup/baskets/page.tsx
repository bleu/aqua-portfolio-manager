"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { base } from "wagmi/chains";
import { CreateBasketsPage } from "@/components/pages/CreateBasketsPage";
import { initialBaskets } from "@/lib/mockBaskets";
import { saveBalancesSnapshot } from "@/lib/safeBalancesSnapshot";
import { useSafeBalances } from "@/lib/useSafeBalances";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  const router = useRouter();
  const address = useVerifiedSafeAddress();
  const { tokens, isLoading } = useSafeBalances(address);
  // Base is the only chain wagmi.ts configures -- wagmi still reports whatever chain the wallet
  // actually sits on, so this is a real check, not a redundant one.
  const { chain } = useAccount();

  // Step 1 is the only place the wizard's balance snapshot gets (re-)written -- every other step
  // reads it, never writes it, so a basket's managed value can't drift between steps just
  // because live prices moved. Re-entering this step (e.g. via Back) intentionally refreshes it.
  useEffect(() => {
    if (address && !isLoading && tokens.length > 0) saveBalancesSnapshot(address, tokens);
  }, [address, isLoading, tokens]);

  if (!address) {
    return <div className="min-h-screen" />;
  }

  return (
    <CreateBasketsPage
      network={chain?.name ?? "Base"}
      safeAddress={address}
      baskets={initialBaskets}
      safeTokens={tokens}
      tokensLoading={isLoading}
      isUnsupportedNetwork={chain !== undefined && chain.id !== base.id}
      onContinue={() => router.push("/setup/targets")}
      onSelectTab={(label) => {
        if (label === "Activity") router.push("/dashboard/history");
        if (label === "Home") router.push("/dashboard");
      }}
    />
  );
}
