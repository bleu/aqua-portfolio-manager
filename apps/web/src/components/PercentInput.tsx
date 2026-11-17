"use client";

import { cn } from "@/lib/cn";

export type PercentInputProps = {
  value: number;
  onChange?: (value: number) => void;
  min?: number;
  max?: number;
  disabled?: boolean;
  className?: string;
};

/** Bordered numeric field with a trailing "%" suffix -- the "Custom %" trailing field used by
 *  ChoicePillGroup's preset pickers (Targets/Parameters). Pill-shaped and chip-height (48px,
 *  min-width 120px) per the Round 2 design spec, matching the preset pills it sits beside. */
export function PercentInput({ value, onChange, min, max, disabled, className }: PercentInputProps) {
  return (
    <div
      className={cn(
        "flex min-w-[120px] items-center justify-end gap-1 rounded-full border border-border bg-surface-raised px-4 py-2",
        "focus-within:border-accent",
        disabled && "cursor-not-allowed opacity-50",
        className,
      )}
    >
      <input
        type="number"
        inputMode="decimal"
        value={Number.isFinite(value) ? value : ""}
        onChange={(e) => onChange?.(e.target.valueAsNumber)}
        min={min}
        max={max}
        step="any"
        disabled={disabled}
        className="w-full min-w-0 bg-transparent text-right text-sm text-gray-100 outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
      />
      <span className="shrink-0 text-sm text-gray-500">%</span>
    </div>
  );
}
