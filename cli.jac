"""
Port of server/bin/synqit.js and server/src/commands.js -- the `synqit`
command line.

Run it with:  jac run cli.jac -- <command> [args]

The command set is the same one the JS CLI shipped, minus the pieces the
Jac runtime provides for free: there is no separate `serve` implementation
to maintain here, because `jac start main.jac` already serves every walker
in this project as a REST endpoint.
"""

import os;
import sys;
import from ui { bold, cyan, gray, green, yellow, ok, info, warn, fail, step }
import from settings {
    load_config, save_config, save_server_env, load_server_env,
    load_state, save_state, config_dir, env_file, DEFAULT_PUSH_BASE
}
import from gitio {
    is_git_root, current_branch, head_sha, git_user_name,
    working_tree_changes, fetch_branch, derive_owner_repo
}
import from workspace { read_workspace, read_tracked_workspace, hashes_for, changed_files }
import from github { verify_github_token, verify_repository_contents, read_head }
import from identity { register_developer, find_developer }


def cmd_help -> None {
    info(bold("synqit") + " — shared source control without branches, commits, or pulls");
    info("");
    info(bold("Usage"));
    info("  jac run cli.jac -- configure            Save this server's GitHub + OpenRouter keys");
    info("  jac run cli.jac -- doctor [owner/repo]  Verify credentials, and a repo's Contents permission");
    info("  jac run cli.jac -- init <project>       Connect this repo to Synqit");
    info("  jac run cli.jac -- status               Show this workspace's sync state");
    info("  jac run cli.jac -- push \"intent\"        Submit a feature");
    info("  jac run cli.jac -- help                 Show this help");
    info("");
    info(bold("Serving"));
    info("  jac start main.jac                      Every walker becomes a REST endpoint");
    info("");
    info(gray(f"Server data: {config_dir()}"));
}


"""Interactive credential setup. Keys are read with getpass so they never
land in shell history, verified immediately, and -- when a repo is given --
checked against the Contents permission Synqit actually needs."""
def cmd_configure(repo: str = "") -> int {
    import getpass;
    stdin_stream: any = sys.stdin;
    if not bool(stdin_stream.isatty()) {
        fail("`configure` must run in an interactive terminal so your keys are not exposed.");
        return 1;
    }
    info("Synqit server setup — keys are saved only on this machine.");
    github_token = getpass.getpass("GitHub token (fine-grained, Contents: read and write): ").strip();
    openrouter_key = getpass.getpass("OpenRouter API key: ").strip();
    model = input("Model [openrouter/free]: ").strip() or "openrouter/free";

    if not github_token or not openrouter_key {
        fail("Both a GitHub token and an OpenRouter API key are required. Nothing was saved.");
        return 1;
    }
    # OpenRouter keys are lowercase `sk-or-v1-`; normalize the one common
    # paste mistake rather than failing an otherwise valid key.
    if openrouter_key.startswith("Sk-or-v1-") {
        openrouter_key = "sk-or-v1-" + openrouter_key[len("Sk-or-v1-"):];
    }

    target = save_server_env(github_token, openrouter_key, model);
    os.environ["GITHUB_TOKEN"] = github_token;
    os.environ["OPENROUTER_API_KEY"] = openrouter_key;
    ok(f"saved credentials to {target}");

    try {
        login = verify_github_token();
        ok(f"GitHub verified as {login}");
    } except Exception as e {
        fail(f"Credentials were saved, but GitHub verification failed: {str(e)}");
        return 1;
    }

    # Identity is not access: a token with only Metadata passes the check
    # above and then fails on the first push. Exercise the real permission.
    if repo {
        try {
            head = verify_repository_contents(repo);
            ok(f"Contents verified on {repo} at {head[:7]}");
        } except Exception as e {
            warn(f"Saved, but the repository check failed: {str(e)}");
            info(gray("    Fix the token's permissions, then run `doctor owner/name`."));
        }
    } else {
        info(gray("    Run `doctor owner/name` before your first push to verify write access."));
    }
    info(gray("    Serve with: jac start main.jac"));
    return 0;
}


"""Verify what is configured, and optionally prove the token can actually
reach a repository's contents."""
def cmd_doctor(repo: str = "") -> int {
    _ = load_server_env();
    info("Synqit server diagnostics");
    has_github = bool(os.environ.get("GITHUB_TOKEN"));
    has_openrouter = bool(os.environ.get("OPENROUTER_API_KEY"));
    info(f"  {'✓' if has_github else '✗'} GitHub token {'configured' if has_github else 'missing'}");
    info(f"  {'✓' if has_openrouter else '✗'} OpenRouter API key {'configured' if has_openrouter else 'missing'}");
    info(gray(f"    Credentials file: {env_file()}"));
    if not has_github {
        info(gray("    Fix: run `configure`."));
        return 1;
    }
    try {
        login = verify_github_token();
        ok(f"GitHub verified as {login}");
    } except Exception as e {
        fail(f"Verification failed: {str(e)}");
        return 1;
    }
    if not repo {
        warn("Only identity was checked. Pass owner/name to confirm this token can read and write a repository.");
        return 0;
    }
    try {
        head = verify_repository_contents(repo);
        ok(f"Contents readable on {repo} at {head[:7]}");
        info(gray("    Write access is exercised on the first push."));
    } except Exception as e {
        fail(f"Repository check failed: {str(e)}");
        return 1;
    }
    return 0;
}


