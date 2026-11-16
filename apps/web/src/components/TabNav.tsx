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

/** The "Portfolio Manager" / "History" tab row in the app header. Figma's own menu-item (node
 *  546:25611 and siblings, confirmed on the Baskets-Filled flow screen) is plain text, colored by
 *  state, with no pill background on the active item. */
export function TabNav({ tabs, onSelect }: TabNavProps) {
  return (
    <nav className="flex items-center gap-8" aria-label="Primary">
      {tabs.map((tab) => (
        <button
          key={tab.label}
          type="button"
          onClick={() => onSelect?.(tab.label)}
          aria-current={tab.active ? "page" : undefined}
          className={cn(
            "text-sm font-medium transition-colors",
            tab.active ? "text-accent" : "text-white/50 hover:text-white/80",
          )}
        >
          {tab.label}
        </button>
      ))}
    </nav>
  );
}
