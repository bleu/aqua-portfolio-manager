"use client";

import { PercentInput } from "./PercentInput";
import { cn } from "@/lib/cn";

export type ChoicePillGroupProps = {
  options: number[];
  /** undefined means nothing is selected yet (e.g. a required field with no default). */
  value: number | undefined;
  onChange: (value: number) => void;
  disabled?: boolean;
  className?: string;
};

/** A single-select row of preset value pills, plus a trailing "Custom" PercentInput -- used for
 *  both the Targets/Parameters percentage pickers and the dashboard's time-range selector.
 *  Not the same as TokenChip's `toggle` variant, which is multi-select filtering. */
export function ChoicePillGroup({ options, value, onChange, disabled, className }: ChoicePillGroupProps) {
  const isCustomValue = value !== undefined && !options.includes(value);

  return (
    <div className={cn("flex flex-wrap items-center gap-2", className)}>
      {options.map((option) => {
        const selected = value === option;
        return (
          <button
            key={option}
            type="button"
            disabled={disabled}
            onClick={() => onChange(option)}
            aria-pressed={selected}
            className={cn(
              "rounded-lg border px-3 py-2 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50",
              selected
                ? "border-accent bg-accent/20 text-white"
                : "border-border bg-surface-raised text-gray-300 hover:border-accent/60",
            )}
          >
            {option}%
          </button>
        );
      })}
      <span className="text-xs text-gray-500">or</span>
      <PercentInput
        value={isCustomValue ? value : Number.NaN}
        onChange={onChange}
        disabled={disabled}
        placeholder="Custom"
        className={cn("w-24", isCustomValue && "border-accent")}
      />
    </div>
  );
}
