import { cn } from "@/lib/cn";

export type AllocationPreviewBarProps = {
  baskets: { id: string; name: string; color: string; targetPct: number }[];
  /** Inline status text shown at the far right of the legend row (e.g. "Matches current
   *  allocation → No initial rebalance") -- plain text in Figma's own reference (node 680:20846),
   *  not a badge/pill. */
  status?: string;
  className?: string;
};

/** A single stacked bar showing every basket's target share side by side, with a square-swatch
 *  legend below -- the whole-portfolio view, distinct from AllocationBar's one-basket-at-a-time
 *  current-vs-target comparison. Matches Figma's own preview bar (node 680:20835): 10px tall,
 *  rounded only at the two outer ends (8px), not a uniformly-rounded pill. */
export function AllocationPreviewBar({ baskets, status, className }: AllocationPreviewBarProps) {
  return (
    <div className={className}>
      <div className="flex h-[10px] w-full overflow-hidden rounded-[8px] bg-surface-raised">
        {baskets.map((basket) => (
          <div
            key={basket.id}
            style={{ width: `${basket.targetPct}%`, backgroundColor: basket.color }}
            title={`${basket.name} ${basket.targetPct.toFixed(0)}%`}
          />
        ))}
      </div>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-4">
          {baskets.map((basket) => (
            <span key={basket.id} className="inline-flex items-center gap-1.5 text-xs text-ink-muted">
              <span className={cn("size-[9px] shrink-0")} style={{ backgroundColor: basket.color }} />
              {basket.name} {basket.targetPct.toFixed(0)}%
            </span>
          ))}
        </div>
        {status && <span className="text-xs font-medium text-[#f1f4fa]">{status}</span>}
      </div>
    </div>
  );
}