"""Connect this checkout to Synqit. Refuses anything but a clean tree on the
target branch that matches origin -- the same preconditions the JS CLI
enforced, for the same reason: the server's snapshot must match reality."""
def cmd_init(project: str = "", branch: str = "main") -> int {
    if load_state() is not None {
        fail("This folder is already connected. Run `status` instead.");
        return 1;
    }
    if not is_git_root() {
        fail("Run `init` from the root of a cloned GitHub repository.");
        return 1;
    }
    changes = working_tree_changes();
    if changes {
        fail(f"This workspace has {len(changes)} local change(s). Start from a fresh clone.");
        return 1;
    }
    if current_branch() != branch {
        fail(f"You are on {current_branch() or 'no branch'}, but Synqit requires {branch}.");
        return 1;
    }
    try {
        remote_sha = fetch_branch(branch);
    } except Exception {
        fail(f"Could not fetch origin/{branch}. Check your remote and connection.");
        return 1;
    }
    if head_sha() != remote_sha {
        fail(f"This clone is behind origin/{branch}. Run `git pull --ff-only`, then retry.");
        return 1;
    }

    (owner, repo) = derive_owner_repo();
    repository = f"{owner}/{repo}";
    project_id = project if project else repo;
    snapshot = read_tracked_workspace();
    if not snapshot {
        fail("Cannot initialize an empty project folder.");
        return 1;
    }

    step(f"Connecting {project_id} ({repository})");
    save_state({
        "project": project_id,
        "repository": repository,
        "branch": branch,
        "baseSha": remote_sha,
        "fileHashes": hashes_for(snapshot),
    });
    ok(f"initialized {project_id} at {remote_sha[:7]} ({len(snapshot)} files)");

    identity = register_developer(git_user_name() or "anon");
    ok(f"you are {identity.dev_id} on this server");
    return 0;
}


def cmd_status -> int {
    state = load_state();
    if state is None {
        fail("This folder is not connected. Run `init` first.");
        return 1;
    }
    snapshot = read_workspace();
    known: dict[str, str] = dict(state.get("fileHashes", {}) or {});
    pending = changed_files(snapshot, known);
    info(f"Synqit project: {state.get('project')}");
    info(f"  repository: {state.get('repository')}");
    info(f"  branch: {state.get('branch')}");
    info(f"  base: {str(state.get('baseSha', ''))[:7]}");
    info(f"  local changes ready to push: {len(pending)}");
    for change in pending[:10] {
        marker = "deleted" if change.deleted else "changed";
        info(gray(f"      {marker}: {change.path}"));
    }
    try {
        head = read_head(str(state.get("repository")), str(state.get("branch", "main")));
        current = head.head;
        suffix = " (up to date)" if current == state.get("baseSha") else " (newer version available)";
        info(f"  shared commit: {current[:7]}{suffix}");
    } except Exception as e {
        warn(f"could not reach GitHub: {str(e)}");
    }
    return 0;
}


"""Describe what would be pushed. The push itself runs through the SubmitPush
walker, which is exposed over HTTP by `jac start main.jac` -- this command
exists so a developer can see the change set before sending it."""
def cmd_push(intent: str) -> int {
    if not intent {
        fail("Describe the feature: push \"Add password validation\"");
        return 1;
    }
    state = load_state();
    if state is None {
        fail("This folder is not connected. Run `init` first.");
        return 1;
    }
    snapshot = read_workspace();
    known: dict[str, str] = dict(state.get("fileHashes", {}) or {});
    pending = changed_files(snapshot, known);
    if not pending {
        info(gray("Nothing to push — this workspace is already synced."));
        return 0;
    }
    info(bold(f"synqit: pushing feature → {state.get('project')}"));
    info(gray(f"    \"{intent}\""));
    info(gray(f"    {len(pending)} changed file(s) from {str(state.get('baseSha',''))[:7]}"));
    for change in pending {
        marker = "deleted" if change.deleted else "changed";
        info(gray(f"      {marker}: {change.path}"));
    }
    info("");
    info(cyan("    Submit with the SubmitPush walker:"));
    info(gray("      curl -X POST $HOST/walker/SubmitPush -H 'content-type: application/json' \\"));
    info(gray(f"        -d '{{\"project_id\": \"{state.get('project')}\", \"intent\": \"{intent}\", ...}}'"));
    return 0;
}


with entry:__main__ {
    argv = sys.argv[1:];
    command = argv[0] if argv else "help";
    rest = argv[1:];
    code = 0;

    if command in ["help", "-h", "--help"] {
        cmd_help();
    } elif command == "configure" {
        code = cmd_configure(rest[0] if rest else "");
    } elif command == "doctor" {
        code = cmd_doctor(rest[0] if rest else "");
    } elif command == "init" {
        code = cmd_init(rest[0] if rest else "");
    } elif command == "status" {
        code = cmd_status();
    } elif command == "push" {
        code = cmd_push(" ".join(rest).strip());
    } else {
        fail(f"Unknown command \"{command}\". Run `help`.");
        code = 1;
    }
    sys.exit(code);
}
