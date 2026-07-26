"""
Covers the identity model that replaced server/src/store.js: slug rules,
id collision handling, and the token lookup that decides whose escalations
a connected notch may ever see.
"""

import from identity {
    Developer, Project, slug, register_developer, find_developer,
    developer_for_token, create_project, find_project, RegisterDeveloper
}


test "slug strips unsafe characters and trims dashes" {
    assert slug("Ben Nisevich") == "Ben-Nisevich";
    assert slug("--weird--") == "weird";
    assert slug("a/b\\c") == "a-b-c";
}

test "slug never returns an empty identifier" {
    assert slug("") == "x";
    assert slug("///") == "x";
}

test "slug caps length at 100 characters" {
    assert len(slug("a" * 400)) == 100;
}

test "registering yields a dev id, a token, and a findable record" {
    dev = register_developer("Ada");
    assert dev.dev_id == "dev_ada";
    assert len(dev.token) > 20;
    assert find_developer("dev_ada") is not None;
}

test "the same name twice gets distinct ids, never a collision" {
    first = register_developer("Grace");
    second = register_developer("Grace");
    assert first.dev_id != second.dev_id;
    assert second.dev_id == "dev_grace_2";
}

test "a token resolves to exactly its own developer" {
    alice = register_developer("alice-token-test");
    bob = register_developer("bob-token-test");
    resolved_alice = developer_for_token(alice.token);
    resolved_bob = developer_for_token(bob.token);
    assert resolved_alice is not None and resolved_alice.dev_id == alice.dev_id;
    assert resolved_bob is not None and resolved_bob.dev_id == bob.dev_id;
}

test "an unknown or empty token resolves to nobody" {
    assert developer_for_token("not-a-real-token") is None;
    assert developer_for_token("") is None;
}

test "a project is created once and found by slug" {
    made = create_project("Pricing Service", "acme/pricing");
    assert made.project_id == "Pricing-Service";
    found = find_project("Pricing Service");
    assert found is not None and found.repository == "acme/pricing";
}

test "creating the same project twice is refused" {
    _ = create_project("dup-project", "acme/dup");
    failed = False;
    try {
        _ = create_project("dup-project", "acme/dup");
    } except ValueError {
        failed = True;
    }
    assert failed;
}

test "the register walker reports credentials the notch can use" {
    res = root spawn RegisterDeveloper(name="walker-test");
    payload = res.reports[0];
    assert payload["dev_id"] == "dev_walker_test";
    assert payload["notch_token"];
}
