"""
The web surface of the demo, as server endpoints.

The macOS notch is the real escalation surface; this is the same seam for a
browser, so the whole loop can be shown on a machine that isn't a Mac. Every
function here is `def:pub` -- the demo board is meant to be opened by anyone
with the URL, unlike the walkers in `escalation.jac`, which are scoped to the
developer their token proved.

Nothing here re-implements the system. It seeds the graph from
`scenarios.jac`, drives the same `DetectConflict` / `CheckPrecedent` /
`ApplyDecision` walkers, and asks `judge.jac` the same two questions. The one
thing it adds is `PendingQuestion`: the notch can block on a human because it
is a socket, and an HTTP request cannot, so the drafted question is parked on
the graph and the browser picks it up on the next read.
"""

import secrets;

import from schema { CodeConcept, File, Conflict, Decision, Touches, OnFile, PrecedentFor, Resolves }
import from walkers { DetectConflict, CheckPrecedent, ApplyDecision }
import from judgment { Verdict }
import from judge { judge_conflict, draft_escalation, active_backend }
import from scenarios { build_codebase_graph, Scenario, SCENARIO_1, SCENARIO_2 }


node PendingQuestion {
    has conflict_id: str;
    has file: str;
    has title: str;
    has summary: str;
    has option_green: str;
    has option_red: str;
    has status: str = "open";      # open | answered
    has choice: str = "";
}

edge AsksAbout {}


obj PendingView {
    has conflict_id: str;
    has file: str;
    has title: str;
    has summary: str;
    has option_green: str;
    has option_red: str;
}

obj ConceptView {
    has name: str;
    has files: list[str];
    has decisions: list[str];
}

obj RunResult {
    has conflict_id: str;
    has file: str;
    has verdict: str;
    has reasoning: str;
    has escalated: bool;
    has precedent_choices: list[str];
    has applied_choice: str;
    has error: str;
}

obj BoardState {
    has seeded: bool;
    has backend: str;
    has concepts: list[ConceptView];
    has pending: list[PendingView];
    has decisions: list[str];
}


"""Idempotent. `build_codebase_graph` would happily create a second FreeTier
on every call, and two concepts means the precedent walk in scenario 2 finds
nothing -- the demo would quietly stop demonstrating its own point."""
def ensure_graph -> dict[str, File] {
    existing = [root -->[?:File]] as list[File];
    if existing {
        by_path: dict[str, File] = {};
        for f in existing {
            by_path[f.path] = f;
        }
        return by_path;
    }
    return build_codebase_graph();
}


def _scenario_for(which: str) -> Scenario {
    return SCENARIO_2 if str(which).strip() == "2" else SCENARIO_1;
}


def _find_conflict(wanted: str) -> Conflict | None {
    found = [root -->[?:Conflict, id == wanted]];
    return found[0] if found else None;
}


def _find_question(wanted: str) -> PendingQuestion | None {
    found = [root -->[?:PendingQuestion, conflict_id == wanted]];
    return found[0] if found else None;
}


def _concept_views -> list[ConceptView] {
    views: list[ConceptView] = [];
    concepts = [root -->[?:CodeConcept]] as list[CodeConcept];
    for c in concepts {
        touching_files = [c <-:Touches:<-] as list[File];
        prior = [c <-:PrecedentFor:<-] as list[Decision];
        views.append(ConceptView(
            name=c.name,
            files=[f.path for f in touching_files],
            decisions=[d.choice for d in prior]
        ));
    }
    return views;
}


def _pending_views -> list[PendingView] {
    open_ones: list[PendingView] = [];
    questions = [root -->[?:PendingQuestion]] as list[PendingQuestion];
    for q in questions {
        if q.status == "open" {
            open_ones.append(PendingView(
                conflict_id=q.conflict_id,
                file=q.file,
                title=q.title,
                summary=q.summary,
                option_green=q.option_green,
                option_red=q.option_red
            ));
        }
    }
    return open_ones;
}


def _state(seeded: bool) -> BoardState {
    made = [root -->[?:Decision]] as list[Decision];
    return BoardState(
        seeded=seeded,
        backend=active_backend(),
        concepts=_concept_views(),
        pending=_pending_views(),
        decisions=[d.choice for d in made]
    );
}


"""Build the two-file codebase graph and report what is on it."""
def:pub seed_board -> BoardState {
    ensure_graph();
    return _state(True);
}


"""Read-only view: concepts, what touches them, what has been decided, and
anything still waiting on a human."""
def:pub board_state -> BoardState {
    return _state(len([root -->[?:File]]) > 0);
}


