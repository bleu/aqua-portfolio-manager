/** Confirmed directly on the real landing page (node 546:25558, "Navigation/Footer"): both the
 *  copyright line and the nav links use var(--text-primary), not a muted gray, and the links sit
 *  gap-[40px] apart. "BLEU" renders as its own logo graphic, not plain bold text. */
export function Footer() {
  return (
    <footer className="mx-auto flex h-[94px] max-w-6xl flex-col items-center justify-between gap-4 px-8 pb-[62px] pt-8 text-sm text-ink-primary sm:flex-row">
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
