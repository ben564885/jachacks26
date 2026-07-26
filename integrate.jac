"""
Port of server/src/agent.js -- the integration agent.

The JS original is 190 lines, and most of them are scaffolding rather than
judgment: hand-written JSON schemas for six tools, a 30-turn dispatch loop,
manual message-history bookkeeping, and per-tool argument validation. Jac's
`by llm(tools=[...])` is a native ReAct loop, so all of that disappears and
what is left is the part that was ever actually interesting -- the tools
themselves and the prompt that says when to ask a human.

The one rule this agent exists to enforce: undoing another developer's
deliberate decision without asking is the thing it must never do.
"""

import from byllm.lib { Model }
import from conflict { Change, FileConflict, describe_conflict }
import from github { RecentCommit }


glob agent_llm: Model = Model(model_name="gpt-4o-mini");

# How many times one integration may go back to the developer before giving
# up. Without a cap a confused agent could ping-pong against a human forever.
glob MAX_ESCALATIONS: int = 3;


obj Workspace {
    has files: dict[str, str];
    has base: dict[str, str];
    has activity: list[str] = [];
}


obj IntegrationResult {
    has status: str;              # integrated | needs_human
    has summary: str = "";
    has reason: str = "";
    has asked: bool = False;
    has question_title: str = "";
    has question_reason: str = "";
}
sem IntegrationResult.status = "Either 'integrated' when the feature is fully implemented, or 'needs_human' when a product decision belongs to a person.";
sem IntegrationResult.summary = "One sentence describing what was integrated. Only when status is 'integrated'.";
sem IntegrationResult.reason = "Why a human is needed. Only when status is 'needs_human'.";
sem IntegrationResult.question_title = "Short headline for the developer, e.g. 'Conflict in login()'. Only when status is 'needs_human'.";
sem IntegrationResult.question_reason = "One plain-English sentence naming what their change collides with and what the other change was trying to do. This is the whole basis for their decision.";


"""Reject anything that could escape the project: absolute paths, traversal
segments, NUL bytes, backslashes. The JS original tested for the two-character
sequences \\0 and \\\\ rather than a NUL byte and a backslash -- a real bug
that shipped, fixed here."""
def safe_path(value: str) -> bool {
    if not value or "\0" in value or "\\" in value or value.startswith("/") {
        return False;
    }
    for part in value.split("/") {
        if not part or part == "." or part == ".." {
            return False;
        }
    }
    return True;
}


glob _ws: Workspace = Workspace(files={}, base={});


def list_files -> list[str] {
    _ws.activity.append("inspected project files");
    return sorted(_ws.files.keys());
}
sem list_files = "List every path in the current project.";


def read_file(path: str) -> str {
    if not safe_path(path) {
        return "";
    }
    _ws.activity.append(f"read {path}");
    return _ws.files.get(path, "");
}
sem read_file = "Read a file as it exists in the CURRENT project.";
sem read_file.path = "Project-relative file path.";


def read_base_file(path: str) -> str {
    if not safe_path(path) {
        return "";
    }
    _ws.activity.append(f"read original {path}");
    return _ws.base.get(path, "");
}
sem read_base_file = "Read the file as it existed when this feature began, before main moved.";
sem read_base_file.path = "Project-relative file path.";


def write_file(path: str, content: str) -> str {
    if not safe_path(path) {
        return "rejected: unsafe path";
    }
    _ws.files[path] = content;
    _ws.activity.append(f"wrote {path}");
    return "written";
}
sem write_file = "Write the integrated implementation to a file in the CURRENT project.";
sem write_file.path = "Project-relative file path.";
sem write_file.content = "The complete new contents of the file.";


def delete_file(path: str) -> str {
    if not safe_path(path) {
        return "rejected: unsafe path";
    }
    if path in _ws.files {
        del _ws.files[path];
    }
    _ws.activity.append(f"deleted {path}");
    return "deleted";
}
sem delete_file = "Delete a file from the CURRENT project when the feature requires its removal.";
sem delete_file.path = "Project-relative file path.";


"""The agent proper. Everything the JS version spent 130 lines dispatching by
hand -- tool schemas, the turn loop, argument parsing, history bookkeeping --
is the `tools=[...]` list and byLLM's ReAct driver."""
def integrate(
    intent: str,
    collisions: str,
    landed_decisions: str,
    can_ask: bool
) -> IntegrationResult by agent_llm(
    tools=[list_files, read_file, read_base_file, write_file, delete_file],
    max_react_iterations=20,
    temperature=0.1
);
sem integrate = """You are Synqit, a feature integrator. Make the feature true in the CURRENT
project, not the old one. Inspect files with the tools and edit every supporting file required.
Never leave merge-conflict markers in a file.

A successful completion is a code change, not a prose answer. If the feature is not already
present in CURRENT you MUST call write_file or delete_file to implement it before returning
status 'integrated'. Never claim files were changed unless you actually called those tools.

Undoing another developer's deliberate decision without asking is the one thing you must never
do. If something this feature depends on is absent from CURRENT, do not assume it was an
oversight and restore it -- check the landed decisions first. Reversing one of them is a
product call that belongs to a human, so return status 'needs_human' with a question instead.""";
sem integrate.intent = "What the developer says this feature is meant to do.";
sem integrate.collisions = "Files that moved on main since the developer's base -- the real collisions.";
sem integrate.landed_decisions = "Decisions already made on main since their base. Each one is something another developer deliberately chose.";
sem integrate.can_ask = "True when the developer is reachable and can answer a question. When false, asking still ends the push rather than guessing for them.";


def describe_collisions(conflicts: list[FileConflict]) -> str {
    if not conflicts {
        return "none";
    }
    return "\n".join([f"- {describe_conflict(c.path, c.kind)}" for c in conflicts]);
}


def describe_landed(history: list[RecentCommit]) -> str {
    if not history {
        return "none";
    }
    return "\n".join([f"- {c.author}: {c.message}" for c in history]);
}


obj IntegrationRun {
    has status: str;
    has summary: str;
    has reason: str;
    has question_title: str;
    has question_reason: str;
    has snapshot: dict[str, str];
    has activity: list[str];
}


"""Run one integration against a real workspace. Returns the agent's verdict
plus the files it produced, so the caller can publish them or hand the
question to a human."""
def run_integration(
    intent: str,
    base_snapshot: dict[str, str],
    current_snapshot: dict[str, str],
    conflicts: list[FileConflict],
    history: list[RecentCommit],
    can_ask: bool = True
) -> IntegrationRun {
    _ws.files = dict(current_snapshot);
    _ws.base = dict(base_snapshot);
    _ws.activity = [];
    verdict = integrate(
        intent,
        describe_collisions(conflicts),
        describe_landed(history),
        can_ask
    );
    return IntegrationRun(
        status=str(verdict.status),
        summary=str(verdict.summary),
        reason=str(verdict.reason),
        question_title=str(verdict.question_title),
        question_reason=str(verdict.question_reason),
        snapshot=dict(_ws.files),
        activity=list(_ws.activity)
    );
}
