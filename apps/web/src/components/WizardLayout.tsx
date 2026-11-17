"use client";

import type { ReactNode } from "react";
import { AppHeader } from "./AppHeader";
import type { TabNavItem } from "./TabNav";
import { WizardStepper, type WizardStep } from "./WizardStepper";

export type WizardLayoutProps = {
  network: string;
  safeAddress: string;
  tabs: TabNavItem[];
  onSelectTab?: (label: string) => void;
  steps: WizardStep[];
  activeStepIndex: number;
  /** Baskets=1200, Targets/Parameters=1000, Review=700 -- the design's own per-step content
   *  widths. Centralizing it here (plus the stepper's fixed top margin below) is what stops the
   *  4 wizard pages from drifting to a different stepper Y position and content width each. */
  contentWidthPx: number;
  /** Rendered above the header, e.g. a one-time modal (WelcomeModal). */
  modal?: ReactNode;
  /** Rendered inside the width-constrained column, above the stepper and outside the dimmed
   *  wrapper below -- e.g. the unsupported-network or Safe-wallet banners. */
  banner?: ReactNode;
  /** True dims and disables everything below the banner -- the unsupported-network state. */
  dimmed?: boolean;
  /** Rendered after the content column, full width (e.g. Footer). */
  footer?: ReactNode;
  children: ReactNode;
};

export function WizardLayout({
  network,
  safeAddress,
  tabs,
  onSelectTab,
  steps,
  activeStepIndex,
  contentWidthPx,
  modal,
  banner,
  dimmed,
  footer,
  children,
}: WizardLayoutProps) {
  return (
    <div className="min-h-screen">
      {modal}
      <AppHeader tabs={tabs} network={network} safeAddress={safeAddress} onSelectTab={onSelectTab} />

      <div className="mx-auto px-6 py-8" style={{ maxWidth: contentWidthPx }}>
        {banner}
        <div className={dimmed ? "pointer-events-none opacity-30" : undefined}>
          <div className="mt-8">
            <WizardStepper steps={steps} activeIndex={activeStepIndex} />
          </div>
          <div className="mt-8">{children}</div>
        </div>
      </div>

      {footer}
    </div>
  );
}
