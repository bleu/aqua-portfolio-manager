import type { ReactNode } from "react";
import { AllocationBar, type AllocationBarProps } from "@/components/AllocationBar";
import { cn } from "@/lib/cn";

export type CurrentVsTargetCardProps = {
  baskets: AllocationBarProps[];
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
 * weights -- the entry page's preview of the mechanic, before a Safe is connected. Matches the
 * real "Portfolio preview" card (node 680:20954) exactly: legend, then basket rows -- no title,
 * subtitle, "Aqua routing" badge, or footer note. An earlier pass added all four on the
 * assumption an older reference screenshot required them; a confirmed-correct Figma screenshot
 * showed the real card has none of that.
 */
export function CurrentVsTargetCard({ baskets, className }: CurrentVsTargetCardProps) {
  return (
    <div className={cn("rounded-2xl bg-surface-card p-6", className)}>
      {/* Confirmed on the real card's "Chart legend": the current-allocation swatch is a mint
          gradient with a border, not a flat tint; "Gap to target" is a distinct purple
          (var(--color-purple-400, #bfb6c9)), not accent at all; "Target" is its own glyph asset,
          not a plain dot. */}
      <div className="flex flex-wrap items-center gap-4">
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
    </div>
  );
}
