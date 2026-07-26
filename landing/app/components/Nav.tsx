export function Nav() {
  return (
    <header className="sticky top-0 z-50 border-b border-border/70 bg-bg/80 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-3">
        <a href="#top" className="flex items-center gap-2 font-mono text-sm tracking-tight">
          <span className="relative inline-flex h-4 w-7 items-center justify-center rounded-full bg-text">
            <span className="h-1.5 w-1.5 rounded-full bg-accent" />
          </span>
          synqit
        </a>
        <nav className="hidden items-center gap-8 text-sm text-muted sm:flex">
          <a href="#how-it-works" className="hover:text-text">
            How it works
          </a>
          <a href="#features" className="hover:text-text">
            Features
          </a>
          <a href="#faq" className="hover:text-text">
            FAQ
          </a>
          <a
            href="https://github.com/ben564885/jachacks26"
            className="hover:text-text"
          >
            GitHub
          </a>
        </nav>
        <a
          href="#quickstart"
          className="rounded-full bg-accent px-4 py-1.5 text-sm font-medium text-accent-contrast transition hover:opacity-90"
        >
          Get started
        </a>
      </div>
    </header>
  );
}
