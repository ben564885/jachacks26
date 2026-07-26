"""
Port of server/src/workspace.js -- reading a developer's folder into a
snapshot, diffing it against what the server last saw, and writing the
canonical version back.

The path-safety check here is the one that matters: it is what stops a
malicious or confused snapshot from writing outside the project.
"""

import os;
import hashlib;
import subprocess;


glob IGNORED_DIRS: set[str] = {".git", ".synqit", "node_modules", ".jac", ".jacvenv", ".next"};
glob IGNORED_FILES: set[str] = {".env", ".DS_Store"};


obj FileChange {
    has path: str;
    has content: str = "";
    has deleted: bool = False;
}


"""Reject any path that could escape the project root. Absolute paths, NUL
bytes, backslashes, and `.`/`..` segments are all refused."""
def is_safe_workspace_path(value: str) -> bool {
    if not value {
        return False;
    }
    if "\0" in value or "\\" in value or value.startswith("/") {
        return False;
    }
    for part in value.split("/") {
        if not part or part == "." or part == ".." {
            return False;
        }
    }
    return True;
}


def content_hash(content: str) -> str {
    return hashlib.sha256(content.encode("utf8")).hexdigest();
}


def hashes_for(snapshot: dict[str, str]) -> dict[str, str] {
    return {path: content_hash(body) for (path, body) in snapshot.items()};
}


def _read_text(path: str) -> str | None {
    try {
        handle = open(path, "r", encoding="utf8");
    } except Exception {
        return None;
    }
    try {
        return handle.read();
    } except Exception {
        return None;  # binary or unreadable -- Synqit is text-only
    } finally {
        handle.close();
    }
}


"""Walk a directory into {path: content}, skipping build output and secrets.
Line endings are normalized so a CRLF checkout does not read as a full-file
change against an LF snapshot."""
def read_workspace(base: str = "") -> dict[str, str] {
    rootdir: str = base if base else os.getcwd();
    snapshot: dict[str, str] = {};
    for (dirpath, dirnames, filenames) in os.walk(rootdir) {
        dirnames[:] = [d for d in dirnames if d not in IGNORED_DIRS];
        for filename in filenames {
            if filename in IGNORED_FILES {
                continue;
            }
            full = os.path.join(dirpath, filename);
            body = _read_text(full);
            if body is None {
                continue;
            }
            rel = os.path.relpath(full, rootdir).replace("\\", "/");
            snapshot[rel] = body.replace("\r\n", "\n");
        }
    }
    return snapshot;
}


"""Only what git already tracks. Used at init so an untracked scratch file
does not become part of the shared project on day one."""
def read_tracked_workspace(base: str = "") -> dict[str, str] {
    rootdir: str = base if base else os.getcwd();
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=rootdir,
        capture_output=True,
        text=True,
        check=True
    );
    snapshot: dict[str, str] = {};
    for path in result.stdout.split("\0") {
        if not path {
            continue;
        }
        body = _read_text(os.path.join(rootdir, path));
        if body is not None {
            snapshot[path] = body.replace("\r\n", "\n");
        }
    }
    return snapshot;
}


"""What changed since the server last saw this workspace. Deletions are
carried explicitly so the server can distinguish "gone" from "never sent"."""
def changed_files(snapshot: dict[str, str], known_hashes: dict[str, str]) -> list[FileChange] {
    paths: set[str] = set(snapshot.keys()) | set(known_hashes.keys());
    changes: list[FileChange] = [];
    for path in sorted(paths) {
        if path not in snapshot {
            changes.append(FileChange(path=path, deleted=True));
            continue;
        }
        if content_hash(snapshot[path]) != known_hashes.get(path, "") {
            changes.append(FileChange(path=path, content=snapshot[path]));
        }
    }
    return changes;
}


"""Replace only server-managed files. Local files Synqit never tracked are
left alone -- the prior hashes say what it is allowed to remove."""
def write_canonical_snapshot(
    snapshot: dict[str, str],
    prior_hashes: dict[str, str],
    base: str = ""
) -> int {
    rootdir: str = base if base else os.getcwd();
    written = 0;
    for path in prior_hashes.keys() {
        if path in snapshot {
            continue;
        }
        if not is_safe_workspace_path(path) {
            raise ValueError(f"Unsafe Synqit path: {path}");
        }
        target = os.path.join(rootdir, path);
        if os.path.exists(target) {
            os.remove(target);
        }
    }
    for (path, body) in snapshot.items() {
        if not is_safe_workspace_path(path) {
            raise ValueError(f"Unsafe Synqit path: {path}");
        }
        target = os.path.join(rootdir, path);
        os.makedirs(os.path.dirname(target), exist_ok=True);
        handle = open(target, "w", encoding="utf8");
        _ = handle.write(body);
        handle.close();
        written += 1;
    }
    return written;
}
