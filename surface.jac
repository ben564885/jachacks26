"""
The seam. This wire shape mirrors the escalation/resolution contract Synqit
Notch already speaks over WebSocket (see the README at the repo root) so the
real macOS notch can be dropped in as a second EscalationSurface without
touching a single walker. `choice` stays "green"/"red"/"other" for the same
reason -- it is already what the notch renders.

TerminalSurface is the fallback decided at the 3pm checkpoint: if the native
notch isn't reliably wired up by then, every walker keeps working unchanged
against this instead.
"""

obj Escalation {
    has conflict_id: str;
    has dev_id: str;
    has title: str;
    has summary: str;
    has file: str;
    has option_green: str;
    has option_red: str;
}

obj Resolution {
    has conflict_id: str;
    has choice: str;  # "green" | "red" | "other"
    has custom_text: str | None = None;
}

obj EscalationSurface {
    def ask(escalation: Escalation) -> Resolution abs;
}

obj TerminalSurface(EscalationSurface) {
    override def ask(escalation: Escalation) -> Resolution {
        print(f"\n--- ESCALATION {escalation.conflict_id} (for {escalation.dev_id}) ---");
        print(f"file: {escalation.file}");
        print(escalation.title);
        print(escalation.summary);
        print(f"  [g] {escalation.option_green}");
        print(f"  [r] {escalation.option_red}");
        print("  [i] instruct (custom answer)");
        choice = input("your call (g/r/i): ").strip().lower();
        if choice == "i" {
            text = input("instruction: ");
            return Resolution(conflict_id=escalation.conflict_id, choice="other", custom_text=text);
        }
        picked = "green" if choice == "g" else "red";
        return Resolution(conflict_id=escalation.conflict_id, choice=picked);
    }
}

"""Non-interactive surface for automated test runs / CI: always picks a
fixed side instead of blocking on stdin."""
obj ScriptedSurface(EscalationSurface) {
    has answers: dict[str, str];  # conflict_id -> "green" | "red" | "other"

    override def ask(escalation: Escalation) -> Resolution {
        choice = self.answers.get(escalation.conflict_id, "green");
        print(f"\n--- ESCALATION {escalation.conflict_id} (for {escalation.dev_id}) ---");
        print(escalation.title);
        print(f"  -> scripted answer: {choice}");
        return Resolution(conflict_id=escalation.conflict_id, choice=choice);
    }
}
