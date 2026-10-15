import type { ReactNode } from "react";

export type InfoBannerProps = {
  children: ReactNode;
};

/** The left-accent note strip used to add a short explanatory aside under a form or summary. */
export function InfoBanner({ children }: InfoBannerProps) {
  return (
    <div className="flex items-center gap-3 rounded-lg border border-border bg-surface-raised px-4 py-3">
      <span
        className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-gray-700 text-[10px] font-semibold text-gray-300"
        aria-hidden="true"
      >
        i
      </span>
      <p className="text-sm text-gray-400">{children}</p>
    </div>
  );
}
