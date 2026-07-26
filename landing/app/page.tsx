import { Nav } from "./components/Nav";
import { NotchMock } from "./components/NotchMock";
import { TerminalWindow } from "./components/TerminalWindow";
import { DetailSection, Eyebrow, FaqItem, FeatureCard, TrunkDivider } from "./components/ui";

const FEATURES = [
  {
    title: "No branches",
    body: "One shared main. Nothing to fork, nothing to open a pull request against.",
  },
  {
    title: "Human escalation",
    body: "A genuine product decision stops the agent and asks — instead of guessing and shipping the wrong call.",
  },
  {
    title: "Native notch",
    body: "A real macOS menu-bar app. Always there, out of the way until it isn't.",
  },
  {
    title: "Precedent memory",
    body: "Once you've decided a concept, the same question isn't asked twice — even from a different file.",
  },
  {
    title: "Full audit trail",
    body: "Every push, every decision, every commit — attributed and written into the history, not a side log.",
  },
  {
    title: "Timeout safety",
    body: "An unanswered question expires in five minutes. Your local work is never touched.",
  },
  {
    title: "Per-developer identity",
    body: "Scoped tokens. Nobody sees or resolves a conflict that isn't theirs.",
  },
  {
    title: "GitHub-backed",
    body: "Real commits, on your real main. doctor verifies the token can actually write before you ever push.",
  },
  {
    title: "Open source",
    body: "MIT licensed, self-hosted. Fork it, read every line that runs your pushes.",
  },
];

const ROADMAP = [
  "Slack surface",
  "Windows / Linux client",
  "VS Code extension",
  "Team activity dashboard",
  "Multi-repo orchestration",
  "Bring your own model",
];

const FAQS = [
  {
    q: "How is this different from reviewing pull requests?",
    a: "There's nothing to review. One shared main — the agent integrates continuously, and only stops you for a real product call, not a stylistic one.",
  },
  {
    q: "Does this replace Git?",
    a: "No. It replaces branches, pull requests, and merges on top of Git. GitHub stays the source of truth for every commit.",
  },
  {
    q: "What happens if I don't answer in time?",
    a: "The push ends in needs_human after five minutes. Your local work is never touched — you can answer later and push again.",
  },
  {
    q: "Is my code sent to a third party?",
    a: "The integration agent calls an LLM (OpenRouter by default, or your own pinned model) to reason about conflicts. Only the changed files and their intent are sent — see the docs for exactly what leaves the server.",
  },
  {
    q: "Can multiple people push at once?",
    a: "Pushes are serialized per project — one queue, one integration at a time. No simultaneous integration race to corrupt main.",
  },
  {
    q: "What if I haven't installed the notch?",
    a: "A conflicting push returns needs_human immediately instead of hanging. Your work stays local and unchanged until you attach a notch.",
  },
  {
    q: "What LLM does the integration agent use?",
    a: "Configurable at synqit configure — OpenRouter by default. Pin any tool-capable model; a free router can pick a different backing model per call, so pin one before relying on stable behavior.",
  },
  {
    q: "Is Synqit open source?",
    a: "Yes — MIT licensed. Fork it, self-host it, or swap the escalation surface for your own.",
  },
];

