import { Badge } from "./Badge";

export type NetworkBadgeProps = {
  network: string;
};

/** The chain indicator pill shown in the app header. Matches Figma's "wallet-indicator" (node
 *  546:25617, confirmed on the Baskets-Filled flow screen): a real chain icon, not a colored
 *  status dot -- bg #1e2123 (surface-raised), border #292c30, 30px radius, 12px padding, 8px
 *  gap, Inter Regular 16px text in #f8fffe. Base-only for now, matching every other part of this
 *  app (indexer, contracts) -- the `network` prop is display text, not a per-chain icon switch. */
export function NetworkBadge({ network }: NetworkBadgeProps) {
  return (
    <Badge
      icon={<img src="/base-network-icon.svg" alt="" className="h-5 w-5 shrink-0" />}
      className="gap-2 rounded-[30px] border-[#292c30] bg-surface-raised p-3 text-base font-normal text-[#f8fffe]"
    >
      {network}
    </Badge>
  );
}
