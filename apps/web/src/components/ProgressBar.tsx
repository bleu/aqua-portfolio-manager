import { cn } from "@/lib/cn";

export type ProgressBarProps = {
  /** 0-1 fraction filled. */
  value: number;
  /** "accent" highlights the fill (the primary group); "neutral" renders a plain gray fill for the rest. Ignored when `color` is set. */
  tone?: "accent" | "neutral";
  /** Overrides tone with an exact fill color -- e.g. one color per basket on the active dashboard. */
  color?: string;
  className?: string;
};

/** The target-share bar used alongside a GroupSummaryCard's percentage. */
export function ProgressBar({ value, tone = "accent", color, className }: ProgressBarProps) {
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
        className={cn("h-full rounded-full", !color && (tone === "accent" ? "bg-accent" : "bg-gray-500"))}
        style={{ width: `${clamped * 100}%`, ...(color ? { backgroundColor: color } : {}) }}
      />
    </div>
  );
}
