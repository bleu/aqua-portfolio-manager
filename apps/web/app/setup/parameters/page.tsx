"use client";

import { useRouter } from "next/navigation";
import { useAccount } from "wagmi";
import { SetStrategyParametersPage } from "@/components/pages/SetStrategyParametersPage";

export default function Page() {
  const router = useRouter();
  const { address } = useAccount();

  if (!address) {
    return <div className="min-h-screen" />;
  }

  return (
    <SetStrategyParametersPage
      network="Base"
      safeAddress={address}
      onBack={() => router.push("/setup/targets")}
      onContinue={() => router.push("/setup/review")}
    />
  );
}
