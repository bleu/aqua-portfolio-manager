import type { ReactNode } from "react";
import { Card } from "./Card";
import { cn } from "@/lib/cn";

export type NumberedStepCardProps = {
  index: number;
  title: string;
  subtitle: string;
  children?: ReactNode;
  className?: string;
};

/** A numbered-circle + title + subtitle wrapper around Card -- used by the Parameters page's two
 *  panels, and reused without a `children` body by the activated page's three explainer cards. */
export function NumberedStepCard({ index, title, subtitle, children, className }: NumberedStepCardProps) {
  return (
    <Card className={cn("space-y-4", className)}>
      <div className="flex items-start gap-3">
        <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-accent/20 text-xs font-semibold text-accent">
          {index}
        </span>
        <div>
          <h3 className="font-semibold text-white">{title}</h3>
          <p className="mt-1 text-sm text-gray-400">{subtitle}</p>
        </div>
      </div>
      {children}
    </Card>
  );
}
