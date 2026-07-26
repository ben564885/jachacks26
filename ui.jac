"""
Port of server/src/ui.js -- terminal output. No dependencies, and colour is
suppressed when stdout is not a TTY or NO_COLOR is set, so piping Synqit's
output into a file does not fill it with escape sequences.
"""

import os;
import sys;


def use_color -> bool {
    stream: any = sys.stdout;
    try {
        tty = bool(stream.isatty());
    } except Exception {
        return False;
    }
    return tty and os.environ.get("NO_COLOR") is None;
}


def paint(code: str, text: str) -> str {
    if not use_color() {
        return str(text);
    }
    return f"\x1b[{code}m{text}\x1b[0m";
}


def bold(text: str) -> str { return paint("1", text); }
def dim(text: str) -> str { return paint("2", text); }
def green(text: str) -> str { return paint("32", text); }
def red(text: str) -> str { return paint("31", text); }
def yellow(text: str) -> str { return paint("33", text); }
def cyan(text: str) -> str { return paint("36", text); }
def gray(text: str) -> str { return paint("90", text); }


def step(message: str) -> None {
    print(gray("  → ") + message);
}

def ok(message: str) -> None {
    print(green("  ✓ ") + message);
}

def info(message: str) -> None {
    print(message);
}

def warn(message: str) -> None {
    print(yellow("  ! ") + message);
}

def fail(message: str) -> None {
    stream: any = sys.stderr;
    _ = stream.write(red("  ✗ ") + message + "\n");
}
