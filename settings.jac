"""
Port of server/src/config.js and the per-workspace state half of
workspace.js -- where Synqit keeps its own files.

Server credentials live under ~/.config/synqit so the tool works from any
directory; per-workspace state lives in .synqit/state.json next to the code
it describes. The .env file is written 0600, because it holds a GitHub token
with write access to a real repository.
"""

import os;
import json;


glob CONFIG_DIR_NAME: str = "synqit";
glob STATE_DIR: str = ".synqit";
glob STATE_FILE: str = "state.json";
glob DEFAULT_PUSH_BASE: str = "http://localhost:8899";


def config_dir -> str {
    override = os.environ.get("SYNQIT_HOME");
    if override {
        return override;
    }
    return os.path.join(os.path.expanduser("~"), ".config", CONFIG_DIR_NAME);
}

def config_file -> str { return os.path.join(config_dir(), "config.json"); }
def env_file -> str { return os.path.join(config_dir(), ".env"); }
def projects_dir -> str { return os.path.join(config_dir(), "projects"); }


def _read_json(path: str) -> dict {
    if not os.path.exists(path) {
        return {};
    }
    handle = open(path, "r", encoding="utf8");
    try {
        loaded = json.load(handle);
    } except Exception {
        return {};
    } finally {
        handle.close();
    }
    return loaded if isinstance(loaded, dict) else {};
}


def _write_json(path: str, payload: dict) -> None {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    handle = open(path, "w", encoding="utf8");
    _ = handle.write(json.dumps(payload, indent=2) + "\n");
    handle.close();
}


def load_config -> dict {
    return _read_json(config_file());
}


def save_config(cfg: dict) -> None {
    _write_json(config_file(), cfg);
}


"""Server credentials. Written 0600 -- this file holds a GitHub token that can
write to a real repository, so it must not be world-readable."""
def save_server_env(github_token: str, openrouter_key: str, model: str = "openrouter/free") -> str {
    target = env_file();
    os.makedirs(os.path.dirname(target), exist_ok=True);
    lines = [
        f"GITHUB_TOKEN={github_token}",
        f"OPENROUTER_API_KEY={openrouter_key}",
        f"SYNQIT_MODEL={model}",
        "",
    ];
    handle = open(target, "w", encoding="utf8");
    _ = handle.write("\n".join(lines));
    handle.close();
    try {
        os.chmod(target, 0o600);
    } except Exception {
        # Windows has no POSIX modes; the write itself still succeeded.
        _ = target;
    }
    return target;
}


"""Load KEY=VALUE pairs from the server env file without overriding anything
already exported in the shell -- the same precedence the JS CLI used."""
def load_server_env -> dict[str, str] {
    target = env_file();
    values: dict[str, str] = {};
    if not os.path.exists(target) {
        return values;
    }
    handle = open(target, "r", encoding="utf8");
    body = handle.read();
    handle.close();
    for line in body.splitlines() {
        trimmed = line.strip();
        if not trimmed or trimmed.startswith("#") or "=" not in trimmed {
            continue;
        }
        (key, _, value) = trimmed.partition("=");
        name = key.strip();
        values[name] = value.strip();
        if name not in os.environ {
            os.environ[name] = value.strip();
        }
    }
    return values;
}


def state_path(base: str = "") -> str {
    rootdir: str = base if base else os.getcwd();
    return os.path.join(rootdir, STATE_DIR, STATE_FILE);
}


def load_state(base: str = "") -> dict | None {
    path = state_path(base);
    if not os.path.exists(path) {
        return None;
    }
    return _read_json(path);
}


def save_state(state: dict, base: str = "") -> None {
    _ignore_synqit_state(base);
    _write_json(state_path(base), state);
}


"""Keep per-workspace Synqit metadata out of normal Git workflows without
touching the project's shared .gitignore."""
def _ignore_synqit_state(base: str = "") -> None {
    rootdir: str = base if base else os.getcwd();
    exclude = os.path.join(rootdir, ".git", "info", "exclude");
    if not os.path.exists(exclude) {
        return;
    }
    handle = open(exclude, "r", encoding="utf8");
    current = handle.read();
    handle.close();
    if f"{STATE_DIR}/" in current.splitlines() {
        return;
    }
    separator = "" if (not current or current.endswith("\n")) else "\n";
    appender = open(exclude, "a", encoding="utf8");
    _ = appender.write(f"{separator}{STATE_DIR}/\n");
    appender.close();
}
