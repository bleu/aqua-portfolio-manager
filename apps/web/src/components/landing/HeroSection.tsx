import { Button } from "@/components/Button";
import { Decor } from "./Decor";
import { GUTTER, LaunchButton, type LaunchProps } from "./LandingChrome";
import { LinkButton } from "./LinkButton";
import { HeroPortfolioCard, HeroTargetCard } from "./MockCards";

export const HOW_IT_WORKS_ID = "how-it-works";

function scrollToHowItWorks(e: React.MouseEvent) {
  e.preventDefault();
  document.getElementById(HOW_IT_WORKS_ID)?.scrollIntoView({ behavior: "smooth" });
}

/** The two floating product cards, laid out on Figma's 738 x 779 stage and scaled down on narrower screens. */
function HeroStage() {
  return (
    <div
      aria-hidden="true"
      className="relative mx-auto h-[390px] w-[369px] shrink-0 lg:absolute lg:right-0 lg:top-0 lg:mx-0 lg:h-[545px] lg:w-[517px] xl:h-[661px] xl:w-[627px] 2xl:h-[779px] 2xl:w-[738px]"
    >
      <div className="absolute left-0 top-0 h-[779px] w-[738px] origin-top-left scale-50 lg:scale-[0.7] xl:scale-[0.85] 2xl:scale-100">
        <HeroPortfolioCard className="absolute left-[140.1px] top-[98px] rotate-[13.05deg]" />
        <HeroTargetCard className="absolute left-2 top-[429.4px] -rotate-[3.29deg]" />
      </div>
    </div>
  );
}

export function HeroSection({ onLaunch, isConnecting }: LaunchProps) {
  return (
    <section className={GUTTER}>
      <div className="relative flex flex-col items-stretch gap-10 overflow-clip rounded-[36px] bg-gradient-to-b from-[#f0f9fa] to-accent p-8 sm:p-14 lg:min-h-[545px] lg:flex-row xl:min-h-[661px] 2xl:min-h-[779px] lg:items-center lg:p-20 lg:pr-[420px] xl:pr-[530px] 2xl:pr-[640px]">
        <Decor
          src="/landing/hero-octopus-a.svg"
          wrapper={{ left: 226, top: -482, width: 1176.207, height: 1157.725 }}
          size={{ width: 936.304, height: 962.719 }}
          transform="scaleY(-1) rotate(74.65deg)"
        />
        <Decor
          src="/landing/hero-octopus-b.svg"
          wrapper={{ left: 549, top: -29, width: 1326.236, height: 1328.501 }}
          size={{ width: 927.275, height: 953.435 }}
          transform="scaleY(-1) rotate(-138.51deg)"
        />

        <div className="relative z-10 flex max-w-[758px] flex-col gap-[52px]">
          <div className="flex flex-col gap-8">
            <h1 className="font-display text-[clamp(28px,3.2vw,52px)] font-semibold leading-[1.25] text-surface-card">
              Give your DeFi portfolio{" "}
              <br className="hidden xl:inline" />
              a few{" "}
              <span className="relative inline-block whitespace-nowrap">
                extra hands
                <img
                  src="/landing/underline-hero.svg"
                  alt=""
                  className="pointer-events-none absolute -bottom-2 left-0 h-5 w-full max-w-none rotate-[2.11deg]"
                />
              </span>
              <span className="relative ml-9 inline-block h-6 w-10 align-top" aria-hidden="true">
                <img src="/landing/sparkle-large.svg" alt="" className="absolute left-3 top-0 h-6 w-7 max-w-none" />
                <img
                  src="/landing/sparkle-small.svg"
                  alt=""
                  className="absolute left-0 top-[21px] h-3.5 w-[17px] max-w-none"
                />
              </span>
            </h1>
            <p className="max-w-[620px] text-lg sm:text-[21px] xl:max-w-[540px] 2xl:max-w-[620px] leading-[1.45] text-surface-card">
              Set your target allocations and let trades routed through Aqua help keep your portfolio aligned, while you
              earn LP fees.
            </p>
          </div>
          <div className="flex flex-wrap items-start gap-3">
            <Button
              variant="secondary"
              className="bg-surface-raised text-ink-primary hover:bg-[#2a2e34]"
              disabled={isConnecting}
              onClick={onLaunch}
            >
              {isConnecting ? "Connecting…" : "Launch app"}
            </Button>
            <LinkButton variant="outline" icon="arrow-down" href={`#${HOW_IT_WORKS_ID}`} onClick={scrollToHowItWorks}>
              How it works
            </LinkButton>
          </div>
        </div>

        <HeroStage />
      </div>
    </section>
  );
}
