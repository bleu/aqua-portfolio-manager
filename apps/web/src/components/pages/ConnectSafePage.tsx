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

      {/* max-w-[1512px]/px-[62px] match the real landing page's own canvas width (1636px, minus
          62px padding each side) -- the previous max-w-6xl (1152px) squeezed every fixed-px
          type size (confirmed from Figma) into a narrower box than it was sized for, reading
          oversized relative to the rest of the page. */}
      <main className="relative mx-auto grid max-w-[1512px] gap-12 px-[62px] py-20 lg:grid-cols-2 lg:items-center">
        <div>
          {/* text-[#f5f7fa] is this exact node's own hardcoded literal (680:20951), a hex step
              off the ink-primary token's variable-bound value -- kept inline rather than through
              the shared token since the source itself diverges here. */}
          <h1 className="mt-6 font-display text-[52px] font-medium leading-[1.25] text-[#f5f7fa]">
            Manage your DeFi exposure with a few extra hands.
          </h1>

          <p className="mt-6 max-w-md text-[18px] leading-[1.25] text-ink-secondary">
            Choose your exposure targets, then let Trim put Aqua Protocol trades to work rebalancing your portfolio
            while earning LP fees.
          </p>

          <Button variant="accent" className="mt-8" disabled={isConnecting} onClick={onConnectSafe}>
            {isConnecting ? "Connecting…" : "Launch app"}
          </Button>

          {connectError && <p className="mt-4 max-w-md text-sm text-red-400">{connectError}</p>}
        </div>

        <div className="relative">
          {/* Confirmed on the real landing page (node 680:20994, "Polvo carvão com contornos
              elegantes 1") -- a distinct, darker-outline asset from the header's blue mark, at
              full opacity, peeking above the card's own top-right corner. Anchored to the card
              itself (not the whole grid row) so it stays correctly placed regardless of how
              tall the hero text column renders. */}
          <img
            src="/octopus-mascot-landing.png"
            alt=""
            className="pointer-events-none absolute -top-10 right-4 z-0 hidden w-28 lg:block"
          />
          <CurrentVsTargetCard
            className="relative z-10"
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
        </div>
      </main>

      <Footer />
    </div>
  );
}
