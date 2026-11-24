"use client";

import { useId, useState } from "react";
import { GUTTER } from "./LandingChrome";
import { FAQ } from "./faq";
import { cn } from "@/lib/cn";

export function FaqSection() {
  const [open, setOpen] = useState<number | null>(0);
  const baseId = useId();

  return (
    <section className={`flex flex-col items-start justify-between gap-10 lg:flex-row lg:items-center ${GUTTER}`}>
      <div className="flex flex-col gap-6">
        <img src="/landing/faq-bubble.svg" alt="" className="h-[69px] w-24" />
        <h2 className="font-display text-[clamp(36px,2vw+20px,52px)] font-normal leading-[1.24] text-ink-primary">
          Fair
          <br />
          questions.
        </h2>
      </div>

      <div className="w-full border-t border-[#292c30] lg:w-[662px]">
        {FAQ.map((item, i) => {
          const isOpen = open === i;
          const buttonId = `${baseId}-q${i}`;
          const panelId = `${baseId}-a${i}`;
          return (
            <div key={item.question} className="border-b border-[#292c30] py-8">
              <h3>
                <button
                  id={buttonId}
                  type="button"
                  aria-expanded={isOpen}
                  aria-controls={panelId}
                  onClick={() => setOpen(isOpen ? null : i)}
                  className="flex w-full items-start justify-between gap-4 text-left focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-accent"
                >
                  <span className="flex items-start gap-4 leading-[1.4] sm:gap-[42px]">
                    <span
                      className={cn(
                        "font-geist-mono w-[25px] shrink-0 text-lg font-medium",
                        isOpen ? "text-accent" : "text-accent-muted",
                      )}
                    >
                      {String(i + 1).padStart(2, "0")}
                    </span>
                    <span
                      className={cn(
                        "max-w-[520px] text-xl font-[510] sm:text-[26px]",
                        isOpen ? "text-ink-primary" : "text-ink-secondary",
                      )}
                    >
                      {item.question}
                    </span>
                  </span>
                  <img
                    src={isOpen ? "/landing/faq-close.svg" : "/landing/faq-chevron.svg"}
                    alt=""
                    className="size-8 shrink-0"
                  />
                </button>
              </h3>
              {isOpen && (
                <div
                  id={panelId}
                  role="region"
                  aria-labelledby={buttonId}
                  className="mt-6 flex flex-col gap-4 pl-10 text-base sm:pl-[67px] sm:text-lg leading-normal text-ink-secondary"
                >
                  {item.answer.map((paragraph) => (
                    <p key={paragraph}>{paragraph}</p>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
}
