export function NotchMock() {
  return (
    <div className="mx-auto w-full max-w-lg">
      <div className="flex justify-center">
        <div className="flex h-7 w-36 items-center justify-center gap-2 rounded-b-2xl bg-black">
          <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#e3a458] motion-reduce:animate-none" />
          <span className="h-1 w-10 rounded-full bg-white/10" />
        </div>
      </div>
      <div className="-mt-px rounded-2xl border border-white/10 bg-[#101114] p-5 text-left shadow-[0_30px_60px_-30px_rgba(0,0,0,0.6)] sm:p-6">
        <p className="font-mono text-[11px] tracking-wide text-[#8b8d92] uppercase">
          Synqit needs a decision
        </p>
        <h3 className="mt-2 font-display text-2xl text-[#f2f1ed] italic">
          Free tier removal vs. unlimited free projects
        </h3>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <div className="rounded-lg border border-white/10 bg-white/[0.03] p-3">
            <p className="font-mono text-[11px] text-[#8b8d92]">dev_a &middot; landed on main first</p>
            <p className="mt-1 text-sm text-[#d8d9dc]">Removed the free tier.</p>
          </div>
          <div className="rounded-lg border border-white/10 bg-white/[0.03] p-3">
            <p className="font-mono text-[11px] text-[#8b8d92]">you &middot; pushing now</p>
            <p className="mt-1 text-sm text-[#d8d9dc]">Give free-tier users unlimited projects.</p>
          </div>
        </div>
        <div className="mt-4 flex flex-wrap gap-2">
          <button className="rounded-full bg-[#e2665a]/15 px-3.5 py-1.5 text-sm text-[#e2665a] ring-1 ring-inset ring-[#e2665a]/30">
            Keep mine
          </button>
          <button className="rounded-full bg-[#3fb37f]/15 px-3.5 py-1.5 text-sm text-[#3fb37f] ring-1 ring-inset ring-[#3fb37f]/30">
            Keep theirs
          </button>
          <button className="rounded-full bg-white/[0.06] px-3.5 py-1.5 text-sm text-[#d8d9dc] ring-1 ring-inset ring-white/15">
            Instruct →
          </button>
        </div>
      </div>
      <p className="mt-3 text-center font-mono text-xs text-muted">
        the actual escalation from Synqit&rsquo;s end-to-end test run
      </p>
    </div>
  );
}
