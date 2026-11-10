import { Button } from "@/components/Button";

export type HeaderProps = {
  productName?: string;
  onLaunchApp?: () => void;
};

export function Header({ productName = "trim", onLaunchApp }: HeaderProps) {
  return (
    // Confirmed on the real header (node 680:20947): h-[80px]/pt-[32px], no border -- the
    // previous version added a bottom border and shorter py-5 that aren't in the source.
    // No max-width here (per the user's call): the page fills wide viewports rather than
    // staying capped at the design's own 1512px content width, so horizontal padding and the
    // wordmark's font size scale moderately with viewport via clamp() instead of a fixed value --
    // Figma's canvas has no opinion on behavior past its own edge, so these curves are my own
    // reasonable choice, anchored to equal the confirmed values at the design's 1636px width.
    <header className="flex h-[80px] items-center justify-between px-[clamp(24px,4vw,120px)] pt-8">
      <div className="flex items-center gap-2">
        <img src="/octopus.svg" alt="" className="h-[30px] w-9" />
        {/* Confirmed directly on the real landing page's header (node 680:20947): Unbounded
            Regular (not Medium), 32px, var(--highlight-mint-primary, #94cad1). */}
        <span className="font-display text-[clamp(32px,9px_+_1.41vw,45px)] font-normal text-accent">
          {productName}
        </span>
      </div>
      <Button variant="accent" onClick={onLaunchApp}>
        Launch app
      </Button>
    </header>
  );
}
