"use client";

import { useRouter } from "next/navigation";
import { FirstAccessIntroductionPage } from "@/components/pages/FirstAccessIntroductionPage";
import { currentAllocation, targetAllocation } from "@/lib/mockData";

export default function Page() {
  const router = useRouter();
  return (
    <FirstAccessIntroductionPage
      currentAllocation={currentAllocation}
      targetAllocation={targetAllocation}
      onSetUp={() => router.push("/dashboard")}
    />
  );
}
