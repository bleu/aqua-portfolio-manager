"use client";

import { Card } from "./Card";
import { ProgressBar } from "./ProgressBar";
import { TokenChip } from "./TokenChip";
import { cn } from "@/lib/cn";
import { formatPercentage, formatUsd } from "@/lib/format";
import type { GroupSummary } from "@/lib/types";

function ChevronIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true" className="shrink-0 text-gray-500">
      <path d="M6 4l4 4-4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

export type GroupSummaryCardProps = {
  group: GroupSummary;
  /** Shows a ProgressBar under the trailing value (used by the target-allocation column). */
  showProgress?: boolean;
  /** Tone forwarded to the ProgressBar when showProgress is set. */
  progressTone?: "accent" | "neutral";
  /** Shows the group's colored dot next to its name. Default true. */
  showIndicator?: boolean;
  /** Shows the group's member token chips. Default true. */
  showTokens?: boolean;
  /** Tighter layout for a left-column basket list (BLEUDEV-411) vs. the larger allocation card (BLEUDEV-409). */
  compact?: boolean;
  onClick?: () => void;
};

/** Summarizes one group/basket: name, member tokens, and a trailing percentage or $ value, with an optional selected state and progress bar. Shared by the allocation comparison (BLEUDEV-409) and the basket list (BLEUDEV-411). */
export function GroupSummaryCard({
  group,
  showProgress,
  progressTone,
  showIndicator = true,
  showTokens = true,
  compact,
  onClick,
}: GroupSummaryCardProps) {
  const trailingLabel =
    group.trailing.kind === "percentage" ? formatPercentage(group.trailing.value) : formatUsd(group.trailing.value);

  const cardProps = {
    padding: "compact" as const,
    radius: "lg" as const,
    onClick,
    role: onClick ? ("button" as const) : undefined,
    tabIndex: onClick ? 0 : undefined,
    className: cn(
      onClick && "cursor-pointer transition-colors hover:border-accent/60",
      group.selected && "border-accent bg-surface-raised",
    ),
  };

  // Compact (basket list, BLEUDEV-411): name + chevron on one row, then a second row pairing
  // the plain-text token list with the trailing value -- a different layout from the larger
  // allocation card below, not just a smaller version of it.
  if (compact) {
    return (
      <Card {...cardProps} className={cn(cardProps.className, "space-y-1.5")}>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {showIndicator && (
              <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: group.color }} />
            )}
            <span className="text-sm font-medium text-gray-100">{group.name}</span>
          </div>
          {onClick && <ChevronIcon />}
        </div>

        <div className="flex items-center justify-between">
          {showTokens && (
            <span className="text-xs text-gray-500">{group.tokens.map((token) => token.symbol).join(" · ")}</span>
          )}
          <span className="text-sm font-semibold text-white">{trailingLabel}</span>
        </div>
      </Card>
    );
  }

  return (
    <Card {...cardProps} className={cn(cardProps.className, "space-y-3")}>
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          {showIndicator && (
            <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: group.color }} />
          )}
          <span className="text-base font-medium text-gray-100">{group.name}</span>
        </div>
        <span className="text-xl font-semibold text-white">{trailingLabel}</span>
      </div>

      {showProgress && group.trailing.kind === "percentage" && (
        <ProgressBar value={group.trailing.value} tone={progressTone} />
      )}

      {showTokens && (
        <div className="flex flex-wrap gap-1.5">
          {group.tokens.map((token) => (
            <TokenChip key={token.address} token={token} variant="display" showIcon={false} />
          ))}
        </div>
      )}
    </Card>
  );
}
