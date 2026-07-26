"""
Port of server/src/conflict.js -- the first branch in the push flow. A
developer's change only conflicts if GitHub main moved the same file out
from under them since they took their base snapshot. Kept as its own pure
module (no graph, no I/O) so it is trivially testable and reusable from
any walker that needs the real answer instead of a scripted one.
"""

obj Change {
    has path: str;
    has content: str | None = None;
    has deleted: bool = False;
}

obj FileConflict {
    has path: str;
    has base: str | None;
    has current: str | None;
    has incoming: str | None;
    has deleted: bool;
    has kind: str;
}

def detect_conflicts(
    changes: list[Change],
    base_snapshot: dict[str, str],
    current_snapshot: dict[str, str]
) -> list[FileConflict] {
    conflicts: list[FileConflict] = [];
    for change in changes {
        base = base_snapshot.get(change.path);
        current = current_snapshot.get(change.path);
        if base == current {
            continue;  # main has not touched this file since their base
        }
        kind = (
            "both_added" if base is None
            else "deleted_on_main" if current is None
            else "both_modified"
        );
        conflicts.append(FileConflict(
            path=change.path,
            base=base,
            current=current,
            incoming=None if change.deleted else change.content,
            deleted=change.deleted,
            kind=kind
        ));
    }
    return conflicts;
}

# The clean branch: lay the developer's files straight onto current main.
def apply_changes(current_snapshot: dict[str, str], changes: list[Change]) -> dict[str, str] {
    snapshot: dict[str, str] = dict(current_snapshot);
    for change in changes {
        if change.deleted {
            if change.path in snapshot {
                del snapshot[change.path];
            }
        } else {
            incoming = change.content;
            if incoming is not None {
                snapshot[change.path] = incoming;
            }
        }
    }
    return snapshot;
}

def describe_conflict(path: str, kind: str) -> str {
    if kind == "both_added" {
        return f"{path} was added on main as well as in your change";
    } elif kind == "deleted_on_main" {
        return f"{path} was deleted on main while you changed it";
    } else {
        return f"{path} changed on main since your base";
    }
}
