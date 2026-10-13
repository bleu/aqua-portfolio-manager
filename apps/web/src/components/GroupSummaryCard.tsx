import { Card } from "./Card";
import { ProgressBar } from "./ProgressBar";
import { TokenChip } from "./TokenChip";
import { cn } from "@/lib/cn";
import { formatPercentage, formatUsd } from "@/lib/format";
import type { GroupSummary } from "@/lib/types";

export type GroupSummaryCardProps = {
  group: GroupSummary;
  /** Shows a ProgressBar under the trailing value (used by the target-allocation column). */
  showProgress?: boolean;
  /** Tighter layout for a left-column basket list (BLEUDEV-411) vs. the larger allocation card (BLEUDEV-409). */
  compact?: boolean;
  onClick?: () => void;
};

/** Summarizes one group/basket: name, member tokens, and a trailing percentage or $ value, with an optional selected state and progress bar. Shared by the allocation comparison (BLEUDEV-409) and the basket list (BLEUDEV-411). */
export function GroupSummaryCard({ group, showProgress, compact, onClick }: GroupSummaryCardProps) {
  const trailingLabel =
    group.trailing.kind === "percentage" ? formatPercentage(group.trailing.value) : formatUsd(group.trailing.value);

  return (
    <Card
      padding="compact"
      onClick={onClick}
      role={onClick ? "button" : undefined}
      tabIndex={onClick ? 0 : undefined}
      className={cn(
        onClick && "cursor-pointer transition-colors hover:border-accent/60",
        group.selected && "border-accent bg-surface-raised",
        compact ? "space-y-1.5" : "space-y-3",
      )}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: group.color }} />
          <span className={cn("font-medium text-gray-100", compact ? "text-sm" : "text-base")}>{group.name}</span>
        </div>
        <span className={cn("font-semibold text-white", compact ? "text-sm" : "text-base")}>{trailingLabel}</span>
      </div>

      {showProgress && group.trailing.kind === "percentage" && <ProgressBar value={group.trailing.value} />}

      <div className="flex flex-wrap gap-1.5">
        {group.tokens.map((token) => (
          <TokenChip key={token.address} token={token} variant="display" />
        ))}
      </div>
    </Card>
  );
}
