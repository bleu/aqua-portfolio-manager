import { Fragment } from "react";
import { AppHeader } from "@/components/AppHeader";
import { Button } from "@/components/Button";
import { Card } from "@/components/Card";
import { GroupSummaryCard } from "@/components/GroupSummaryCard";
import { InfoBanner } from "@/components/InfoBanner";
import { RoutedTradesConnector } from "@/components/RoutedTradesConnector";
import type { GroupSummary } from "@/lib/types";

export type FirstAccessIntroductionPageProps = {
  network: string;
  safeAddress: string;
  currentAllocation: GroupSummary[];
  targetAllocation: GroupSummary[];
  onSetUp?: () => void;
};

/**
 * BLEUDEV-409 — "02 · First-access introduction": explains how Portfolio Manager works before
 * setup, shown once after wallet connection. No tab nav yet -- there's nothing to switch to
 * before a strategy exists.
 */
export function FirstAccessIntroductionPage({
  network,
  safeAddress,
  currentAllocation,
  targetAllocation,
  onSetUp,
}: FirstAccessIntroductionPageProps) {
  return (
    <div>
      <AppHeader network={network} safeAddress={safeAddress} />

      <div className="mx-auto max-w-5xl px-6 py-16 text-center">
        <p className="text-xs font-semibold tracking-wider text-accent">HOW IT WORKS</p>
        <h1 className="mt-3 text-4xl font-semibold text-white">Set the exposure you want to maintain</h1>
        <p className="mx-auto mt-4 max-w-2xl text-sm text-gray-400">
          Group your managed tokens and set each group&apos;s target share. Portfolio Manager uses trades routed
          through Aqua to move exposure toward those targets while your portfolio earns LP fees.
        </p>

        <Card padding="spacious" className="mt-14 text-left">
          {/* Each pair (current/target row) is emitted as its own grid row so CSS Grid's default
              row-stretch makes left and right boxes match height -- a target card with just a
              progress bar would otherwise be shorter than its current-side counterpart's token
              chip row. */}
          <div className="grid grid-cols-[1fr_auto_1fr] gap-x-6 gap-y-3">
            <p className="text-xs font-medium tracking-wide text-gray-500">CURRENT ALLOCATION</p>
            <div />
            <p className="text-xs font-medium tracking-wide text-gray-500">TARGET ALLOCATION</p>

            {currentAllocation.map((group, index) => (
              <Fragment key={group.id}>
                <GroupSummaryCard group={group} showIndicator={false} />
                {index === 0 && (
                  <RoutedTradesConnector style={{ gridRow: `span ${currentAllocation.length}` }} />
                )}
                {targetAllocation[index] && (
                  <GroupSummaryCard
                    group={targetAllocation[index]}
                    showIndicator={false}
                    showProgress
                    progressTone={index === 0 ? "accent" : "neutral"}
                    showTokens={false}
                  />
                )}
              </Fragment>
            ))}
          </div>

          <div className="mt-6">
            <InfoBanner>Routed trades move allocation toward them while your portfolio earns LP fees.</InfoBanner>
          </div>
        </Card>

        <div className="mt-8">
          <Button onClick={onSetUp}>Set up Portfolio Manager</Button>
        </div>
      </div>
    </div>
  );
}
