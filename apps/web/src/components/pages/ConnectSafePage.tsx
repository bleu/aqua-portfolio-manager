import { Button } from "@/components/Button";
import { CurrentVsTargetCard } from "@/components/CurrentVsTargetCard";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";

export type ConnectSafePageProps = {
  onConnectSafe?: () => void;
  isConnecting?: boolean;
  connectError?: string;
};

/** BLEUDEV-397 — "01 · Connect Safe": the entry landing page. FirstAccessIntroductionPage ("02")
 *  follows once connected -- see its own doc comment.
 *  BLEUDEV-429 — rebranded to Trim. The wallet-choice copy ("WalletConnect or Safe App") this page
 *  used to show inline moves into the Connect Wallet modal (BLEUDEV-430); both CTAs here still
 *  call the same `onConnectSafe` handler until that modal replaces it. */
export function ConnectSafePage({ onConnectSafe, isConnecting, connectError }: ConnectSafePageProps) {
  return (
    <div className="min-h-screen">
      <Header onLaunchApp={onConnectSafe} />

      <main className="relative mx-auto grid max-w-6xl gap-12 overflow-hidden px-8 py-20 lg:grid-cols-2 lg:items-center">
        <img
          src="/octopus-mascot.png"
          alt=""
          className="pointer-events-none absolute -right-10 top-1/2 hidden w-72 -translate-y-1/2 opacity-10 lg:block"
        />

        <div>
          <h1 className="mt-6 font-display text-[52px] font-medium leading-[1.25] text-ink-primary">
            Manage your DeFi exposure with a few extra hands.
          </h1>

          <p className="mt-6 max-w-md text-[21px] leading-[1.45] text-ink-secondary">
            Choose your exposure targets, then let Trim put Aqua Protocol trades to work rebalancing your portfolio
            while earning LP fees.
          </p>

          <Button variant="accent" className="mt-8" disabled={isConnecting} onClick={onConnectSafe}>
            {isConnecting ? "Connecting…" : "Launch app"}
          </Button>

          {connectError && <p className="mt-4 max-w-md text-sm text-red-400">{connectError}</p>}
        </div>

        <CurrentVsTargetCard
          baskets={[
            {
              label: "Crypto majors",
              currentPct: 42,
              targetPct: 33.3,
              caption: "Routing reduces the overweight basket toward 33.3%",
              // Trim brand guide's Salmon -- confirmed in Figma's allocation-ribbon node names,
              // each basket gets its own brand color rather than sharing the accent.
              color: "#d99d8e",
            },
            {
              label: "Stablecoins",
              currentPct: 58,
              targetPct: 66.7,
              caption: "Routing increases the underweight basket toward 66.7%",
              color: "#94cad1",
            },
          ]}
        />
      </main>

      <Footer />
    </div>
  );
}
