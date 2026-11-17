import type { ReactNode } from "react";
import { cn } from "@/lib/cn";

export type BannerProps = {
  /** "info" (teal) for the Safe-wallet recommendation; "warning" (amber) for unsupported-network
   *  and risk-disclosure banners. */
  tone: "info" | "warning";
  icon: ReactNode;
  title: string;
  description: string;
  action?: ReactNode;
  className?: string;
};

/** The full-width banner shown above the wizard content (Safe wallet recommendation, unsupported
 *  network). Matches the design reference's two banner treatments exactly: "info" is a filled
 *  teal gradient with dark text; "warning" is an amber-outlined dark card with light text. */
export function Banner({ tone, icon, title, description, action, className }: BannerProps) {
  return (
    <div
      className={cn(
        "flex flex-wrap items-center justify-between gap-4 rounded-3xl px-5 py-4",
        tone === "info" && "bg-gradient-to-r from-[#d8eff1] to-[#9bcfd5] text-[#0e2226]",
        tone === "warning" && "border border-[#b79f6e] bg-[#14161a] text-white",
        className,
      )}
    >
      <div className="flex items-center gap-3.5">
        {icon}
        <div>
          <div className="text-base font-semibold">{title}</div>
          <div className={cn("mt-0.5 text-sm", tone === "warning" && "text-[#d4d7da]")}>{description}</div>
        </div>
      </div>
      {action}
    </div>
  );
}
