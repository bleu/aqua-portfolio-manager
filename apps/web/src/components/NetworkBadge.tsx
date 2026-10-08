import { Badge } from "./Badge";

export type NetworkBadgeProps = {
  network: string;
  /** Defaults to a live/positive green, matching the connected-network state in the design. */
  statusColor?: string;
};

/** The chain indicator pill (colored dot + chain name) shown in the app header. */
export function NetworkBadge({ network, statusColor = "#22c55e" }: NetworkBadgeProps) {
  return <Badge dotColor={statusColor}>{network}</Badge>;
}
