import { ClosingSection } from "@/components/landing/ClosingSection";
import { FaqSection } from "@/components/landing/FaqSection";
import { HeroSection } from "@/components/landing/HeroSection";
import { HowItWorksSection } from "@/components/landing/HowItWorksSection";
import { LandingFooter, LandingHeader } from "@/components/landing/LandingChrome";
import { SharedLiquiditySection } from "@/components/landing/SharedLiquiditySection";
import { ValueSection } from "@/components/landing/ValueSection";

export type ConnectSafePageProps = {
  onConnectSafe?: () => void;
  isConnecting?: boolean;
  connectError?: string;
};

/** The public landing page and entry to the app (trim.pm). Every "Launch app" button calls the same
 *  `onConnectSafe` handler, so the connect flow is unchanged. FirstAccessIntroductionPage ("02")
 *  follows once a Safe is connected.
 *  Design: Figma "Portfolio Manager - Lo-fi", frame "Landing page" (node 1196:13320).
 *  Product figures in the preview cards are examples, not live data. */
export function ConnectSafePage({ onConnectSafe, isConnecting, connectError }: ConnectSafePageProps) {
  const launch = { onLaunch: onConnectSafe, isConnecting };
  return (
    <div className="relative flex min-h-screen flex-col gap-[100px] overflow-x-clip">
      <img
        src="/landing-page-bg.png"
        alt=""
        className="pointer-events-none absolute inset-0 -z-10 size-full max-w-none object-cover"
      />

      <div className="flex flex-col gap-8">
        <LandingHeader {...launch} />
        <HeroSection {...launch} />
      </div>

      <main className="flex flex-col gap-[100px] sm:gap-[140px] lg:gap-[200px] lg:pt-[100px]">
        <SharedLiquiditySection />
        <ValueSection />
        <HowItWorksSection />
        <FaqSection />
        <ClosingSection {...launch} />
      </main>

      <LandingFooter />

      {/* The connect attempt can start from any "Launch app" button, so the error shows in view
          wherever the visitor clicked. */}
      {connectError && (
        <p
          role="alert"
          className="fixed bottom-6 left-1/2 z-50 w-[min(92vw,28rem)] -translate-x-1/2 rounded-xl border border-red-400/40 bg-surface-card px-4 py-3 text-sm text-red-400 shadow-lg"
        >
          {connectError}
        </p>
      )}
    </div>
  );
}
