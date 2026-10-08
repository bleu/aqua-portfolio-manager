import { cn } from "@/lib/cn";

export type ProgressBarProps = {
  /** 0-1 fraction filled. */
  value: number;
  className?: string;
};

/** The target-share bar used alongside a GroupSummaryCard's percentage. */
export function ProgressBar({ value, className }: ProgressBarProps) {
  const clamped = Math.min(1, Math.max(0, value));
  return (
    <div
      className={cn("h-1.5 w-full overflow-hidden rounded-full bg-surface-raised", className)}
      role="progressbar"
      aria-valuenow={Math.round(clamped * 100)}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <div className="h-full rounded-full bg-accent" style={{ width: `${clamped * 100}%` }} />
    </div>
  );
}
