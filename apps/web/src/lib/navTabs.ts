import type { TabNavItem } from "@/components/TabNav";

export type NavTabKey = "home" | "portfolio-manager" | "activity";

/** The shared Home / Portfolio Manager / Activity header nav, confirmed identical across every
 *  Claude Artifact screen's `<nav class="nav">`. Every wizard/dashboard/history page built its
 *  own 2-item `Portfolio Manager · History` array before this -- centralized here so the 3 items
 *  and the active one can't drift per page again. "History" is this app's existing route name for
 *  what the artifact calls "Activity"; the nav label changes, the route (`/dashboard/history`)
 *  does not. */
export function buildNavTabs(active: NavTabKey): TabNavItem[] {
  return [
    { label: "Home", active: active === "home" },
    { label: "Portfolio Manager", active: active === "portfolio-manager" },
    { label: "Activity", active: active === "activity" },
  ];
}
