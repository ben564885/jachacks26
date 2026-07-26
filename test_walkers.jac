"""
Proves the one claim the whole pitch rests on: a conflict on pricing.js and
a conflict on billing_test.js are unrelated by file, but the graph reaches
the same CodeConcept from both -- so a decision recorded against one is
found as precedent for the other. This is graph traversal, not text diffing
with an LLM sprinkled on, and it needs no LLM call to prove.

Escalate's `by llm()` chain is exercised separately (see llm_chain.jac) --
it needs a real API key, so it isn't asserted on here.
"""

import from schema { File, Conflict }
import from walkers { DetectConflict, CheckPrecedent, ApplyDecision }
import from scenarios { build_codebase_graph, SCENARIO_1, SCENARIO_2 }

test "precedent is found across different files via a shared concept" {
    files = build_codebase_graph();

    # scenario 1: pricing.js, nobody has decided this concept before
    detect_1 = files["pricing.js"] spawn DetectConflict(
        conflict_id=SCENARIO_1.conflict_id,
        ours_dev=SCENARIO_1.ours_dev, ours_intent=SCENARIO_1.ours_intent, ours_diff=SCENARIO_1.ours_diff,
        theirs_dev=SCENARIO_1.theirs_dev, theirs_intent=SCENARIO_1.theirs_intent, theirs_diff=SCENARIO_1.theirs_diff
    );
    conflict_1 = detect_1.reports[0] as Conflict;

    precedent_before = conflict_1 spawn CheckPrecedent();
    assert precedent_before.precedent_choices == [];

    # a human answers -- this is what Escalate would have fed in
    conflict_1 spawn ApplyDecision(
        decision_id="d_scenario_1",
        choice="green",
        reasoning="developer kept the unlimited free tier",
        via_precedent=False
    );
    assert conflict_1.status == "resolved";

    # scenario 2: a *different file*, same FreeTier concept
    detect_2 = files["billing_test.js"] spawn DetectConflict(
        conflict_id=SCENARIO_2.conflict_id,
        ours_dev=SCENARIO_2.ours_dev, ours_intent=SCENARIO_2.ours_intent, ours_diff=SCENARIO_2.ours_diff,
        theirs_dev=SCENARIO_2.theirs_dev, theirs_intent=SCENARIO_2.theirs_intent, theirs_diff=SCENARIO_2.theirs_diff
    );
    conflict_2 = detect_2.reports[0] as Conflict;

    precedent_after = conflict_2 spawn CheckPrecedent();
    assert precedent_after.precedent_choices == ["green"];
}

test "a conflict on an unrelated concept finds no precedent" {
    other_file = File(path="unrelated.js");
    root ++> other_file;

    detect = other_file spawn DetectConflict(
        conflict_id="c_unrelated",
        ours_dev="ben", ours_intent="refactor logging", ours_diff="1 file",
        theirs_dev="ana", theirs_intent="also touched logging", theirs_diff="1 file"
    );
    conflict = detect.reports[0] as Conflict;

    result = conflict spawn CheckPrecedent();
    assert result.precedent_choices == [];
}
