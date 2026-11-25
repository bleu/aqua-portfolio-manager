import { Button } from "@/components/Button";
import { AQUA_URL, BLEU_URL, DOCS_URL } from "./links";

/** Horizontal page gutter shared by every landing section (Figma: 80px at the 1636px frame). */
export const GUTTER = "px-[clamp(24px,4.9vw,120px)]";

export type LaunchProps = { onLaunch?: () => void; isConnecting?: boolean };

export function LaunchButton({ onLaunch, isConnecting, className }: LaunchProps & { className?: string }) {
  return (
    <Button variant="accent" className={className} disabled={isConnecting} onClick={onLaunch}>
      {isConnecting ? "Connecting…" : "Launch app"}
    </Button>
  );
}

export function LandingHeader({ onLaunch, isConnecting }: LaunchProps) {
  return (
    <header className={`flex items-center justify-between pt-10 ${GUTTER}`}>
      <div className="flex items-center gap-1">
        <img src="/landing/header-octopus.svg" alt="" className="size-9 -scale-x-100" />
        <span className="font-display text-[32px] font-normal text-accent">Trim</span>
      </div>
      <LaunchButton onLaunch={onLaunch} isConnecting={isConnecting} />
    </header>
  );
}

export function LandingFooter() {
  return (
    <footer
      className={`flex flex-col items-center justify-between gap-4 pb-[62px] pt-8 text-sm leading-5 tracking-[0.25px] text-ink-primary sm:flex-row ${GUTTER}`}
    >
      <span className="flex items-center gap-1">
        © 2026 Built by
        <img src="/bleu-logo.svg" alt="BLEU" className="h-[11.164px]" />
      </span>
      <nav aria-label="Footer" className="flex items-center gap-10">
        <a href={DOCS_URL} target="_blank" rel="noopener noreferrer" className="hover:text-accent">
          Documentation
        </a>
        <a href={BLEU_URL} target="_blank" rel="noopener noreferrer" className="hover:text-accent">
          About Bleu
        </a>
        <a href={AQUA_URL} target="_blank" rel="noopener noreferrer" className="hover:text-accent">
          About Aqua
        </a>
      </nav>
    </footer>
  );
}
