import type { ReactNode } from "react";

export type InfoBannerProps = {
  children: ReactNode;
};

/** The left-accent note strip used to add a short explanatory aside under a form or summary. */
export function InfoBanner({ children }: InfoBannerProps) {
  return (
    <div className="flex items-start gap-3 rounded-lg border border-border bg-surface-raised px-4 py-3">
      <span className="mt-0.5 h-full w-0.5 self-stretch rounded-full bg-accent" aria-hidden="true" />
      <p className="text-sm text-gray-400">{children}</p>
    </div>
  );
}
