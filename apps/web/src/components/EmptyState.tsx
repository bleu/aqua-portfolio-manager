import type { ReactNode } from "react";
import { Card } from "./Card";

export type EmptyStateProps = {
  icon?: ReactNode;
  heading: string;
  description: string;
  action?: ReactNode;
};

/** Generic icon + heading + description + CTA card, built on the shared Card surface. Used for the empty dashboard (BLEUDEV-410) and reusable anywhere else an empty state is needed. */
export function EmptyState({ icon, heading, description, action }: EmptyStateProps) {
  return (
    <Card className="flex flex-col items-center gap-4 py-16 text-center">
      {icon && (
        <span className="flex h-12 w-12 items-center justify-center rounded-full bg-accent/20 text-accent">
          {icon}
        </span>
      )}
      <div className="space-y-2">
        <h2 className="text-lg font-semibold text-white">{heading}</h2>
        <p className="mx-auto max-w-md text-sm text-gray-400">{description}</p>
      </div>
      {action}
    </Card>
  );
}
