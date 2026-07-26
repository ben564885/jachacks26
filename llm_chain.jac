"""
The agent's reasoning, broken into the three separate judgment calls it
actually needs to make -- not one prompt asked to do everything at once.

This is the Jac-native path and the one worth reading: a signature, a
docstring, and `by llm()`. There is no prompt template, no JSON schema and no
parsing anywhere in this file -- the return type *is* the schema, and byllm
fills it in. `llm_http.jac` is the same two judgments written out by hand; the
difference between the two files is the argument for the language.

Nothing imports this module at boot. `judgment.jac` imports it inside the
function that needs it, so a host that cannot load byllm still starts. The
types live in `judgment.jac` for the same reason: importing them must not drag
byllm in with them.
"""

import from byllm.llm { Model }

import from judgment { Verdict, JudgeResult, EscalationQuestion }

glob llm = Model(model_name="gpt-4o-mini");


"""Step 1. Given the two competing intents on the same file, and any
decisions this project has already made about the same concept, decide
whether this is mechanical, already answered by precedent, or a genuine
product decision that needs a human."""
def judge_conflict(
    file_path: str,
    ours_dev: str,
    ours_intent: str,
    theirs_dev: str,
    theirs_intent: str,
    precedent_choices: list[str]
) -> JudgeResult by llm();

"""Step 2. Only called when step 1 says ESCALATE. Turn the raw intents into
the plain-language question a developer sees in the escalation surface."""
def draft_escalation(
    file_path: str,
    ours_dev: str,
    ours_intent: str,
    theirs_dev: str,
    theirs_intent: str
) -> EscalationQuestion by llm();
