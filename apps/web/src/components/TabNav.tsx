"use client";

import { cn } from "@/lib/cn";

export type TabNavItem = {
  label: string;
  active?: boolean;
};

export type TabNavProps = {
  tabs: TabNavItem[];
  onSelect?: (label: string) => void;
};

/** The "Portfolio Manager" / "History" tab row in the app header. */
export function TabNav({ tabs, onSelect }: TabNavProps) {
  return (
    <nav className="flex items-center gap-1" aria-label="Primary">
      {tabs.map((tab) => (
        <button
          key={tab.label}
          type="button"
          onClick={() => onSelect?.(tab.label)}
          aria-current={tab.active ? "page" : undefined}
          className={cn(
            "rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
            tab.active ? "bg-accent/20 text-accent" : "text-gray-400 hover:text-gray-200",
          )}
        >
          {tab.label}
        </button>
      ))}
    </nav>
  );
}
