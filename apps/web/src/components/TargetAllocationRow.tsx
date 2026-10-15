import { PercentInput } from "./PercentInput";
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

/** One basket's row in the Targets table: name + token list (left), current allocation (middle),
 *  editable or read-only target % (right). */
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
    <div className={cn("flex items-center justify-between gap-4 py-3", className)}>
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: color }} />
          <span className="font-medium text-white">{name}</span>
        </div>
        <p className="mt-0.5 truncate text-xs text-gray-500">{tokenSymbols.join(" · ")}</p>
      </div>

      {!readOnly && (
        <div className="shrink-0 text-right">
          <p className="text-sm text-white">{currentPct.toFixed(1)}%</p>
          <p className="text-xs text-gray-500">{formatUsd(currentValue)}</p>
        </div>
      )}

      <div className="w-28 shrink-0">
        {readOnly ? (
          <p className="text-right text-sm text-white">{targetPct.toFixed(1)}%</p>
        ) : (
          <PercentInput value={Number(targetPct.toFixed(1))} onChange={onTargetChange} min={0} max={100} />
        )}
      </div>
    </div>
  );
}
