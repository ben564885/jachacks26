"""
Covers the path-safety gate and the change-detection logic ported from
server/src/workspace.js. The safety cases are the ones that matter: this
function is the only thing standing between a hostile snapshot and the
filesystem outside the project.
"""

import from workspace {
    FileChange, is_safe_workspace_path, content_hash, hashes_for, changed_files
}
import from integrate { safe_path }


test "ordinary project-relative paths are allowed" {
    assert is_safe_workspace_path("src/index.js");
    assert is_safe_workspace_path("a.txt");
    assert is_safe_workspace_path("deeply/nested/file.ts");
}

test "absolute paths are refused" {
    assert not is_safe_workspace_path("/etc/passwd");
}

test "traversal segments are refused" {
    assert not is_safe_workspace_path("../outside.js");
    assert not is_safe_workspace_path("src/../../escape.js");
    assert not is_safe_workspace_path("./sneaky.js");
}

test "NUL bytes and backslashes are refused" {
    assert not is_safe_workspace_path("bad\0name.js");
    assert not is_safe_workspace_path("windows\\path.js");
}

test "empty paths are refused" {
    assert not is_safe_workspace_path("");
}

"""The JS original tested for the two-character sequences \\0 and \\\\ rather
than a NUL byte and a backslash, so a real NUL never actually tripped it.
The Jac port checks the characters themselves -- assert that directly."""
test "the agent's path gate refuses a real NUL byte, not the literal text" {
    assert not safe_path("bad\0name.js");
    assert not safe_path("windows\\path.js");
    assert safe_path("src/fine.js");
}

test "identical content hashes identically" {
    assert content_hash("hello") == content_hash("hello");
    assert content_hash("hello") != content_hash("hello ");
}

test "an untouched file is not a change" {
    snapshot = {"a.js": "one"};
    known = hashes_for(snapshot);
    assert changed_files(snapshot, known) == [];
}

test "an edited file is reported with its new content" {
    known = hashes_for({"a.js": "one"});
    changes = changed_files({"a.js": "one edited"}, known);
    assert len(changes) == 1;
    assert changes[0].path == "a.js";
    assert changes[0].content == "one edited";
    assert not changes[0].deleted;
}

test "a removed file is reported as a deletion" {
    known = hashes_for({"a.js": "one", "b.js": "two"});
    changes = changed_files({"a.js": "one"}, known);
    assert len(changes) == 1;
    assert changes[0].path == "b.js";
    assert changes[0].deleted;
}

test "a brand new file is reported as a change" {
    changes = changed_files({"new.js": "fresh"}, {});
    assert len(changes) == 1;
    assert changes[0].path == "new.js";
    assert changes[0].content == "fresh";
}

test "changes come back in stable path order" {
    changes = changed_files({"c.js": "3", "a.js": "1", "b.js": "2"}, {});
    assert [c.path for c in changes] == ["a.js", "b.js", "c.js"];
}
