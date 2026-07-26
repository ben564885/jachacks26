import type { ReactNode } from "react";

export function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <span className="inline-block rounded-full border border-border bg-surface-2 px-3 py-1 font-mono text-xs tracking-wide text-muted uppercase">
      {children}
    </span>
  );
}

export function FeatureCard({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <div className="rounded-xl border border-border bg-surface p-5 transition hover:border-accent/40">
      <h3 className="font-medium text-text">{title}</h3>
      <p className="mt-1.5 text-sm leading-relaxed text-muted">{children}</p>
    </div>
  );
}

export function DetailSection({
  eyebrow,
  heading,
  children,
  visual,
  reverse = false,
  dark = false,
}: {
  eyebrow: string;
  heading: string;
  children: ReactNode;
  visual: ReactNode;
  reverse?: boolean;
  dark?: boolean;
}) {
  return (
    <section
      className={
        dark
          ? "bg-[#0b0c0f] py-20 text-[#f2f1ed]"
          : "py-20"
      }
    >
      <div className="mx-auto max-w-6xl px-6">
        <div
          className={`grid items-center gap-10 lg:grid-cols-2 lg:gap-16 ${
            reverse ? "lg:[&>*:first-child]:order-2" : ""
          }`}
        >
          <div>
            <span
              className={`inline-block rounded-full border px-3 py-1 font-mono text-xs tracking-wide uppercase ${
                dark
                  ? "border-white/15 bg-white/5 text-[#9a9ca3]"
                  : "border-border bg-surface-2 text-muted"
              }`}
            >
              {eyebrow}
            </span>
            <h2 className="mt-4 font-display text-3xl italic sm:text-4xl">{heading}</h2>
            <div
              className={`mt-4 space-y-3 text-[15px] leading-relaxed ${
                dark ? "text-[#c3c4c8]" : "text-muted"
              }`}
            >
              {children}
            </div>
          </div>
          <div>{visual}</div>
        </div>
      </div>
    </section>
  );
}

export function TrunkDivider({ notch = false }: { notch?: boolean }) {
  return (
    <div className="mx-auto flex max-w-6xl items-center gap-0 px-6" aria-hidden="true">
      <span className="h-px flex-1 bg-border" />
      {notch ? (
        <span className="h-3 w-6 rounded-b-full border border-t-0 border-accent bg-accent/20" />
      ) : (
        <span className="h-1.5 w-1.5 rounded-full bg-border" />
      )}
      <span className="h-px flex-1 bg-border" />
    </div>
  );
}

export function FaqItem({ q, a }: { q: string; a: string }) {
  return (
    <details className="group border-b border-border py-4 [&_summary::-webkit-details-marker]:hidden">
      <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-[15px] text-text">
        {q}
        <span className="shrink-0 text-muted transition group-open:rotate-45">+</span>
      </summary>
      <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted">{a}</p>
    </details>
  );
}
