import { ArrowLeftIcon, ArrowRightIcon, PinIcon } from "@/components/icons";
import { cn } from "@/lib/cn";

export type AllocationBarProps = {
  /** Basket name, e.g. "Crypto majors". */
  label: string;
  /** Current allocation, as a percent of the whole portfolio (0-100). */
  currentPct: number;
  /** Target allocation, as a percent of the whole portfolio (0-100). */
  targetPct: number;
  /** Short sentence explaining which way routing moves this basket. */
  caption: string;
  /** This basket's own brand color (hex), e.g. Trim's Mint or Salmon -- each basket gets a
   *  distinct color, not a shared accent (confirmed in Figma: the allocation visualization
   *  names its two ribbons "mint / allocation edge" and "salmon / allocation edge"). Defaults
   *  to the shared accent for callers that don't pass one. */
  color?: string;
  className?: string;
};

function formatPct(value: number): string {
  return `${Number(value.toFixed(1))}%`;
}

/**
 * One basket's current-vs-target row: a filled bar up to the lower of the two values, a
 * highlighted "gap to target" segment spanning the difference (carrying a directional arrow),
 * and a pin marking the target position.
 */
export function AllocationBar({
  label,
  currentPct,
  targetPct,
  caption,
  color = "#94cad1",
  className,
}: AllocationBarProps) {
  const lower = Math.min(currentPct, targetPct);
  const upper = Math.max(currentPct, targetPct);
  const gapWidth = upper - lower;
  const isShrinking = targetPct < currentPct;

  return (
    <div className={cn("rounded-xl border border-border p-5", className)}>
      <div className="flex items-baseline justify-between gap-4">
        <span className="font-semibold text-white">{label}</span>
        <span className="text-sm text-gray-400">
          Current {formatPct(currentPct)} · Target {formatPct(targetPct)}
        </span>
      </div>

      <div className="relative mt-4 pt-3">
        <div className="relative flex h-10 overflow-hidden rounded-lg border border-border bg-surface">
          <div style={{ width: `${lower}%`, backgroundColor: `${color}66` }} />
          {gapWidth > 0 && (
            <div
              className={cn("flex items-center justify-center text-white", isShrinking ? "border-r-2" : "border-l-2")}
              style={{ width: `${gapWidth}%`, backgroundColor: color, borderColor: color }}
            >
              {isShrinking ? <ArrowLeftIcon className="size-4" /> : <ArrowRightIcon className="size-4" />}
            </div>
          )}
          <div className="absolute inset-y-0 w-[3px] -translate-x-1/2 bg-white" style={{ left: `${targetPct}%` }} />
        </div>
        <PinIcon
          className="absolute top-1.5 size-3 -translate-x-1/2 text-white"
          style={{ left: `${targetPct}%` }}
        />
      </div>

      <div className="mt-3 flex items-center gap-2 text-sm text-gray-400">
        <span className="size-1.5 shrink-0 rounded-full" style={{ backgroundColor: color }} />
        {caption}
      </div>
    </div>
  );
}
