import type { HTMLAttributes, ReactNode } from "react";
import { cn } from "@/lib/cn";

export type CardProps = HTMLAttributes<HTMLDivElement> & {
  children: ReactNode;
  /** Tighter padding for compact contexts (e.g. a list item built on Card). */
  padding?: "default" | "compact";
};

/** Base dark bordered panel surface other components (GroupSummaryCard, EmptyState, basket panels) build on. */
export function Card({ children, padding = "default", className, ...rest }: CardProps) {
  return (
    <div
      className={cn(
        "rounded-xl border border-border bg-surface-card",
        padding === "default" ? "p-6" : "p-4",
        className,
      )}
      {...rest}
    >
      {children}
    </div>
  );
}
