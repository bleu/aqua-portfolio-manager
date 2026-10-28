import { Badge } from "@/components/Badge";
import { Button } from "@/components/Button";
import { CurrentVsTargetCard } from "@/components/CurrentVsTargetCard";
import { Header } from "@/components/Header";

export type ConnectSafePageProps = {
  onConnectSafe?: () => void;
  isConnecting?: boolean;
  connectError?: string;
  /** Omitted entirely when no Base Account connector is registered (e.g. missing config) --
   *  callers should only pass this when connecting one is actually possible. */
  onConnectBaseWallet?: () => void;
  isConnectingBaseWallet?: boolean;
  connectBaseWalletError?: string;
};

/** BLEUDEV-397 — "01 · Connect Safe": the entry landing page. FirstAccessIntroductionPage ("02")
 *  follows once connected -- see its own doc comment.
 *
 *  Two real account types work here, not just Safe: a Safe (any strategy, protected by its own
 *  BasketScopeGuard) or a Base smart wallet used for nothing but Portfolio Manager. The second
 *  path exists only because the first doesn't fit everyone -- Base Wallet has no equivalent to a
 *  Safe's Guard (confirmed directly against CoinbaseSmartWallet.sol: execute()/executeBatch() call
 *  out with no hook of any kind), so there's nothing to protect a Base Wallet shared with another
 *  strategy the way the Guard protects a Safe. The dedicated-use warning below isn't boilerplate --
 *  it's the one condition that makes connecting one safe at all. */
export function ConnectSafePage({
  onConnectSafe,
  isConnecting,
  connectError,
  onConnectBaseWallet,
  isConnectingBaseWallet,
  connectBaseWalletError,
}: ConnectSafePageProps) {
  return (
    <div className="min-h-screen">
      <Header />

      <main className="mx-auto grid max-w-6xl gap-12 px-8 py-20 lg:grid-cols-2 lg:items-center">
        <div>
          <Badge variant="outline">Smart account required</Badge>

          <h1 className="mt-6 text-5xl leading-[1.05] font-bold text-white">Keep your portfolio on target</h1>

          <p className="mt-6 max-w-md text-base leading-relaxed text-gray-400">
            Connect a Safe or a Base Wallet, choose the tokens to manage, and set a target for each group. Trades
            routed through Aqua help maintain those targets while your portfolio earns LP fees.
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Button disabled={isConnecting} onClick={onConnectSafe}>
              {isConnecting ? "Connecting…" : "Connect Safe"}
            </Button>
            {onConnectBaseWallet && (
              <Button variant="secondary" disabled={isConnectingBaseWallet} onClick={onConnectBaseWallet}>
                {isConnectingBaseWallet ? "Connecting…" : "Connect Base Wallet"}
              </Button>
            )}
          </div>

          {connectError && <p className="mt-4 max-w-md text-sm text-red-400">{connectError}</p>}
          {connectBaseWalletError && <p className="mt-4 max-w-md text-sm text-red-400">{connectBaseWalletError}</p>}

          <p className="mt-4 text-sm text-gray-500">
            You can connect a Safe with WalletConnect or open Portfolio Manager as a Safe App.
          </p>
          {onConnectBaseWallet && (
            <p className="mt-2 max-w-md text-sm text-amber-500">
              Use a Base Wallet only if it won&apos;t run any other strategy. A Safe protects a shared wallet from
              other activity; a Base Wallet has no equivalent protection, so it must be dedicated to Portfolio
              Manager alone.
            </p>
          )}
        </div>

        <CurrentVsTargetCard
          baskets={[
            {
              label: "Crypto majors",
              currentPct: 42,
              targetPct: 33.3,
              caption: "Routing reduces the overweight basket toward 33.3%",
            },
            {
              label: "Stablecoins",
              currentPct: 58,
              targetPct: 66.7,
              caption: "Routing increases the underweight basket toward 66.7%",
            },
          ]}
        />
      </main>
    </div>
  );
}
