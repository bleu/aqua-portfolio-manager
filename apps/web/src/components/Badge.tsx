import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export type BadgeProps = {
  children: ReactNode;
  /**
   * `plain` (default) — bordered pill, with an optional custom-colored leading dot via
   *   `dotColor` (e.g. NetworkBadge's brand color; AddressBadge uses no dot at all).
   * `outline` — uppercase, bordered, tinted-background label (e.g. "SAFE SMART ACCOUNT REQUIRED").
   * `dot` — rounded pill with a leading accent-colored dot (e.g. "Aqua routing").
   */
  variant?: "plain" | "outline" | "dot";
  /** Only meaningful for the `plain` variant -- a custom leading dot color. */
  dotColor?: string;
  className?: string;
};

/** Base small-pill primitive. NetworkBadge and AddressBadge are `plain`-variant configurations. */
export function Badge({ children, variant = "plain", dotColor, className }: BadgeProps) {
  if (variant === "dot") {
    return (
      <span
        className={cn(
          "inline-flex items-center gap-2 rounded-full bg-surface-raised px-3.5 py-1.5 text-sm font-medium text-white",
          className,
        )}
      >
        <span className="size-1.5 rounded-full bg-accent" />
        {children}
      </span>
    );
  }

  if (variant === "outline") {
    return (
      <span
        className={cn(
          "inline-flex items-center rounded-full bg-accent/15 px-3 py-1 text-xs font-semibold tracking-wide text-accent uppercase",
          className,
        )}
      >
        {children}
      </span>
    );
  }

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full border border-border bg-surface-raised px-3 py-1 text-xs font-medium text-gray-300",
        className,
      )}
    >
      {dotColor && <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: dotColor }} />}
      {children}
    </span>
  );
}
