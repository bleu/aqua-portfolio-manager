"use client";

import { useState } from "react";
import { cn } from "@/lib/cn";

export type TokenIconProps = {
  symbol: string;
  iconUrl?: string;
  size?: number;
  className?: string;
};

/** Real token logo when one's available, falling back to a letter avatar on a missing URL or a
 *  failed/broken image load -- shared by TokenChip and TokenListRow so both pick up logos at once. */
export function TokenIcon({ symbol, iconUrl, size = 20, className }: TokenIconProps) {
  const [failed, setFailed] = useState(false);
  const style = { width: size, height: size };

  if (iconUrl && !failed) {
    return (
      <img
        src={iconUrl}
        alt={symbol}
        style={style}
        onError={() => setFailed(true)}
        className={cn("shrink-0 rounded-full object-cover", className)}
      />
    );
  }

  return (
    <span
      style={style}
      className={cn(
        "flex shrink-0 items-center justify-center rounded-full bg-accent/30 text-[10px] font-semibold text-accent",
        className,
      )}
    >
      {symbol.slice(0, 1)}
    </span>
  );
}
