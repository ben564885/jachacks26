"""
Port of server/src/git.js -- real git, driven from Jac via subprocess.

Carries over the security fix the JS version earned the hard way: the CLI
loads the *server's* credentials into the environment and child processes
inherit them, so GitHub's credential helper would prefer the server's
GITHUB_TOKEN over the developer's own keychain and service their fetches as
the server. Every git call here strips those two variables, so developers
always authenticate as themselves.
"""

import os;
import subprocess;
import from pathlib { Path }


glob US: str = "\x1f";  # unit separator, for parsing --format output


obj CommitInfo {
    has sha: str;
    has short_sha: str;
    has subject: str;
    has author_name: str;
    has author_email: str;
    has date: str;
    has body: str = "";
}

obj WorkingChange {
    has status: str;
    has path: str;
}


"""Run git with the server's tokens stripped from the environment."""
def git(args: list[str], cwd: str = "") -> str {
    env = dict(os.environ);
    env.pop("GITHUB_TOKEN", None);
    env.pop("GH_TOKEN", None);
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd if cwd else None,
        env=env,
        capture_output=True,
        text=True,
        check=True
    );
    return result.stdout;
}


def git_ok(args: list[str], cwd: str = "") -> bool {
    try {
        _ = git(args, cwd);
        return True;
    } except Exception {
        return False;
    }
}


def is_git_repo(cwd: str = "") -> bool {
    return git_ok(["rev-parse", "--is-inside-work-tree"], cwd);
}


def is_git_root(cwd: str = "") -> bool {
    try {
        top = git(["rev-parse", "--show-toplevel"], cwd).strip();
    } except Exception {
        return False;
    }
    here = Path(cwd) if cwd else Path.cwd();
    return Path(top).resolve() == here.resolve();
}


def current_branch(cwd: str = "") -> str {
    return git(["branch", "--show-current"], cwd).strip();
}


def head_sha(cwd: str = "") -> str {
    return git(["rev-parse", "HEAD"], cwd).strip();
}


"""The human-readable half of a developer id. Advisory only -- routing uses
the id the server hands back, never this."""
def git_user_name(cwd: str = "") -> str | None {
    try {
        name = git(["config", "user.name"], cwd).strip();
    } except Exception {
        return None;
    }
    return name if name else None;
}


def working_tree_changes(cwd: str = "") -> list[WorkingChange] {
    out = git(["status", "--porcelain=v1", "--untracked-files=all"], cwd);
    changes: list[WorkingChange] = [];
    for line in out.splitlines() {
        if line {
            changes.append(WorkingChange(status=line[:2], path=line[3:]));
        }
    }
    return changes;
}


def fetch_branch(branch: str = "main", cwd: str = "") -> str {
    _ = git(["fetch", "--quiet", "origin", branch], cwd);
    return git(["rev-parse", f"origin/{branch}"], cwd).strip();
}


def sync_to_commit(branch: str = "main", cwd: str = "") -> str {
    fetched = fetch_branch(branch, cwd);
    _ = git(["reset", "--hard", fetched], cwd);
    return fetched;
}


"""owner/repo from the origin remote when it looks GitHub-shaped, otherwise
git user.name plus the repo's directory name."""
def derive_owner_repo(cwd: str = "") -> tuple {
    owner: str | None = None;
    repo: str | None = None;
    try {
        url = git(["config", "--get", "remote.origin.url"], cwd).strip();
        trimmed = url[:-4] if url.endswith(".git") else url;
        trimmed = trimmed.rstrip("/");
        separator = max(trimmed.rfind(":"), trimmed.rfind("/"));
        tail = trimmed[separator + 1:] if separator >= 0 else trimmed;
        head_part = trimmed[:separator] if separator >= 0 else "";
        owner_sep = max(head_part.rfind(":"), head_part.rfind("/"));
        if tail {
            repo = tail;
            owner = head_part[owner_sep + 1:] if owner_sep >= 0 else (head_part or None);
        }
    } except Exception {
        owner = None;
    }
    if not owner {
        owner = git_user_name(cwd) or "anon";
    }
    if not repo {
        try {
            repo = Path(git(["rev-parse", "--show-toplevel"], cwd).strip()).name;
        } except Exception {
            repo = "repo";
        }
    }
    return (owner, repo);
}


"""Read a single commit into structured metadata."""
def read_commit(ref: str = "HEAD", cwd: str = "") -> CommitInfo {
    sha = git(["rev-parse", ref], cwd).strip();
    fmt = US.join(["%H", "%h", "%an", "%ae", "%aI", "%s"]);
    raw = git(["show", "-s", f"--format={fmt}", sha], cwd).strip();
    parts = raw.split(US);
    while len(parts) < 6 {
        parts.append("");
    }
    body = git(["show", "-s", "--format=%b", sha], cwd).rstrip();
    return CommitInfo(
        sha=parts[0],
        short_sha=parts[1],
        author_name=parts[2],
        author_email=parts[3],
        date=parts[4],
        subject=parts[5],
        body=body
    );
}
