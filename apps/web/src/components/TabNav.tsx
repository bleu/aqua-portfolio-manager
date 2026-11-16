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

/** The Home / Portfolio Manager / Activity tab row in the app header. Confirmed directly on the
 *  Claude Artifact's own header markup (every `project/*.dc.html` screen shares the identical
 *  `<nav class="nav">`): plain text, colored by state, no pill background on the active item, the
 *  active item in the app's accent teal (#8fc9d0). */
export function TabNav({ tabs, onSelect }: TabNavProps) {
  return (
    <nav className="flex items-center gap-10" aria-label="Primary">
      {tabs.map((tab) => (
        <button
          key={tab.label}
          type="button"
          onClick={() => onSelect?.(tab.label)}
          aria-current={tab.active ? "page" : undefined}
          className={cn(
            "text-sm font-medium transition-colors",
            tab.active ? "text-[#8fc9d0]" : "text-[#8b9096] hover:text-white/80",
          )}
        >
          {tab.label}
        </button>
      ))}
    </nav>
  );
}
