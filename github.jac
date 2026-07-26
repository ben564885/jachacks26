"""
Port of server/src/github.js -- the real GitHub Contents API, in Jac.

This is the module that answers "is this actually a working system or a
scripted demo": reading a repository's head, materializing a commit's file
tree, and listing what landed on main since a developer's base are all real
network calls. Jac compiles to Python bytecode, so `requests` is imported
directly -- no wrapper, no FFI, no separate service.
"""

import os;
import base64;
import requests;

glob API: str = "https://api.github.com";


obj Repository {
    has owner: str;
    has repo: str;
}

obj RepoHead {
    has repository: str;
    has branch: str;
    has head: str;
}

obj RecentCommit {
    has sha: str;
    has author: str;
    has message: str;
}


def parse_repository(value: str) -> Repository {
    parts = str(value or "").split("/");
    if len(parts) != 2 or not parts[0] or not parts[1] or " " in value {
        raise ValueError("GitHub repository must look like owner/repository.");
    }
    return Repository(owner=parts[0], repo=parts[1]);
}


def _token -> str {
    token = os.environ.get("GITHUB_TOKEN");
    if not token {
        raise ValueError("GITHUB_TOKEN is required for connected repositories.");
    }
    return token;
}


def _headers -> dict[str, str] {
    return {
        "accept": "application/vnd.github+json",
        "authorization": f"Bearer {_token()}",
        "x-github-api-version": "2022-11-28",
    };
}


"""One GET against the GitHub API, with the same error translation the JS
server does -- a 401/403 gets a message that names the actual fix rather
than echoing a status code."""
def _get(path: str) -> any {
    response = requests.get(f"{API}{path}", headers=_headers(), timeout=30);
    if response.status_code == 401 {
        raise ValueError("GitHub rejected this token.");
    }
    if response.status_code == 403 {
        raise ValueError(
            "GitHub denied access. Ensure the token has Contents: read and write on this repository."
        );
    }
    if not response.ok {
        raise ValueError(f"GitHub responded {response.status_code}.");
    }
    return response.json();
}


def verify_github_token -> str {
    data = _get("/user");
    return data["login"] as str;
}


"""`GET /user` succeeds for any token, so verifying it proves only that the
token exists. This exercises the Contents permission Synqit actually needs,
against a real repository -- the bug that shipped a Metadata-only token to
production in the JS original."""
def verify_repository_contents(repository: str, branch: str = "main") -> str {
    repo = parse_repository(repository);
    response = requests.get(
        f"{API}/repos/{repo.owner}/{repo.repo}/git/ref/heads/{branch}",
        headers=_headers(),
        timeout=30
    );
    if response.ok {
        return response.json()["object"]["sha"] as str;
    }
    if response.status_code == 403 {
        raise ValueError(
            f"the token reached {repository} but has no Contents permission. "
            + "Grant \"Contents: Read and write\" on the token."
        );
    }
    if response.status_code == 404 {
        raise ValueError(
            f"the token cannot see {repository} on branch {branch}. "
            + "Check the repository is in the token's scope and the branch exists."
        );
    }
    raise ValueError(f"GitHub responded {response.status_code}.");
}


def read_head(repository: str, branch: str = "main") -> RepoHead {
    repo = parse_repository(repository);
    data = _get(f"/repos/{repo.owner}/{repo.repo}/git/ref/heads/{branch}");
    return RepoHead(
        repository=f"{repo.owner}/{repo.repo}",
        branch=branch,
        head=data["object"]["sha"] as str
    );
}


"""Materialize every text blob at a commit into {path: content}. This is the
snapshot both sides of a conflict are compared against."""
def snapshot_at(repository: str, commit_sha: str) -> dict[str, str] {
    repo = parse_repository(repository);
    commit = _get(f"/repos/{repo.owner}/{repo.repo}/git/commits/{commit_sha}");
    tree = _get(f"/repos/{repo.owner}/{repo.repo}/git/trees/{commit['tree']['sha']}?recursive=1");
    snapshot: dict[str, str] = {};
    for entry in tree["tree"] {
        if entry["type"] != "blob" {
            continue;
        }
        blob = _get(f"/repos/{repo.owner}/{repo.repo}/git/blobs/{entry['sha']}");
        raw = str(blob["content"]).replace("\n", "");
        try {
            snapshot[entry["path"] as str] = base64.b64decode(raw).decode("utf8");
        } except UnicodeDecodeError {
            continue;  # binary file -- Synqit is text-only, same as the JS original
        }
    }
    return snapshot;
}


"""Commits landed on the branch since the developer took their base. This is
what lets an escalation name the *other* side of a collision -- who changed
it and what they were doing -- instead of only describing the pusher's own
change back at them. Attribution is a nicety; never fail a push over it."""
def read_history_since(repository: str, since_sha: str, branch: str = "main", limit: int = 20) -> list[RecentCommit] {
    repo = parse_repository(repository);
    recent: list[RecentCommit] = [];
    try {
        commits = _get(
            f"/repos/{repo.owner}/{repo.repo}/commits?sha={branch}&per_page={min(limit, 100)}"
        );
    } except Exception {
        return recent;
    }
    for entry in commits {
        if entry["sha"] == since_sha {
            break;
        }
        author = "someone";
        if entry.get("author") {
            author = entry["author"]["login"] as str;
        } elif entry.get("commit", {}).get("author") {
            author = entry["commit"]["author"]["name"] as str;
        }
        recent.append(RecentCommit(
            sha=entry["sha"] as str,
            author=author,
            message=str(entry.get("commit", {}).get("message", "")).split("\n")[0]
        ));
    }
    return recent;
}


"""Which paths a given commit touched, so an escalation can point at the
specific commit that collided rather than the whole recent history."""
def read_commit_paths(repository: str, sha: str) -> list[str] {
    repo = parse_repository(repository);
    try {
        commit = _get(f"/repos/{repo.owner}/{repo.repo}/commits/{sha}");
    } except Exception {
        return [];
    }
    return [f["filename"] as str for f in commit.get("files", [])];
}
