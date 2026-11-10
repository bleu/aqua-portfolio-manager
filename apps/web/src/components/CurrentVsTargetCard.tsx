import type { ReactNode } from "react";
import { AllocationBar, type AllocationBarProps } from "@/components/AllocationBar";
import { Badge } from "@/components/Badge";
import { ArrowUpRightIcon } from "@/components/icons";
import { cn } from "@/lib/cn";

export type CurrentVsTargetCardProps = {
  title?: string;
  subtitle?: string;
  baskets: AllocationBarProps[];
  footerNote?: string;
  className?: string;
};

function LegendItem({ children, swatch }: { children: ReactNode; swatch: ReactNode }) {
  return (
    <span className="inline-flex items-center gap-2 text-sm text-gray-400">
      {swatch}
      {children}
    </span>
  );
}

/**
 * Static illustration of how Aqua routing rebalances a 2-basket portfolio toward its target
 * weights -- the entry page's preview of the mechanic, before a Safe is connected.
 */
export function CurrentVsTargetCard({
  title = "Current vs. target",
  subtitle = "How Aqua routing rebalances the portfolio",
  baskets,
  footerNote = "Eligible routed trades earn LP fees for your portfolio.",
  className,
}: CurrentVsTargetCardProps) {
  return (
    <div className={cn("rounded-2xl border border-border bg-surface-card p-6", className)}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-lg font-semibold text-white">{title}</h2>
          <p className="mt-1 text-sm text-gray-400">{subtitle}</p>
        </div>
        <Badge variant="dot">Aqua routing</Badge>
      </div>

      {/* Confirmed on the real card (node 680:20954's "Chart legend"): the current-allocation
          swatch is a mint gradient with a border, not a flat tint; "Gap to target" is a distinct
          purple (var(--color-purple-400, #bfb6c9)), not accent at all; "Target" is its own glyph
          asset, not a plain dot. */}
      <div className="mt-4 flex flex-wrap items-center gap-4">
        <LegendItem
          swatch={<span className="h-2 w-[18px] rounded-sm border border-accent-muted bg-gradient-to-b from-accent to-accent-muted" />}
        >
          Current allocation
        </LegendItem>
        <LegendItem swatch={<span className="h-2 w-[18px] rounded-sm bg-difference" />}>Gap to target</LegendItem>
        <LegendItem swatch={<img src="/target-symbol.svg" alt="" className="h-3.5 w-[11px]" />}>Target</LegendItem>
      </div>

      <div className="mt-5 flex flex-col gap-4">
        {baskets.map((basket) => (
          <AllocationBar key={basket.label} {...basket} />
        ))}
      </div>

      <div className="mt-4 flex items-center gap-3 rounded-xl bg-surface-raised px-4 py-3.5">
        <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-accent/30 text-white">
          <ArrowUpRightIcon className="size-3.5" />
        </span>
        <span className="text-sm text-white">{footerNote}</span>
      </div>
    </div>
  );
}
