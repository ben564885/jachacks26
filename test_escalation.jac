"""
Mirrors the security-critical half of server/test/escalation.test.mjs: a
developer may only ever see and resolve their own conflicts, an unanswered
question expires rather than hanging forever, and a resolved question cannot
be resolved twice.

The JS suite needed a real WebSocket server and a client helper to assert
these. Here they are graph properties, so they are asserted directly.
"""

import from datetime { datetime, timezone, timedelta }
import from identity { register_developer }
import from escalation {
    Escalation, Ask, Resolve, Pending, Withdraw,
    pending_for, find_escalation, is_expired
}


def _ask_for(dev_id: str, title: str = "Conflict") -> str {
    res = root spawn Ask(dev_id=dev_id, title=title, reason="two intents collided");
    return res.reports[0]["conflict_id"] as str;
}


test "asking an unregistered developer fails fast instead of hanging" {
    res = root spawn Ask(dev_id="dev_nobody", title="x", reason="y");
    assert res.reports[0]["error"] == "no_notch";
}

test "an escalation comes back with options the notch can render" {
    dev = register_developer("esc-options");
    res = root spawn Ask(dev_id=dev.dev_id, title="Pricing", reason="collided");
    options = res.reports[0]["options"];
    ids = [o["id"] for o in options];
    assert "green" in ids;
    assert "red" in ids;
    assert "other" in ids;
}

test "asking suspends until the developer answers, then resolves with their choice" {
    dev = register_developer("esc-answer");
    conflict_id = _ask_for(dev.dev_id);
    assert len(pending_for(dev.dev_id)) == 1;

    res = root spawn Resolve(conflict_id=conflict_id, dev_id=dev.dev_id, choice="green");
    assert res.reports[0]["status"] == "applied";
    assert res.reports[0]["choice"] == "green";
    assert pending_for(dev.dev_id) == [];
}

test "a typed instruction comes back as custom text" {
    dev = register_developer("esc-custom");
    conflict_id = _ask_for(dev.dev_id);
    res = root spawn Resolve(
        conflict_id=conflict_id,
        dev_id=dev.dev_id,
        choice="other",
        custom_text="keep both, behind a flag"
    );
    assert res.reports[0]["custom_text"] == "keep both, behind a flag";
}

test "a developer cannot resolve someone else's conflict" {
    alice = register_developer("esc-alice");
    bob = register_developer("esc-bob");
    conflict_id = _ask_for(alice.dev_id);

    res = root spawn Resolve(conflict_id=conflict_id, dev_id=bob.dev_id, choice="green");
    assert res.reports[0]["status"] == "error";
    # and alice's question is still open, not consumed by bob's attempt
    assert len(pending_for(alice.dev_id)) == 1;
}

test "dev_b never sees dev_a's escalation" {
    alice = register_developer("esc-scope-a");
    bob = register_developer("esc-scope-b");
    _ = _ask_for(alice.dev_id, "alice only");

    assert len(pending_for(alice.dev_id)) == 1;
    assert pending_for(bob.dev_id) == [];
}

test "resolving an unknown conflict is refused" {
    dev = register_developer("esc-unknown");
    res = root spawn Resolve(conflict_id="c_nope", dev_id=dev.dev_id, choice="green");
    assert res.reports[0]["status"] == "error";
}

test "the same conflict cannot be resolved twice" {
    dev = register_developer("esc-twice");
    conflict_id = _ask_for(dev.dev_id);
    _ = root spawn Resolve(conflict_id=conflict_id, dev_id=dev.dev_id, choice="green");
    second = root spawn Resolve(conflict_id=conflict_id, dev_id=dev.dev_id, choice="red");
    assert second.reports[0]["status"] == "error";
}

test "an unanswered question expires instead of wedging the queue" {
    dev = register_developer("esc-expiry");
    conflict_id = _ask_for(dev.dev_id);
    escalation = find_escalation(conflict_id);
    assert escalation is not None;

    # backdate the deadline rather than sleeping five real minutes
    escalation.expires_at = (
        datetime.now(timezone.utc) - timedelta(seconds=1)
    ).isoformat();
    assert is_expired(escalation);

    res = root spawn Resolve(conflict_id=conflict_id, dev_id=dev.dev_id, choice="green");
    assert res.reports[0]["status"] == "error";
    assert pending_for(dev.dev_id) == [];
}

test "a reconnecting notch catches up through pending" {
    dev = register_developer("esc-reconnect");
    _ = _ask_for(dev.dev_id, "first");
    _ = _ask_for(dev.dev_id, "second");

    res = root spawn Pending(dev_id=dev.dev_id);
    titles = [e["title"] for e in res.reports[0]];
    assert "first" in titles;
    assert "second" in titles;
}

test "withdrawing an escalation drops it from pending" {
    dev = register_developer("esc-withdraw");
    conflict_id = _ask_for(dev.dev_id);
    res = root spawn Withdraw(conflict_id=conflict_id, reason="superseded");
    assert res.reports[0]["withdrawn"];
    assert pending_for(dev.dev_id) == [];
}
