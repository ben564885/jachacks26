"""
Tests for the path->concept inference that makes cross-file precedent
possible. No network, no LLM -- these assert the one claim the graph model
rests on: that two unrelated-looking paths resolve to a shared concept.
"""

import from ingest { concepts_for_path }

test "a nested path yields its directory segments and stem" {
    assert concepts_for_path("server/src/billing.js") == ["server", "src", "billing"];
}

test "a bare filename yields just its stem" {
    assert concepts_for_path("pricing.js") == ["pricing"];
}

test "test-suffixed files reach the same concept as what they test" {
    impl_concepts = concepts_for_path("billing/pricing.js");
    test_concepts = concepts_for_path("billing/pricing_test.js");
    shared = [c for c in impl_concepts if c in test_concepts];
    assert "pricing" in shared;
    assert "billing" in shared;
}

test "spec suffix is stripped the same way" {
    assert "checkout" in concepts_for_path("web/checkout_spec.ts");
}

test "windows separators normalize" {
    assert concepts_for_path("server\\src\\auth.js") == ["server", "src", "auth"];
}

test "dot segments never become concepts" {
    concepts = concepts_for_path("./src/./auth.js");
    assert "." not in concepts;
    assert "src" in concepts;
}
