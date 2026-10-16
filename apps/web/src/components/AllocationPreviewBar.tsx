import { Badge } from "./Badge";
import { cn } from "@/lib/cn";

export type AllocationPreviewBarProps = {
  baskets: { id: string; name: string; color: string; targetPct: number }[];
  /** Shows a "No initial rebalance" badge on the legend row when true, omitted when false. */
  noInitialRebalance?: boolean;
  className?: string;
};

/** A single stacked bar showing every basket's target share side by side, with a colored-dot
 *  legend below -- the whole-portfolio view, distinct from AllocationBar's one-basket-at-a-time
 *  current-vs-target comparison. */
export function AllocationPreviewBar({ baskets, noInitialRebalance, className }: AllocationPreviewBarProps) {
  return (
    <div className={className}>
      <div className="flex h-3 w-full overflow-hidden rounded-full bg-surface-raised">
        {baskets.map((basket) => (
          <div
            key={basket.id}
            style={{ width: `${basket.targetPct}%`, backgroundColor: basket.color }}
            title={`${basket.name} ${basket.targetPct.toFixed(1)}%`}
          />
        ))}
      </div>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-4">
        <div className="flex flex-wrap items-center gap-4">
          {baskets.map((basket) => (
            <span key={basket.id} className="inline-flex items-center gap-2 text-sm text-gray-400">
              <span className={cn("h-2 w-2 shrink-0 rounded-full")} style={{ backgroundColor: basket.color }} />
              {basket.name} {basket.targetPct.toFixed(1)}%
            </span>
          ))}
        </div>
        {noInitialRebalance && (
          <Badge className="shrink-0">
            <span className="flex h-3.5 w-3.5 items-center justify-center rounded-full bg-accent text-[9px] text-white">
              ✓
            </span>
            No initial rebalance
          </Badge>
        )}
      </div>
    </div>
  );
}
