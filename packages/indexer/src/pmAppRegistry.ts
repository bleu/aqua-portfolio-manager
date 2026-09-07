/**
 * Which `app` address is our own Portfolio Manager router, per chain. Deployment-specific --
 * not derivable from a `Shipped` event alone, same pattern as `Deploy.s.sol`'s
 * `AQUA_ADDRESS`/`AQUA_MAINNET` constants in packages/contracts.
 */
export const PM_ROUTER_ADDRESSES: Record<number, string> = {
  // 8453: "0x...", // Base -- fill in once PortfolioManagerRouter is deployed there.
};

export function isPmApp(app: string, chainId: number): boolean {
  const pmRouter = PM_ROUTER_ADDRESSES[chainId];
  return pmRouter !== undefined && app.toLowerCase() === pmRouter.toLowerCase();
}
