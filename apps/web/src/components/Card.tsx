import type { HTMLAttributes, ReactNode } from "react";
import { cn } from "@/lib/cn";

const PADDING = {
  spacious: "p-8",
  default: "p-6",
  compact: "p-4",
};

const RADIUS = {
  default: "rounded-xl",
  lg: "rounded-2xl",
};

export type CardProps = HTMLAttributes<HTMLDivElement> & {
  children: ReactNode;
  /** "spacious" for a large standalone panel, "compact" for a list item built on Card. */
  padding?: keyof typeof PADDING;
  /** "lg" for a rounder corner on a small standalone card (e.g. GroupSummaryCard). */
  radius?: keyof typeof RADIUS;
};

/** Base dark bordered panel surface other components (GroupSummaryCard, EmptyState, basket panels) build on. */
export function Card({ children, padding = "default", radius = "default", className, ...rest }: CardProps) {
  return (
    <div
      className={cn("border border-border bg-surface-card", PADDING[padding], RADIUS[radius], className)}
      {...rest}
    >
      {children}
    </div>
  );
}
