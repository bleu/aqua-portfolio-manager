export function formatPercentage(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

export function formatUsd(value: number): string {
  return `$${value.toLocaleString("en-US", { maximumFractionDigits: 0 })}`;
}

export function truncateAddress(address: string): string {
  if (address.length <= 10) return address;
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}
