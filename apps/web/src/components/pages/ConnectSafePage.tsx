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
    <div className="relative min-h-screen overflow-hidden">
      {/* The real landing page frame has one full-bleed background image behind everything
          (confirmed node 680:20946's own background) -- a top-left glow plus the wavy horizon
          line visible near the footer. An earlier pass omitted it entirely. */}
      <img
        src="/landing-page-bg.png"
        alt=""
        className="pointer-events-none absolute inset-0 -z-10 size-full object-cover"
      />

      <Header onLaunchApp={onConnectSafe} />

      {/* No max-width (per the user's call): the page fills wide viewports instead of staying
          capped at the design's own 1512px/1636px content width. Horizontal padding and the
          headline/body font sizes scale moderately with viewport via clamp() rather than a fixed
          value -- Figma's canvas has no opinion on behavior past its own edge, so these curves
          are my own reasonable choice, anchored to equal the confirmed values at the design's
          1636px width.
          grid-cols-[881fr_522fr] matches the real hero/card width ratio (881px:522px) -- an
          equal grid-cols-2 split had rendered the card noticeably wider, and the hero column
          noticeably narrower, than the real design, which is why the headline wrapped across
          more lines than it should have. */}
      <main className="relative grid gap-16 px-[clamp(24px,4vw,120px)] py-20 lg:grid-cols-[881fr_522fr] lg:items-center">
        <div>
          {/* text-[#f5f7fa] is this exact node's own hardcoded literal (680:20951), a hex step
              off the ink-primary token's variable-bound value -- kept inline rather than through
              the shared token since the source itself diverges here. */}
          <h1 className="mt-6 font-display text-[clamp(52px,2.4px_+_3.03vw,80px)] font-medium leading-[1.25] text-[#f5f7fa]">
            Manage your DeFi exposure with a few extra hands.
          </h1>

          <p className="mt-6 max-w-2xl text-[clamp(18px,7.4px_+_0.65vw,24px)] leading-[1.25] text-ink-secondary">
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
              tall the hero text column renders. w-[158px] matches the real node's own 171x156
              size scaled to this page's content width (1512/1636) -- a smaller w-28 was
              downscaling its fine linework enough to blur into an indistinct smudge. */}
          <img
            src="/octopus-mascot-landing.png"
            alt=""
            className="pointer-events-none absolute -top-16 right-4 z-0 hidden w-[158px] lg:block"
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
