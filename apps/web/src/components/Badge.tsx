import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export type BadgeProps = {
  children: ReactNode;
  /** Optional leading status dot color (e.g. a network's brand color). */
  dotColor?: string;
  className?: string;
};

/** Base small-pill primitive. NetworkBadge and AddressBadge are configurations of this component. */
export function Badge({ children, dotColor, className }: BadgeProps) {
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