export default function Home() {
  return (
    <div id="top" className="flex min-h-screen flex-col">
      <Nav />

      {/* Hero */}
      <section className="relative overflow-hidden px-6 pt-20 pb-24 text-center">
        <div className="mx-auto max-w-3xl">
          <Eyebrow>Open source · self-hosted</Eyebrow>
          <h1 className="mt-6 font-display text-5xl leading-[1.05] sm:text-6xl">
            One shared main.
            <br />
            <span className="text-accent italic">No branches to review.</span>
          </h1>
          <p className="mx-auto mt-6 max-w-xl text-lg leading-relaxed text-muted">
            Push a feature. An agent integrates it into the newest main. When it hits a
            decision only you can make — not a merge conflict, a product one — it asks.
            Right in your notch.
          </p>
          <div className="mt-8 flex items-center justify-center gap-3">
            <a
              href="#quickstart"
              className="rounded-full bg-accent px-5 py-2.5 text-sm font-medium text-accent-contrast transition hover:opacity-90"
            >
              Get started
            </a>
            <a
              href="https://github.com/ben564885/jachacks26"
              className="rounded-full border border-border px-5 py-2.5 text-sm font-medium text-text transition hover:border-accent/50"
            >
              GitHub ↗
            </a>
          </div>
        </div>

        <div className="mt-16">
          <NotchMock />
        </div>
      </section>

      <TrunkDivider notch />

      {/* Quickstart */}
      <section id="quickstart" className="py-20">
        <div className="mx-auto grid max-w-6xl items-center gap-12 px-6 lg:grid-cols-2 lg:gap-20">
          <div>
            <Eyebrow>Quickstart</Eyebrow>
            <h2 className="mt-4 font-display text-4xl italic">Running in one command.</h2>
            <p className="mt-4 max-w-md text-[15px] leading-relaxed text-muted">
              Open source. Self-hosted. The first run walks you through your GitHub token and
              OpenRouter key — every run after that just listens.
            </p>
            <div className="mt-6 flex items-center gap-5">
              <a
                href="https://github.com/ben564885/jachacks26"
                className="rounded-full bg-text px-4 py-2 text-sm font-medium text-bg transition hover:opacity-85"
              >
                ★ Star on GitHub
              </a>
              <a href="#faq" className="text-sm font-medium text-text hover:text-accent">
                Read the docs →
              </a>
            </div>
          </div>
          <TerminalWindow
            lines={[
              { text: "git clone https://github.com/ben564885/jachacks26.git" },
              { text: "cd jachacks26 && make server", dim: "  # listens on :8899" },
            ]}
          />
        </div>
      </section>

      <TrunkDivider />

      {/* How it works */}
      <section id="how-it-works" className="py-20">
        <div className="mx-auto max-w-6xl px-6">
          <div className="max-w-xl">
            <Eyebrow>How it works</Eyebrow>
            <h2 className="mt-4 font-display text-4xl italic">From push to shared main.</h2>
          </div>
          <div className="mt-12 grid gap-8 sm:grid-cols-3">
            {[
              {
                n: "01",
                t: "Push your feature",
                d: (
                  <>
                    Describe the change in plain English:{" "}
                    <span className="font-mono text-[13px] text-text">
                      synqit push &quot;add avatars&quot;
                    </span>
                  </>
                ),
              },
              {
                n: "02",
                t: "An agent integrates it",
                d: "It reads the newest main and resolves anything it can safely decide on its own.",
              },
              {
                n: "03",
                t: "You decide, only when it matters",
                d: "A genuine product conflict becomes three choices, right in your notch.",
              },
            ].map((step) => (
              <div key={step.n} className="border-t border-border pt-5">
                <span className="font-mono text-sm text-accent">{step.n}</span>
                <h3 className="mt-2 font-medium text-text">{step.t}</h3>
                <p className="mt-1.5 text-sm leading-relaxed text-muted">{step.d}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Status mock / second big visual */}
      <section className="py-10">
        <div className="mx-auto max-w-6xl px-6 text-center">
          <h2 className="font-display text-3xl italic sm:text-4xl">
            See your workspace, not your diff.
          </h2>
          <div className="mx-auto mt-10 max-w-xl text-left">
            <TerminalWindow
              lines={[
                { text: "synqit status" },
                { prompt: false, text: "Synqit project: pricing-service" },
                { prompt: false, text: "  server: http://127.0.0.1:8899" },
                { prompt: false, text: "  local changes ready to push: 2" },
                { prompt: false, text: "  you: dev_ben" },
                { prompt: false, text: "  notch: attached" },
                { prompt: false, text: "  shared GitHub commit: a91f3c2", dim: " (up to date)" },
              ]}
            />
          </div>
        </div>
      </section>

      <TrunkDivider />

      {/* Features grid */}
      <section id="features" className="py-20">
        <div className="mx-auto max-w-6xl px-6">
          <div className="max-w-xl">
            <Eyebrow>Features</Eyebrow>
            <h2 className="mt-4 font-display text-4xl italic">
              Everything shared source control needs to not be Git-plus-a-chatbot.
            </h2>
          </div>
          <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {FEATURES.map((f) => (
              <FeatureCard key={f.title} title={f.title}>
                {f.body}
              </FeatureCard>
            ))}
          </div>
        </div>
      </section>

      {/* Alternating detail sections */}
      <DetailSection
        eyebrow="Bring your own repo"
        heading="Any GitHub repo, one fine-grained token."
        visual={
          <TerminalWindow
            lines={[
              { prompt: false, text: "✓ GitHub token configured" },
              { prompt: false, text: "✓ OpenRouter API key configured" },
              {
                prompt: false,
                text: "✓ Contents verified on acme/pricing-service",
                dim: " at a91f3c2",
              },
            ]}
          />
        }
      >
        <p>
          Point Synqit at a repo with Contents: read and write. doctor --verify exercises the
          permission for real, against a real ref — not an identity check that passes for any
          token and then fails on your first push.
        </p>
      </DetailSection>

      <DetailSection
        eyebrow="Precedent memory"
        heading="Ask once. Never ask again."
        reverse
        visual={
          <div className="rounded-xl border border-border bg-surface p-8">
            <svg
              viewBox="0 0 320 160"
              className="w-full"
              role="img"
              aria-label="Two files reaching the same concept, one decision recorded against it"
            >
              <g fill="none" stroke="var(--border)" strokeWidth="1.5">
                <line x1="40" y1="40" x2="160" y2="90" />
                <line x1="40" y1="140" x2="160" y2="90" />
                <line x1="160" y1="90" x2="270" y2="90" />
              </g>
              <circle cx="40" cy="40" r="6" fill="var(--text-muted, #5b5d63)" />
              <circle cx="40" cy="140" r="6" fill="var(--text-muted, #5b5d63)" />
              <circle cx="160" cy="90" r="9" fill="var(--accent)" />
              <circle cx="270" cy="90" r="6" fill="var(--text-muted, #5b5d63)" />
              <g fontFamily="ui-monospace, monospace" fontSize="10" fill="currentColor">
                <text x="10" y="30">pricing.js</text>
                <text x="4" y="158">billing_test.js</text>
                <text x="132" y="72">FreeTier</text>
                <text x="238" y="80">Decision</text>
              </g>
            </svg>
          </div>
        }
      >
        <p>
          A decision isn&rsquo;t just logged — it&rsquo;s written back into the graph as
          precedent for every concept the conflict touched. The next collision on the same
          idea, even in a different file, resolves on its own.
        </p>
      </DetailSection>

      <DetailSection
        eyebrow="Timeout safety"
        heading="Escalations that don't hang your team."
        dark
        visual={
          <div className="space-y-3 rounded-xl border border-white/10 bg-white/[0.03] p-6 font-mono text-sm">
            {["dev_ben", "dev_ana", "dev_theo"].map((dev, i) => (
              <div key={dev} className="flex items-center gap-3">
                <span className="w-20 shrink-0 text-[#9a9ca3]">{dev}</span>
                <div className="h-1.5 flex-1 rounded-full bg-white/10">
                  <div
                    className="h-1.5 rounded-full bg-[#e3a458]"
                    style={{ width: `${[62, 100, 18][i]}%` }}
                  />
                </div>
                <span className="w-16 text-right text-[#9a9ca3]">
                  {["3:07", "expired", "0:54"][i]}
                </span>
              </div>
            ))}
          </div>
        }
      >
        <ul className="space-y-2">
          <li>— A question waits five minutes, not forever.</li>
          <li>— No answer? The push ends in needs_human — your local work untouched.</li>
          <li>— Every fallback is today&rsquo;s behavior: no notch, a timeout, too many rounds.</li>
          <li>— One slow decision never wedges the rest of the queue.</li>
        </ul>
      </DetailSection>

      <DetailSection
        eyebrow="Audit trail"
        heading="Every push explains itself."
        reverse
        visual={
          <div className="overflow-x-auto rounded-xl border border-border bg-surface">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="border-b border-border text-xs text-muted uppercase">
                  <th className="px-4 py-3 font-normal">Commit</th>
                  <th className="px-4 py-3 font-normal">Decision</th>
                  <th className="px-4 py-3 font-normal">Dev</th>
                </tr>
              </thead>
              <tbody className="font-mono text-[13px] [font-variant-numeric:tabular-nums]">
                {[
                  ["a91f3c2", "kept theirs", "dev_ana"],
                  ["7c2e0d1", "mechanical", "—"],
                  ["e58b420", "instructed", "dev_ben"],
                ].map((row) => (
                  <tr key={row[0]} className="border-b border-border last:border-0">
                    <td className="px-4 py-3 text-text">{row[0]}</td>
                    <td className="px-4 py-3 text-muted">{row[1]}</td>
                    <td className="px-4 py-3 text-muted">{row[2]}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        }
      >
        <p>
          Which decision was made, and why, is part of the published commit message — not a
          side channel that drifts from what actually shipped.
        </p>
      </DetailSection>

      <DetailSection
        eyebrow="Multi-project"
        heading="One shared queue, however many repos."
        visual={
          <div className="grid grid-cols-2 gap-3">
            {["pricing-service", "marketing-site", "mobile-app"].map((p) => (
              <div key={p} className="rounded-lg border border-border bg-surface p-4">
                <p className="text-sm font-medium text-text">{p}</p>
                <p className="mt-1 font-mono text-xs text-ok">active</p>
              </div>
            ))}
            <div className="flex items-center justify-center rounded-lg border border-dashed border-border p-4 text-sm text-muted">
              + Add project
            </div>
          </div>
        }
      >
        <p>
          One person runs one server. Every project your team connects shares the same
          notch, the same identity, the same escalation surface.
        </p>
      </DetailSection>

      <TrunkDivider />

      {/* Open source */}
      <section className="py-20">
        <div className="mx-auto max-w-6xl px-6">
          <div className="max-w-xl">
            <Eyebrow>Open source</Eyebrow>
            <h2 className="mt-4 font-display text-4xl italic">
              Extensible, adaptable, open source.
            </h2>
          </div>
          <div className="mt-10 grid gap-4 sm:grid-cols-3">
            <FeatureCard title="Self-hosted">
              Runs on your machine or your infrastructure. No Synqit account, ever.
            </FeatureCard>
            <FeatureCard title="MIT licensed">
              Fork it, read it, ship your own escalation surface on top of it.
            </FeatureCard>
            <FeatureCard title="Extensible">
              The EscalationSurface seam means Slack, Linear, or your own UI can plug in
              exactly where the notch does.
            </FeatureCard>
          </div>
        </div>
      </section>

      {/* Roadmap */}
      <section className="py-20">
        <div className="mx-auto max-w-6xl px-6">
          <Eyebrow>Roadmap</Eyebrow>
          <h2 className="mt-4 font-display text-4xl italic">
            Where a surface could plug in next.
          </h2>
          <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {ROADMAP.map((r) => (
              <div
                key={r}
                className="flex items-center justify-between rounded-xl border border-dashed border-border p-5 text-muted"
              >
                <span className="text-sm">{r}</span>
                <span className="rounded-full bg-surface-2 px-2.5 py-1 font-mono text-[11px] tracking-wide uppercase">
                  Soon
                </span>
              </div>
            ))}
            <a
              href="https://github.com/ben564885/jachacks26"
              className="flex items-center justify-center rounded-xl border border-border p-5 text-sm font-medium text-text hover:border-accent/50"
            >
              Suggest a surface →
            </a>
          </div>
        </div>
      </section>

      <TrunkDivider />

      {/* FAQ */}
      <section id="faq" className="py-20">
        <div className="mx-auto max-w-3xl px-6">
          <Eyebrow>FAQ</Eyebrow>
          <h2 className="mt-4 font-display text-4xl italic">Questions, answered.</h2>
          <div className="mt-8">
            {FAQS.map((f) => (
              <FaqItem key={f.q} q={f.q} a={f.a} />
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="bg-surface-2 py-24 text-center">
        <div className="mx-auto max-w-2xl px-6">
          <Eyebrow>Get started</Eyebrow>
          <h2 className="mt-4 font-display text-4xl italic sm:text-5xl">
            From clone to shared main in one command.
          </h2>
          <div className="mx-auto mt-8 max-w-md text-left">
            <TerminalWindow
              lines={[
                { text: "git clone https://github.com/ben564885/jachacks26.git" },
                { text: "cd jachacks26 && make server" },
              ]}
            />
          </div>
          <p className="mx-auto mt-6 max-w-md text-sm text-muted">
            Open source. Self-hosted. First run walks you through setup — no Synqit account
            required.
          </p>
          <div className="mt-6 flex items-center justify-center gap-3">
            <a
              href="https://github.com/ben564885/jachacks26"
              className="rounded-full bg-text px-4 py-2 text-sm font-medium text-bg transition hover:opacity-85"
            >
              ★ Star on GitHub
            </a>
            <a href="#faq" className="text-sm font-medium text-text hover:text-accent">
              Read the docs →
            </a>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="mt-auto bg-[#0b0c0f] py-16 text-[#c3c4c8]">
        <div className="mx-auto max-w-6xl px-6">
          <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <p className="flex items-center gap-2 font-mono text-sm text-[#f2f1ed]">
                <span className="relative inline-flex h-4 w-7 items-center justify-center rounded-full bg-[#f2f1ed]">
                  <span className="h-1.5 w-1.5 rounded-full bg-[#e3a458]" />
                </span>
                synqit
              </p>
              <p className="mt-3 max-w-[22ch] text-sm text-[#7a7c82]">
                A conflict becomes a question, not a rejected push.
              </p>
            </div>
            <div>
              <p className="font-mono text-xs tracking-wide text-[#7a7c82] uppercase">
                Product
              </p>
              <ul className="mt-3 space-y-2 text-sm">
                <li>
                  <a href="#quickstart" className="hover:text-white">
                    Get started
                  </a>
                </li>
                <li>
                  <a href="#how-it-works" className="hover:text-white">
                    How it works
                  </a>
                </li>
              </ul>
            </div>
            <div>
              <p className="font-mono text-xs tracking-wide text-[#7a7c82] uppercase">
                Platform
              </p>
              <ul className="mt-3 space-y-2 text-sm">
                <li>
                  <a href="#features" className="hover:text-white">
                    Notch
                  </a>
                </li>
                <li>
                  <a href="#features" className="hover:text-white">
                    Server
                  </a>
                </li>
                <li>
                  <a href="#features" className="hover:text-white">
                    Precedent memory
                  </a>
                </li>
              </ul>
            </div>
            <div>
              <p className="font-mono text-xs tracking-wide text-[#7a7c82] uppercase">
                Developer
              </p>
              <ul className="mt-3 space-y-2 text-sm">
                <li>
                  <a href="https://github.com/ben564885/jachacks26" className="hover:text-white">
                    GitHub
                  </a>
                </li>
                <li>
                  <a href="#faq" className="hover:text-white">
                    FAQ
                  </a>
                </li>
              </ul>
            </div>
          </div>
          <div className="mt-12 flex flex-col-reverse items-center justify-between gap-4 border-t border-white/10 pt-6 text-xs text-[#7a7c82] sm:flex-row">
            <span>© 2026 synqit. Open source under MIT.</span>
          </div>
        </div>
      </footer>
    </div>
  );
}
