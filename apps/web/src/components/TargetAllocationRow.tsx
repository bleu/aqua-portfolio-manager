import { AllocationRing } from "./AllocationRing";
import { AllocationSelector } from "./AllocationSelector";
import { cn } from "@/lib/cn";
import { formatUsd } from "@/lib/format";

export type TargetAllocationRowProps = {
  name: string;
  color: string;
  tokenSymbols: string[];
  currentPct: number;
  currentValue: number;
  targetPct: number;
  /** Omit (or pass no onTargetChange) to render the target as plain text -- the shape BLEUDEV-416's
   *  review page and BLEUDEV-418's activated page reuse, instead of forking a second row. */
  readOnly?: boolean;
  onTargetChange?: (value: number) => void;
  className?: string;
};

/** One basket's row in the Targets table (node 680:20781/680:20807, "2. Targets" flow screen):
 *  a standalone gradient sub-card, not a flat divided-list row -- ring + name/tokens on the
 *  left, the current allocation value in the middle, an editable (or read-only) target on the
 *  right. */
export function TargetAllocationRow({
  name,
  color,
  tokenSymbols,
  currentPct,
  currentValue,
  targetPct,
  readOnly,
  onTargetChange,
  className,
}: TargetAllocationRowProps) {
  return (
    <div
      className={cn(
        "flex w-full items-center justify-between gap-4 rounded-[30px] bg-gradient-to-r from-white/[0.02] to-white/[0.04] p-5",
        className,
      )}
    >
      <div className="flex min-w-0 items-center gap-3">
        <AllocationRing percentage={currentPct} color={color} size={40} className="shrink-0" />
        <div className="min-w-0">
          <p className="font-medium text-ink-primary">{name}</p>
          <p className="mt-0.5 truncate text-sm text-ink-secondary">{tokenSymbols.join(" · ")}</p>
        </div>
      </div>

      <div className="shrink-0 text-right">
        <p className="text-base font-medium text-[#f8fffe]">{currentPct.toFixed(0)}%</p>
        <p className="text-xs text-[#a3a3a3]">{formatUsd(currentValue)}</p>
      </div>

      {readOnly ? (
        <div className="w-[123px] shrink-0 text-right">
          <p className="text-base text-[#f8f8fc]">{targetPct.toFixed(0)}%</p>
          <p className="text-xs text-[#a3a3a3]">{formatUsd(currentValue)}</p>
        </div>
      ) : (
        <AllocationSelector
          value={Number(targetPct.toFixed(0))}
          valueUsd={currentValue}
          onChange={onTargetChange}
          min={0}
          max={100}
        />
      )}
    </div>
  );
}
