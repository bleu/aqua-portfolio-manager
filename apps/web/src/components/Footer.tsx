/** Confirmed directly on the real landing page (node 546:25558, "Navigation/Footer"): both the
 *  copyright line and the nav links use var(--text-primary), not a muted gray, and the links sit
 *  gap-[40px] apart. "BLEU" renders as its own logo graphic, not plain bold text.
 *
 *  The mountain silhouette is cropped straight from the full-page background's own bottom strip
 *  (apps/web/public/landing-page-bg.png) with a moderate contrast boost -- the source asset's own
 *  wave shapes are real, but at full-page scale they read as flat, indistinguishable from the
 *  surrounding near-black. Isolating and boosting just this strip keeps the rest of the page's
 *  subtlety intact while making the footer's own silhouette actually visible, matching the
 *  reference screenshot. */
export function Footer() {
  return (
    // No max-width (matches Header/main): fills wide viewports instead of staying capped at the
    // design's own content width.
    <footer className="relative flex h-[94px] flex-col items-center justify-between gap-4 overflow-hidden px-[clamp(24px,4vw,120px)] pb-[62px] pt-8 text-sm text-ink-primary sm:flex-row">
      <img
        src="/footer-mountains.png"
        alt=""
        className="pointer-events-none absolute inset-0 -z-10 size-full object-cover"
      />
      <span className="flex items-center gap-1">
        © 2026 Built by
        <img src="/bleu-logo.svg" alt="BLEU" className="h-[11px]" />
      </span>
      <nav className="flex items-center gap-10">
        <a href="#" className="hover:text-accent">
          Documentation
        </a>
        <a href="#" className="hover:text-accent">
          About Bleu
        </a>
        <a href="#" className="hover:text-accent">
          About Aqua
        </a>
      </nav>
    </footer>
  );
}
