"""
Servable entrypoint for `jac start`. Deliberately just imports -- no
top-level `with entry` block. jac start imports this module immediately on
boot, and any eager `by llm()` call here would run before the server has
bound a port. `demo.jac` (run locally via `jac run demo.jac`) is where the
scripted two-scenario walkthrough lives.

Importing a module here is what publishes its walkers as REST endpoints, so
this file is also the API surface: every walker below answers on
POST /walker/<name>, and NotchSocket answers on ws://host/ws/NotchSocket.
"""

# --- the concept graph and the precedent walk over it ---
import from schema {
    CodeConcept, File, Commit, Conflict, Decision,
    Touches, Changes, OursCommit, TheirsCommit, OnFile, PrecedentFor, Resolves
}
import from walkers { DetectConflict, CheckPrecedent, Escalate, ApplyDecision }
import from ingest { IngestRepo, concepts_for_path }

# --- identity, projects, and the escalation lifecycle ---
import from identity {
    Developer, Project, RegisterDeveloper, ListDevelopers, CreateProject,
    register_developer, find_developer, developer_for_token, find_project
}
import from escalation {
    Escalation, Ask, Resolve, Pending, Withdraw, pending_for, is_expired
}
import from notchsocket { NotchSocket, NotchStatus }

# --- the push flow: real conflicts, a real agent, real GitHub ---
import from conflict { Change, FileConflict, detect_conflicts, apply_changes, describe_conflict }
import from github { read_head, read_history_since, snapshot_at, verify_repository_contents }
import from push { Push, PushOutcome, SubmitPush, Status }

# `integrate` is deliberately absent. It holds the `by agent_llm(tools=[...])`
# ReAct loop, so importing it loads byllm -- and importing it *here* would do
# that at boot, before the server binds a port, on a host that may not be able
# to load byllm at all. Nothing is lost: IntegrationRun is an `obj` and
# run_integration is a plain `def`, so neither was ever an endpoint. push.jac
# imports them where the work happens. See judge.jac for the full story.

# --- the escalation surface seam and the two by llm() judgments ---
import from surface { EscalationSurface, ScriptedSurface, Escalation as ScriptedEscalation, Resolution }
import from judgment { Verdict }

# --- the browser surface: the same loop as the notch, for a machine that
#     isn't a Mac. The client's `sv import` registers these itself, but the
#     board is also worth having as plain REST, so it is imported here too.
import from board {
    seed_board, board_state, run_scenario, answer_question, reset_board,
    BoardState, RunResult, ConceptView, PendingView, PendingQuestion, AsksAbout
}


cl {
    import from .components.Board { Board }

    def:pub app() -> JsxElement {
        return <Board />;
    }
}
