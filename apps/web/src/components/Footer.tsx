export function Footer() {
  return (
    <footer className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-8 py-6 text-sm text-ink-muted sm:flex-row">
      <span>© 2026 Built by BLEU</span>
      <nav className="flex items-center gap-6">
        <a href="#" className="hover:text-ink-primary">
          Documentation
        </a>
        <a href="#" className="hover:text-ink-primary">
          About Bleu
        </a>
        <a href="#" className="hover:text-ink-primary">
          About Aqua
        </a>
      </nav>
    </footer>
  );
}
