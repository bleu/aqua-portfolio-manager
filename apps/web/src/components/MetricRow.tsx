import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export type MetricRowProps = {
  label: string;
  value: ReactNode;
  caption?: string;
  /** The Portfolio overview card's one headline metric (Total managed value) renders larger than
   *  the stacked ones below it. */
  size?: "default" | "large";
  divider?: boolean;
};

/** A stacked label/value/caption metric, used by the dashboard's Portfolio overview card.
 *  Distinct from StatColumn (BLEUDEV-418), which is a horizontal big-number-over-caption layout
 *  with no label line and no divider. */
export function MetricRow({ label, value, caption, size = "default", divider }: MetricRowProps) {
  return (
    <div className={cn(divider && "border-t border-border pt-4")}>
      <p className="text-sm text-gray-400">{label}</p>
      <p className={cn("mt-1 font-bold text-white", size === "large" ? "text-3xl" : "text-xl")}>{value}</p>
      {caption && <p className="mt-1 text-xs text-gray-500">{caption}</p>}
    </div>
  );
}
