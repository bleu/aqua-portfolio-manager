import { Button } from "@/components/Button";
import { Card } from "@/components/Card";
import { GroupSummaryCard } from "@/components/GroupSummaryCard";
import { InfoBanner } from "@/components/InfoBanner";
import { RoutedTradesConnector } from "@/components/RoutedTradesConnector";
import type { GroupSummary } from "@/lib/types";

export type FirstAccessIntroductionPageProps = {
  currentAllocation: GroupSummary[];
  targetAllocation: GroupSummary[];
  onSetUp?: () => void;
};

/**
 * BLEUDEV-409 — "02 · First-access introduction": explains how Portfolio Manager works before
 * setup, shown once after wallet connection. The outer app chrome (brand/tabs/badges) is its own
 * reusable AppHeader, built in BLEUDEV-410 and composed around this page at the route level.
 */
export function FirstAccessIntroductionPage({
  currentAllocation,
  targetAllocation,
  onSetUp,
}: FirstAccessIntroductionPageProps) {
  return (
    <div className="mx-auto max-w-3xl px-6 py-16 text-center">
      <p className="text-xs font-semibold tracking-wider text-accent">HOW IT WORKS</p>
      <h1 className="mt-3 text-4xl font-semibold text-white">Set the exposure you want to maintain</h1>
      <p className="mx-auto mt-4 max-w-xl text-sm text-gray-400">
        Group your managed tokens and set each group&apos;s target share. Portfolio Manager uses trades routed
        through Aqua to move exposure toward those targets while your portfolio earns LP fees.
      </p>

      <Card className="mt-10 text-left">
        <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-6">
          <div className="space-y-3">
            <p className="text-xs font-medium tracking-wide text-gray-500">CURRENT ALLOCATION</p>
            {currentAllocation.map((group) => (
              <GroupSummaryCard key={group.id} group={group} />
            ))}
          </div>

          <RoutedTradesConnector />

          <div className="space-y-3">
            <p className="text-xs font-medium tracking-wide text-gray-500">TARGET ALLOCATION</p>
            {targetAllocation.map((group) => (
              <GroupSummaryCard key={group.id} group={group} showProgress />
            ))}
          </div>
        </div>

        <div className="mt-6">
          <InfoBanner>Routed trades move allocation toward them while your portfolio earns LP fees.</InfoBanner>
        </div>
      </Card>

      <div className="mt-8">
        <Button onClick={onSetUp}>Set up Portfolio Manager</Button>
      </div>
    </div>
  );
}
