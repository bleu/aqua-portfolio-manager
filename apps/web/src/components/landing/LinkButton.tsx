import type { AnchorHTMLAttributes } from "react";
import { cn } from "@/lib/cn";

export type LinkButtonProps = AnchorHTMLAttributes<HTMLAnchorElement> & {
  /** "ghost" is bold text only (links on mint cards); "outline" adds Figma's subtle border. */
  variant?: "ghost" | "outline";
  /** Opens in a new tab and adds the arrow icon. */
  external?: boolean;
  icon?: "arrow-up-right" | "arrow-down";
};

/** Figma's "Actions/Button/Primary" used as a text link on a light surface. */
export function LinkButton({ variant = "ghost", external, icon, className, children, ...rest }: LinkButtonProps) {
  const iconName = icon ?? (external ? "arrow-up-right" : undefined);
  return (
    <a
      className={cn(
        "inline-flex h-12 items-center justify-center gap-2 rounded-full px-[18px] text-[15px] text-[#0a0c16] transition-opacity hover:opacity-70 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-surface-card",
        variant === "ghost" && "font-bold",
        variant === "outline" && "border border-[#292c30] font-[590]",
        className,
      )}
      {...(external ? { target: "_blank", rel: "noopener noreferrer" } : {})}
      {...rest}
    >
      {children}
      {iconName && <img src={`/landing/${iconName}.svg`} alt="" className="size-6" />}
    </a>
  );
}
