"""
The shape of a judgment: what the agent decides, and what it asks.

Types only, and no imports beyond them. Both implementations
(`llm_chain.jac` via `by llm()`, `llm_http.jac` over HTTP) depend on this
module, and `judge.jac` picks between them -- so this one has to stay a leaf.
An earlier version kept these next to the dispatcher, which made the graph
cyclic and left the type checker binding two different `JudgeResult`s.
"""

enum Verdict {
    APPLY_PRECEDENT,
    RESOLVE_MECHANICALLY,
    ESCALATE
}

obj JudgeResult {
    has verdict: Verdict;
    has reasoning: str;
}

obj EscalationQuestion {
    has title: str;
    has summary: str;
    has option_a_label: str;
    has option_b_label: str;
}
