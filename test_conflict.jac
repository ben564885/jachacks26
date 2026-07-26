"""
Mirrors server/test/conflict.test.mjs case-for-case, so the Jac port is
provably behavior-identical to the JS original it replaces, not just
similar-looking.
"""

import from conflict { Change, apply_changes, describe_conflict, detect_conflicts }

test "a file nobody else touched is not a conflict" {
    base = {"a.js": "one", "b.js": "two"};
    current = {"a.js": "one", "b.js": "two"};
    changes = [Change(path="a.js", content="one changed")];
    assert detect_conflicts(changes, base, current) == [];
}

test "a file main moved under them is a conflict" {
    base = {"a.js": "one"};
    current = {"a.js": "one, edited on main"};
    changes = [Change(path="a.js", content="one changed")];
    conflicts = detect_conflicts(changes, base, current);
    assert len(conflicts) == 1;
    assert conflicts[0].kind == "both_modified";
}

test "both sides adding the same new file is a conflict" {
    conflicts = detect_conflicts([Change(path="new.js", content="mine")], {}, {"new.js": "theirs"});
    assert conflicts[0].kind == "both_added";
}

test "editing a file main deleted is a conflict" {
    conflicts = detect_conflicts([Change(path="gone.js", content="mine")], {"gone.js": "was here"}, {});
    assert conflicts[0].kind == "deleted_on_main";
}

test "main moving an unrelated file is not a conflict" {
    base = {"a.js": "one", "b.js": "two"};
    current = {"a.js": "one", "b.js": "two, edited on main"};
    assert detect_conflicts([Change(path="a.js", content="changed")], base, current) == [];
}

test "a deletion of an untouched file is clean" {
    base = {"a.js": "one"};
    current = {"a.js": "one"};
    assert detect_conflicts([Change(path="a.js", deleted=True)], base, current) == [];
}

test "apply_changes lays changes onto current main" {
    current = {"a.js": "one", "b.js": "two"};
    next_snapshot = apply_changes(current, [
        Change(path="a.js", content="edited"),
        Change(path="b.js", deleted=True),
        Change(path="c.js", content="new"),
    ]);
    assert next_snapshot == {"a.js": "edited", "c.js": "new"};
    assert current == {"a.js": "one", "b.js": "two"};  # must not mutate the input
}

test "conflicts read as plain English" {
    assert "changed on main since your base" in describe_conflict("x.js", "both_modified");
    assert "added on main as well" in describe_conflict("x.js", "both_added");
    assert "deleted on main" in describe_conflict("x.js", "deleted_on_main");
}