"""Run one seeded scenario through the real walkers. Scenario 1 has no
precedent and escalates; scenario 2 is a different file reaching the same
concept, so the precedent walk answers it without asking anyone."""
def:pub run_scenario(which: str) -> RunResult {
    files = ensure_graph();
    scenario = _scenario_for(which);
    file_node = files.get(scenario.file_path);
    if file_node is None {
        return RunResult(
            conflict_id=scenario.conflict_id, file=scenario.file_path, verdict="",
            reasoning="", escalated=False, precedent_choices=[], applied_choice="",
            error=f"{scenario.file_path} is not on the graph. Seed the board first."
        );
    }

    existing = _find_conflict(scenario.conflict_id);
    if existing is None {
        detected = file_node spawn DetectConflict(
            conflict_id=scenario.conflict_id,
            ours_dev=scenario.ours_dev,
            ours_intent=scenario.ours_intent,
            ours_diff=scenario.ours_diff,
            theirs_dev=scenario.theirs_dev,
            theirs_intent=scenario.theirs_intent,
            theirs_diff=scenario.theirs_diff
        );
        conflict = detected.reports[0] as Conflict;
    } else {
        conflict = existing;
    }

    checked = conflict spawn CheckPrecedent();
    precedent: list[str] = checked.precedent_choices;

    # The judgment is the only part that needs a model. Everything above and
    # below is graph work, so a missing key costs the verdict -- not the demo.
    try {
        judged = judge_conflict(
            scenario.file_path,
            scenario.ours_dev, scenario.ours_intent,
            scenario.theirs_dev, scenario.theirs_intent,
            precedent
        );
    } except Exception as err {
        return RunResult(
            conflict_id=scenario.conflict_id, file=scenario.file_path, verdict="",
            reasoning="", escalated=False, precedent_choices=precedent,
            applied_choice="", error=str(err)
        );
    }

    if judged.verdict == Verdict.APPLY_PRECEDENT and precedent {
        conflict spawn ApplyDecision(
            decision_id=f"d_{secrets.token_hex(4)}",
            choice=precedent[0],
            reasoning=judged.reasoning,
            via_precedent=True
        );
        return RunResult(
            conflict_id=scenario.conflict_id, file=scenario.file_path,
            verdict="APPLY_PRECEDENT", reasoning=judged.reasoning, escalated=False,
            precedent_choices=precedent, applied_choice=precedent[0], error=""
        );
    }

    if judged.verdict == Verdict.ESCALATE {
        if _find_question(scenario.conflict_id) is None {
            try {
                question = draft_escalation(
                    scenario.file_path,
                    scenario.ours_dev, scenario.ours_intent,
                    scenario.theirs_dev, scenario.theirs_intent
                );
            } except Exception as err {
                return RunResult(
                    conflict_id=scenario.conflict_id, file=scenario.file_path,
                    verdict="ESCALATE", reasoning=judged.reasoning, escalated=False,
                    precedent_choices=precedent, applied_choice="", error=str(err)
                );
            }
            pending = PendingQuestion(
                conflict_id=scenario.conflict_id,
                file=scenario.file_path,
                title=question.title,
                summary=question.summary,
                option_green=question.option_a_label,
                option_red=question.option_b_label
            );
            root ++> pending;
            pending +>:AsksAbout:+> conflict;
        }
        return RunResult(
            conflict_id=scenario.conflict_id, file=scenario.file_path,
            verdict="ESCALATE", reasoning=judged.reasoning, escalated=True,
            precedent_choices=precedent, applied_choice="", error=""
        );
    }

    return RunResult(
        conflict_id=scenario.conflict_id, file=scenario.file_path,
        verdict="RESOLVE_MECHANICALLY", reasoning=judged.reasoning, escalated=False,
        precedent_choices=precedent, applied_choice="", error=""
    );
}


"""The human's answer. Writes a Decision resolving this conflict and made
precedent for every concept its file touches -- which is the whole learning
mechanism, and why the next scenario never reaches a person."""
def:pub answer_question(conflict_id: str, choice: str) -> BoardState {
    question = _find_question(conflict_id);
    conflict = _find_conflict(conflict_id);
    if question is None or conflict is None {
        return _state(True);
    }
    question.status = "answered";
    question.choice = choice;
    conflict spawn ApplyDecision(
        decision_id=f"d_{secrets.token_hex(4)}",
        choice=choice,
        reasoning="answered on the board",
        via_precedent=False
    );
    return _state(True);
}


"""Wipe conflicts, decisions and questions but keep the codebase graph, so the
demo can be run again from the top in front of the next person."""
def:pub reset_board -> BoardState {
    for q in [root -->[?:PendingQuestion]] {
        del q;
    }
    for d in [root -->[?:Decision]] {
        del d;
    }
    for c in [root -->[?:Conflict]] {
        del c;
    }
    return _state(len([root -->[?:File]]) > 0);
}
