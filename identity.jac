"""
Port of server/src/store.js -- developers and projects.

The JS original hand-rolled a JSON store: read a file, parse it, mutate the
dict, write it back, and keep the directory layout in sync. None of that
survives the port, because in Jac the graph IS the database. A developer is
a node hanging off root; finding one by token is a filtered traversal, not
a full-table scan of a parsed file. Persistence is automatic.
"""

import secrets;
import re;
import from datetime { datetime, timezone }


node Developer {
    has dev_id: str;
    has name: str;
    has token: str;
    has created_at: str;
}

node Project {
    has project_id: str;
    has repository: str;
    has created_at: str;
    has branch: str = "main";
    has head: str = "";
}

edge OwnedBy {}


def now_iso -> str {
    return datetime.now(timezone.utc).isoformat();
}


"""Same slug rules as the JS original: anything outside [A-Za-z0-9._-] becomes
a dash, leading/trailing dashes are trimmed, capped at 100 chars, and an empty
result falls back to "x" rather than producing a nameless record."""
def slug(value: str) -> str {
    cleaned: str = re.sub(r"[^A-Za-z0-9._-]+", "-", str(value));
    trimmed: str = re.sub(r"^-+|-+$", "", cleaned)[:100];
    return trimmed if trimmed else "x";
}


def find_developer(wanted: str) -> Developer | None {
    found = [root -->[?:Developer, dev_id == wanted]];
    return found[0] if found else None;
}


"""Token lookup is the security-relevant one: a notch presents a bearer token
and the server must decide whose escalations it may ever see."""
def developer_for_token(token: str) -> Developer | None {
    if not token {
        return None;
    }
    for dev in [root -->[?:Developer]] {
        if secrets.compare_digest(dev.token, token) {
            return dev;
        }
    }
    return None;
}


"""Registers a developer. Names are advisory; the id is what routing uses, so
a repeated name gets a numeric suffix rather than colliding onto one record."""
def register_developer(name: str) -> Developer {
    lowered: str = slug(name if name else "anon").lower();
    safe: str = re.sub(r"-+", "_", lowered);
    base: str = f"dev_{safe}"[:40];
    taken = [d.dev_id for d in [root -->[?:Developer]]];
    dev_id = base;
    suffix = 2;
    while dev_id in taken {
        dev_id = f"{base}_{suffix}";
        suffix += 1;
    }
    made = Developer(
        dev_id=dev_id,
        name=name if name else "anon",
        token=secrets.token_urlsafe(24),
        created_at=now_iso()
    );
    root ++> made;
    return made;
}


def find_project(project_id: str) -> Project | None {
    wanted = slug(project_id);
    found = [root -->[?:Project, project_id == wanted]];
    return found[0] if found else None;
}


def create_project(project_id: str, repository: str, branch: str = "main") -> Project {
    wanted = slug(project_id);
    if find_project(wanted) is not None {
        raise ValueError(f"Project \"{wanted}\" already exists.");
    }
    made = Project(
        project_id=wanted,
        repository=repository,
        branch=branch,
        created_at=now_iso()
    );
    root ++> made;
    return made;
}


"""Register a developer and hand back the credentials the notch needs. This is
the whole of the JS `POST /api/developers` handler."""
walker RegisterDeveloper {
    has name: str = "anon";

    can register with Root entry {
        dev = register_developer(self.name);
        report {"dev_id": dev.dev_id, "notch_token": dev.token, "name": dev.name};
    }
}


walker ListDevelopers {
    can list with Root entry {
        report [
            {"dev_id": d.dev_id, "name": d.name, "created_at": d.created_at}
            for d in [root -->[?:Developer]]
        ];
    }
}


walker CreateProject {
    has project_id: str;
    has repository: str;
    has branch: str = "main";

    can create with Root entry {
        made = create_project(self.project_id, self.repository, self.branch);
        report {
            "project": made.project_id,
            "repository": made.repository,
            "branch": made.branch,
        };
    }
}
