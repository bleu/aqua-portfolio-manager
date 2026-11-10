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
  className?: string;
};

function formatPct(value: number): string {
  return `${Number(value.toFixed(1))}%`;
}

/**
 * One basket's current-vs-target row: a filled bar up to the lower of the two values, a
 * highlighted "gap to target" segment spanning the difference (carrying a directional arrow),
 * and a marker pinpointing the target position. Styling confirmed directly on the real landing
 * page's own basket rows (nodes 680:20967 and 680:20980) -- bar widths stay percentage-driven
 * from real data rather than copying that static mockup's illustrative fixed pixel widths.
 */
export function AllocationBar({ label, currentPct, targetPct, caption, className }: AllocationBarProps) {
  const lower = Math.min(currentPct, targetPct);
  const upper = Math.max(currentPct, targetPct);
  const gapWidth = upper - lower;
  const isShrinking = targetPct < currentPct;

  return (
    <div className={cn("rounded-[10px] bg-gradient-to-r from-white/[0.02] to-white/[0.04] p-[14px]", className)}>
      <div className="flex items-baseline justify-between gap-4">
        <span className="text-[17px] font-bold text-ink-primary">{label}</span>
        <span className="text-[14px] text-ink-muted">
          Current {formatPct(currentPct)} · Target {formatPct(targetPct)}
        </span>
      </div>

      <div className="relative mt-3.5 h-11 overflow-hidden rounded-lg border border-border-subtle bg-surface">
        <div
          className="absolute inset-y-0 left-0 rounded-l-md border border-accent-muted bg-gradient-to-b from-accent to-accent-muted"
          style={{ width: `${lower}%` }}
        />
        {gapWidth > 0 && (
          <div
            className="absolute inset-y-0 flex items-center justify-center bg-difference text-[20px] font-semibold text-surface-card"
            style={{ left: `${lower}%`, width: `${gapWidth}%` }}
          >
            {isShrinking ? "←" : "→"}
          </div>
        )}
        <div className="absolute inset-y-0 w-[3px] -translate-x-1/2 bg-[#f5f7fa]" style={{ left: `${targetPct}%` }} />
      </div>

      <div className="mt-2 flex items-center gap-2 text-[14px] text-ink-muted">
        <span className="size-1.5 shrink-0 rounded-full bg-accent" />
        {caption}
      </div>
    </div>
  );
}
