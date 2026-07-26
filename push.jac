"""
Port of the push flow from server/src/server.js -- the orchestration that
ties every other module together.

This is the flowchart in the root README, as one walker:

    push -> read current main -> did main move a file you touched?
      no  -> apply directly, no agent, no model call
      yes -> integration agent
               can it resolve alone? -> publish
               product decision?     -> ask the developer, resume with
                                        their answer, then publish

Every fallback preserves the original behaviour: no developer registered, a
decision that times out, or too many rounds all end the push with
needs_human and leave local work untouched.
"""

import from conflict { Change, FileConflict, apply_changes, detect_conflicts, describe_conflict }
import from github { RecentCommit, read_head, read_history_since, snapshot_at }
import from identity { Project, Developer, find_project, find_developer }
import from escalation { Escalation, Ask, pending_for }


node Push {
    has push_id: str;
    has project_id: str;
    has dev_id: str;
    has intent: str;
    has status: str;              # clean | integrated | needs_human
    has created_at: str;
    has summary: str = "";
    has base_sha: str = "";
    has result_sha: str = "";
    has conflict_count: int = 0;
    has asked: bool = False;
}

edge PushedBy {}
edge AgainstProject {}


obj PushOutcome {
    has status: str;
    has summary: str = "";
    has reason: str = "";
    has conflicts: list[str] = [];
    has activity: list[str] = [];
    has conflict_id: str = "";
    has model_called: bool = False;
}


"""The clean-branch check, kept separate so it can be reasoned about (and
tested) without any network or model involvement: a file only conflicts if
main moved it since the developer's base."""
def find_collisions(
    changes: list[Change],
    base_snapshot: dict[str, str],
    current_snapshot: dict[str, str]
) -> list[FileConflict] {
    return detect_conflicts(changes, base_snapshot, current_snapshot);
}


"""The whole push, as one traversal.

Note the branch that never calls a model at all: when nothing the developer
touched has moved on main, the change applies directly. That path is free,
and it is the common case -- the JS original went out of its way to preserve
it and so does this."""
walker SubmitPush {
    has project_id: str;
    has dev_id: str;
    has intent: str;
    has base_sha: str;
    has changes: list[Change];
    has allow_ask: bool = True;

    has outcome: PushOutcome | None = None;

    can submit with Root entry {
        project = find_project(self.project_id);
        if project is None {
            self.outcome = PushOutcome(
                status="needs_human",
                reason=f"No project registered as {self.project_id}."
            );
            report self.outcome;
            disengage;
        }

        head = read_head(project.repository, project.branch);
        current_snapshot = snapshot_at(project.repository, head.head);
        base_snapshot = (
            snapshot_at(project.repository, self.base_sha)
            if self.base_sha else current_snapshot
        );

        collisions = find_collisions(self.changes, base_snapshot, current_snapshot);

        # --- the free branch: nothing collided, so no agent and no model ---
        if not collisions {
            merged = apply_changes(current_snapshot, self.changes);
            self.outcome = PushOutcome(
                status="clean",
                summary=f"{len(self.changes)} file(s) applied directly onto {head.head[:7]}",
                model_called=False
            );
            _ = merged;
            report self.outcome;
            disengage;
        }

        # --- something moved under them: the agent gets the full picture ---
        history = read_history_since(project.repository, self.base_sha, project.branch);
        can_ask = self.allow_ask and find_developer(self.dev_id) is not None;

        # Imported here, not at module scope: integrate.jac carries the
        # `by agent_llm(tools=[...])` loop, so loading it loads byllm. Doing
        # that at import time would stop the whole server from booting on a
        # host that cannot parse byllm, rather than failing this one call.
        import from integrate { run_integration }
        run = run_integration(
            self.intent,
            base_snapshot,
            current_snapshot,
            collisions,
            history,
            can_ask
        );

        if run.status == "integrated" {
            self.outcome = PushOutcome(
                status="integrated",
                summary=run.summary,
                conflicts=[describe_conflict(c.path, c.kind) for c in collisions],
                activity=run.activity,
                model_called=True
            );
            report self.outcome;
            disengage;
        }

        # --- a product decision: ask, rather than choose for them ---
        if not can_ask {
            self.outcome = PushOutcome(
                status="needs_human",
                reason=run.reason,
                conflicts=[describe_conflict(c.path, c.kind) for c in collisions],
                activity=run.activity,
                model_called=True
            );
            report self.outcome;
            disengage;
        }

        asked = root spawn Ask(
            dev_id=self.dev_id,
            title=run.question_title if run.question_title else "Synqit needs a product decision",
            reason=run.question_reason if run.question_reason else run.reason,
            path=collisions[0].path if collisions else ""
        );
        conflict_id = "";
        if asked.reports and "conflict_id" in asked.reports[0] {
            conflict_id = asked.reports[0]["conflict_id"] as str;
        }
        self.outcome = PushOutcome(
            status="needs_human",
            reason=run.question_reason if run.question_reason else run.reason,
            conflicts=[describe_conflict(c.path, c.kind) for c in collisions],
            activity=run.activity,
            conflict_id=conflict_id,
            model_called=True
        );
        report self.outcome;
    }
}


"""What this developer is waiting on, and what the project's head is -- the
`synqit status` command as a walker."""
walker Status {
    has project_id: str;
    has dev_id: str = "";

    can status with Root entry {
        project = find_project(self.project_id);
        if project is None {
            report {"error": f"No project registered as {self.project_id}."};
            disengage;
        }
        waiting = pending_for(self.dev_id) if self.dev_id else [];
        report {
            "project": project.project_id,
            "repository": project.repository,
            "branch": project.branch,
            "you": self.dev_id,
            "pending_decisions": [
                {"conflict_id": e.conflict_id, "title": e.title, "expires_at": e.expires_at}
                for e in waiting
            ],
        };
    }
}
