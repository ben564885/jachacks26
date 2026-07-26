"""
The same two judgments as `llm_chain.jac`, over plain HTTP.

This exists so the agent still reasons on a host whose jaclang cannot parse
byllm's shipped `.jac` source -- see the note in `judgment.jac`. It is a real
model call, not a stub: same model, same two prompts, same structured result.
What it loses is the part worth having, which is that `by llm()` states the
signature and nothing else. Here the schema is spelled out by hand, the JSON
is parsed by hand, and a malformed reply is this module's problem.

`requests` is already a dependency for the GitHub API, so this adds nothing to
install -- which is the point, since the reason we are here is a dependency
that would not load.
"""

import os;
import json;
import requests;

import from judgment { Verdict, JudgeResult, EscalationQuestion }

glob COMPLETIONS: str = "https://api.openai.com/v1/chat/completions";


def _model -> str {
    return str(os.environ.get("OPENAI_MODEL") or "gpt-4o-mini");
}


"""Same key byllm reads, so switching backends needs no new configuration."""
def _key -> str {
    key = str(os.environ.get("OPENAI_API_KEY") or "").strip();
    if not key {
        raise ValueError(
            "OPENAI_API_KEY is not set. The HTTP judgment backend needs it for the same "
            + "reason byllm does -- it is the model call."
        );
    }
    return key;
}


"""One completion, forced to return a JSON object. temperature=0 because these
are judgments that should not wander between identical conflicts."""
def _complete(instruction: str, question: str) -> dict[str, any] {
    payload = {
        "model": _model(),
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": instruction},
            {"role": "user", "content": question}
        ]
    };
    response = requests.post(
        COMPLETIONS,
        headers={"Authorization": f"Bearer {_key()}", "Content-Type": "application/json"},
        json=payload,
        timeout=60
    );
    if response.status_code == 401 {
        raise ValueError("OpenAI rejected the API key (401). Check OPENAI_API_KEY.");
    }
    if response.status_code != 200 {
        raise ValueError(f"OpenAI returned {response.status_code}: {response.text[:200]}");
    }
    # `requests` hands back Any at this boundary, so the shape is asserted here
    # rather than trusted three call-sites later.
    body = response.json();
    content: str = str(body["choices"][0]["message"]["content"]);
    return json.loads(content) as dict[str, any];
}


"""The model answers with a verdict name; anything unrecognised escalates.
Defaulting to ESCALATE is the safe direction -- the failure mode is asking a
human something they may have already answered, not deciding for them."""
def _verdict_from(raw: str) -> Verdict {
    name = str(raw or "").strip().upper();
    if name == "APPLY_PRECEDENT" {
        return Verdict.APPLY_PRECEDENT;
    }
    if name == "RESOLVE_MECHANICALLY" {
        return Verdict.RESOLVE_MECHANICALLY;
    }
    return Verdict.ESCALATE;
}


def judge_conflict(
    file_path: str,
    ours_dev: str,
    ours_intent: str,
    theirs_dev: str,
    theirs_intent: str,
    precedent_choices: list[str]
) -> JudgeResult {
    instruction = "You are the integration agent for a shared codebase. Two developers changed "
        + "the same file with different intent. Decide whether this is mechanical (you can "
        + "resolve it), already settled by precedent, or a genuine product decision that needs "
        + "a human. Reply with JSON: {\"verdict\": one of APPLY_PRECEDENT, RESOLVE_MECHANICALLY, "
        + "ESCALATE, \"reasoning\": a short sentence}.";
    known = ", ".join(precedent_choices) if precedent_choices else "none";
    question = f"File: {file_path}\n"
        + f"{ours_dev} wants: {ours_intent}\n"
        + f"{theirs_dev} wants: {theirs_intent}\n"
        + f"Decisions already made on this concept: {known}";
    data = _complete(instruction, question);
    return JudgeResult(
        verdict=_verdict_from(str(data.get("verdict", ""))),
        reasoning=str(data.get("reasoning", ""))
    );
}


def draft_escalation(
    file_path: str,
    ours_dev: str,
    ours_intent: str,
    theirs_dev: str,
    theirs_intent: str
) -> EscalationQuestion {
    instruction = "Turn a merge conflict into the question a developer sees in their notch. "
        + "Be plain and specific; the two options are the two competing intents, not yes/no. "
        + "Reply with JSON: {\"title\": short headline, \"summary\": one or two sentences, "
        + "\"option_a_label\": what taking the first intent means, \"option_b_label\": what "
        + "taking the second means}.";
    question = f"File: {file_path}\n"
        + f"{ours_dev} wants: {ours_intent}\n"
        + f"{theirs_dev} wants: {theirs_intent}";
    data = _complete(instruction, question);
    return EscalationQuestion(
        title=str(data.get("title", "Escalation")),
        summary=str(data.get("summary", "")),
        option_a_label=str(data.get("option_a_label", ours_intent)),
        option_b_label=str(data.get("option_b_label", theirs_intent))
    );
}
