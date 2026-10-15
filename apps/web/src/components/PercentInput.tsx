"use client";

import { cn } from "@/lib/cn";

export type PercentInputProps = {
  value: number;
  onChange?: (value: number) => void;
  min?: number;
  max?: number;
  disabled?: boolean;
  placeholder?: string;
  className?: string;
};

/** Bordered numeric field with a trailing "%" suffix -- the "Custom %" / target-percent input
 *  shared by the wizard's Targets and Parameters steps. */
export function PercentInput({ value, onChange, min, max, disabled, placeholder, className }: PercentInputProps) {
  return (
    <div
      className={cn(
        "flex items-center gap-1 rounded-lg border border-border bg-surface-raised px-3 py-2",
        "focus-within:border-accent",
        disabled && "cursor-not-allowed opacity-50",
        className,
      )}
    >
      <input
        type="text"
        inputMode="decimal"
        // A native type="number" input renders its decimal separator per the browser's OS locale
        // (comma on e.g. pt-BR), not this app's own always-period formatting -- a plain text input
        // whose value we format ourselves keeps "70.1" consistent for every user, matching Figma.
        value={Number.isFinite(value) ? value.toString() : ""}
        onChange={(e) => {
          const raw = e.target.value.replace(",", ".");
          if (raw === "" || /^\d*\.?\d*$/.test(raw)) {
            const parsed = Number(raw);
            if (!Number.isNaN(parsed)) {
              const clamped = Math.min(max ?? 100, Math.max(min ?? 0, parsed));
              onChange?.(clamped);
            }
          }
        }}
        placeholder={placeholder}
        disabled={disabled}
        className="w-full min-w-0 bg-transparent text-right text-sm text-gray-100 outline-none placeholder:text-left placeholder:text-gray-500"
      />
      <span className="shrink-0 text-sm text-gray-500">%</span>
    </div>
  );
}
