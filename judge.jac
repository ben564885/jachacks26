"""
Who answers a judgment.

The two judgments the agent makes -- is this mine to resolve, and if not, what
exactly am I asking the human -- have one shape (`judgment.jac`) and two
implementations. `llm_chain.jac` expresses them as `by llm()`, which is the
point of writing this in Jac at all. `llm_http.jac` is the same two judgments
over plain HTTP.

Why both: byllm ships its own `.jac` source, which the *host's* jaclang parses
at import. A managed host that supplies a jaclang other than the one byllm was
built against rejects that source outright, and the failure lands on
`import from byllm.llm` at boot -- a syntax error in a file nobody here wrote,
in a module this project only wanted two functions from. No project pin can
reconcile it: every published byllm carries the syntax, and every published
jaclang accepts it, so the mismatch is with a jaclang that is neither.

So the byllm import happens inside these functions, where it can be caught,
rather than at module scope where it takes the whole server down. `by llm()`
is still what gets tried first. Neither the walkers nor the graph know which
implementation answered.

Set `SYNQIT_LLM_BACKEND` to pin it: `byllm` to require the Jac-native path and
fail loudly if it is unavailable, `http` to skip it. Default is `auto`.
"""

import os;

import from judgment { Verdict, JudgeResult, EscalationQuestion }


def selected_backend -> str {
    return str(os.environ.get("SYNQIT_LLM_BACKEND") or "auto").strip().lower();
}


"""Which implementation would answer right now. Resolving it means attempting
the byllm import, so this is a probe rather than a cached flag."""
def active_backend -> str {
    choice = selected_backend();
    if choice == "http" {
        return "http";
    }
    try {
        import from llm_chain { judge_conflict as probe }
        return "byllm";
    } except Exception as err {
        if choice == "byllm" {
            raise;
        }
        return "http";
    }
}


"""Step 1. Given the two competing intents on the same file, and any decisions
this project has already made about the same concept, decide whether this is
mechanical, already answered by precedent, or a genuine product decision that
needs a human."""
def judge_conflict(
    file_path: str,
    ours_dev: str,
    ours_intent: str,
    theirs_dev: str,
    theirs_intent: str,
    precedent_choices: list[str]
) -> JudgeResult {
    choice = selected_backend();
    if choice != "http" {
        try {
            import from llm_chain { judge_conflict as judge_by_llm }
            return judge_by_llm(
                file_path, ours_dev, ours_intent, theirs_dev, theirs_intent, precedent_choices
            );
        } except Exception as err {
            if choice == "byllm" {
                raise;
            }
        }
    }
    import from llm_http { judge_conflict as judge_over_http }
    return judge_over_http(
        file_path, ours_dev, ours_intent, theirs_dev, theirs_intent, precedent_choices
    );
}


"""Step 2. Only called when step 1 says ESCALATE. Turn the raw intents into
the plain-language question a developer sees in the escalation surface."""
def draft_escalation(
    file_path: str,
    ours_dev: str,
    ours_intent: str,
    theirs_dev: str,
    theirs_intent: str
) -> EscalationQuestion {
    choice = selected_backend();
    if choice != "http" {
        try {
            import from llm_chain { draft_escalation as draft_by_llm }
            return draft_by_llm(
                file_path, ours_dev, ours_intent, theirs_dev, theirs_intent
            );
        } except Exception as err {
            if choice == "byllm" {
                raise;
            }
        }
    }
    import from llm_http { draft_escalation as draft_over_http }
    return draft_over_http(file_path, ours_dev, ours_intent, theirs_dev, theirs_intent);
}
