import { cn } from "@/lib/cn";

export type ProgressBarProps = {
  /** 0-1 fraction filled. */
  value: number;
  /** Overrides the default accent fill -- e.g. one color per basket on the active dashboard. */
  color?: string;
  className?: string;
};

/** The target-share bar used alongside a GroupSummaryCard's percentage. */
export function ProgressBar({ value, color, className }: ProgressBarProps) {
  const clamped = Math.min(1, Math.max(0, value));
  return (
    <div
      className={cn("h-1.5 w-full overflow-hidden rounded-full bg-surface-raised", className)}
      role="progressbar"
      aria-valuenow={Math.round(clamped * 100)}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <div
        className={cn("h-full rounded-full", !color && "bg-accent")}
        style={{ width: `${clamped * 100}%`, backgroundColor: color }}
      />
    </div>
  );
}
