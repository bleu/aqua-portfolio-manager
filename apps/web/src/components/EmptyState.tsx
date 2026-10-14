import type { ReactNode } from "react";
import { cn } from "@/lib/cn";
import { Card } from "./Card";

export type EmptyStateProps = {
  icon?: ReactNode;
  heading: string;
  description: string;
  action?: ReactNode;
  className?: string;
};

/** Generic icon + heading + description + CTA card, built on the shared Card surface. Used for the empty dashboard (BLEUDEV-410) and reusable anywhere else an empty state is needed. */
export function EmptyState({ icon, heading, description, action, className }: EmptyStateProps) {
  return (
    <Card className={cn("flex flex-col items-center justify-center gap-8 py-16 text-center", className)}>
      {icon && (
        /* Sized to match Figma's 88x88 circle in a 1438-wide frame (88/1438 ≈ 6.12vw). */
        <span className="flex h-[6.12vw] w-[6.12vw] items-center justify-center rounded-full bg-accent/20 text-accent">
          {icon}
        </span>
      )}
      <div className="space-y-2">
        <h2 className="text-lg font-semibold text-white">{heading}</h2>
        <p className="mx-auto max-w-xl text-sm text-gray-400">{description}</p>
      </div>
      {action}
    </Card>
  );
}
