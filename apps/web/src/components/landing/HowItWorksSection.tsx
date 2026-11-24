"use client";

import { useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { GUTTER } from "./LandingChrome";
import { HOW_IT_WORKS_ID } from "./HeroSection";
import { BasketsPreview, LimitsPreview, RebalancePreview, TargetsPreview } from "./StepPreviews";
import { cn } from "@/lib/cn";

type Step = { title: string; description: string; gradient: string; preview: ReactNode };

/** Copy and card colours from Figma frames "1" to "4" under the landing page (Hi-fi, User flows). */
const STEPS: Step[] = [
  {
    title: "Build your baskets",
    description: "Group supported tokens into baskets that reflect how you want to manage your exposure.",
    gradient: "from-[#f0f9fa] to-accent",
    preview: <BasketsPreview />,
  },
  {
    title: "Set your targets",
    description: "Decide how much exposure you want to maintain in each basket.",
    gradient: "from-[#f7f5f9] to-[#aa9eb7]",
    preview: <TargetsPreview />,
  },
  {
    title: "Configure your limits and fees",
    description: "Set your price tolerance and LP fee tier to define the conditions under which trades can execute.",
    gradient: "from-[#fcf3f0] to-[#d99d8e]",
    preview: <LimitsPreview />,
  },
  {
    title: "Let trades rebalance",
    description:
      "Keep your assets in your wallet and your capital available for other Aqua strategies. Trades routed through Aqua help move your allocations toward their targets.",
    gradient: "from-[#f0f9fa] to-[#d1bc94]",
    preview: <RebalancePreview />,
  },
];

const pad = (n: number) => String(n + 1).padStart(2, "0");

/** Figma's 818 x 443 card, scaled down below the desktop breakpoint. */
function PreviewCard({ step, labelledBy, id }: { step: Step; labelledBy: string; id: string }) {
  return (
    <div
      id={id}
      role="tabpanel"
      aria-labelledby={labelledBy}
      className="relative mx-auto h-[186px] w-[343px] shrink-0 sm:h-[310px] sm:w-[573px] lg:mx-0 lg:h-[443.41px] lg:w-[818px]"
    >
      {/* Remounted on every step so the new card fades in. The previews are examples, not live data. */}
      <div
        aria-hidden="true"
        className={cn(
          "landing-fade absolute left-0 top-0 h-[443.41px] w-[818px] origin-top-left scale-[0.42] overflow-clip rounded-[36px] bg-gradient-to-b sm:scale-[0.7] lg:scale-100",
          step.gradient,
        )}
        key={step.title}
      >
        {step.preview}
      </div>
    </div>
  );
}

export function HowItWorksSection() {
  const [active, setActive] = useState(0);
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);

  const select = (i: number) => {
    setActive(i);
    tabs.current[i]?.focus();
  };

  const onKeyDown = (e: KeyboardEvent) => {
    if (e.key === "ArrowDown" || e.key === "ArrowRight") {
      e.preventDefault();
      select((active + 1) % STEPS.length);
    } else if (e.key === "ArrowUp" || e.key === "ArrowLeft") {
      e.preventDefault();
      select((active + STEPS.length - 1) % STEPS.length);
    }
  };

  return (
    <section id={HOW_IT_WORKS_ID} className={`scroll-mt-10 ${GUTTER}`}>
      <div className="flex flex-col items-start justify-between gap-10 lg:flex-row">
        <div role="tablist" aria-orientation="vertical" aria-label="How it works" className="flex w-full max-w-[410px] flex-col gap-6">
          {STEPS.map((step, i) => {
            const isActive = i === active;
            return (
              <button
                key={step.title}
                ref={(el) => {
                  tabs.current[i] = el;
                }}
                id={`how-tab-${i}`}
                role="tab"
                type="button"
                aria-selected={isActive}
                aria-controls="how-panel"
                tabIndex={isActive ? 0 : -1}
                onClick={() => setActive(i)}
                onKeyDown={onKeyDown}
                className={cn(
                  "flex w-full flex-col items-start text-left leading-[1.4] transition-opacity focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-accent",
                  isActive ? "gap-3" : "gap-2 font-[510] opacity-50 hover:opacity-80",
                )}
              >
                <span className={cn("text-xs font-[510]", isActive ? "text-accent" : "text-accent-muted")}>
                  {pad(i)} /{isActive && " HOW IT WORKS"}
                </span>
                {isActive ? (
                  <>
                    <span className="flex items-center gap-2">
                      <img src="/landing/step-icon.svg" alt="" className="h-5 w-[27px] shrink-0" />
                      <span className="text-[26px] font-[510] text-ink-primary">{step.title}</span>
                    </span>
                    <span className="max-w-[380px] text-lg font-normal leading-normal text-ink-secondary">
                      {step.description}
                    </span>
                  </>
                ) : (
                  <span className="text-[26px] text-ink-secondary">{step.title}</span>
                )}
              </button>
            );
          })}
        </div>
        <PreviewCard step={STEPS[active]} labelledBy={`how-tab-${active}`} id="how-panel" />
      </div>
    </section>
  );
}
