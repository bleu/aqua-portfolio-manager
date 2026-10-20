"use client";

import { useRouter } from "next/navigation";
import { SetStrategyParametersPage } from "@/components/pages/SetStrategyParametersPage";
import { saveDraftParameters } from "@/lib/parametersDraftStorage";
import { useVerifiedSafeAddress } from "@/lib/useVerifiedSafeAddress";

export default function Page() {
  const router = useRouter();
  const address = useVerifiedSafeAddress();

  if (!address) {
    return <div className="min-h-screen" />;
  }

  return (
    <SetStrategyParametersPage
      network="Base"
      safeAddress={address}
      onBack={() => router.push("/setup/targets")}
      onContinue={(params) => {
        saveDraftParameters(address, params);
        router.push("/setup/review");
      }}
    />
  );
}
