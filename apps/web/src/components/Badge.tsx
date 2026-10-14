import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export type BadgeProps = {
  children: ReactNode;
  /**
   * `outline` — uppercase, bordered, tinted-background label (e.g. "SAFE SMART ACCOUNT REQUIRED").
   * `dot` — rounded pill with a leading accent-color dot (e.g. "Aqua routing").
   * `header` — plain bordered pill, normal case (the network/Safe-address badges in AppHeader).
   */
  variant?: "outline" | "dot" | "header";
  /** Only meaningful for variant="header": colors its optional leading dot. Omit for no dot. */
  dotColor?: string;
  className?: string;
};

export function Badge({ children, variant = "outline", dotColor, className }: BadgeProps) {
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

  if (variant === "header") {
    return (
      <span
        className={cn(
          "inline-flex items-center gap-1.5 rounded-full border border-border px-3 py-1 text-xs font-medium text-gray-200",
          className,
        )}
      >
        {dotColor && <span className="size-1.5 rounded-full" style={{ backgroundColor: dotColor }} />}
        {children}
      </span>
    );
  }

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
