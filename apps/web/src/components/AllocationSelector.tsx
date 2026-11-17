"use client";

import { cn } from "@/lib/cn";
import { formatUsd } from "@/lib/format";

export type AllocationSelectorProps = {
  value: number;
  valueUsd: number;
  onChange?: (value: number) => void;
  min?: number;
  max?: number;
  disabled?: boolean;
  className?: string;
};

/** The per-basket target-percent input in the Targets table ("Allocation selector", node
 *  680:20802, "2. Targets" flow screen): a boxed number entry with its $ equivalent shown below
 *  it, not PercentInput's compact single-line field (that one's shared with ChoicePillGroup's
 *  "Custom %" trailing field, a genuinely different, smaller context left alone here). */
export function AllocationSelector({ value, valueUsd, onChange, min, max, disabled, className }: AllocationSelectorProps) {
  return (
    <div
      className={cn(
        "flex w-[123px] shrink-0 flex-col items-end gap-1 rounded-[20px] border-2 border-[#292c30] bg-surface-raised p-4",
        "focus-within:border-accent",
        disabled && "cursor-not-allowed opacity-50",
        className,
      )}
    >
      <div className="flex items-center gap-1">
        <input
          type="number"
          inputMode="decimal"
          value={Number.isFinite(value) ? value : ""}
          onChange={(e) => onChange?.(e.target.valueAsNumber)}
          min={min}
          max={max}
          step="any"
          disabled={disabled}
          className="w-12 min-w-0 bg-transparent text-right text-base text-[#f8f8fc] outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
        />
        <span className="shrink-0 text-base text-[#85898c]">%</span>
      </div>
      <span className="text-xs text-[#a3a3a3]">{formatUsd(valueUsd)}</span>
    </div>
  );
}
