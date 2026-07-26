"""
The seeded demo repo. Two files, two developers, one shared concept.

Scenario 1 (pricing.js): ben wants unlimited free-tier projects; ana already
removed the free tier on main. Nobody has decided this before -> escalates.

Scenario 2 (billing_test.js): a *different file*, but it reaches the same
FreeTier concept -- a test asserting the free tier still exists, landing
against main having removed it. A plain git/text diff sees no relationship
between pricing.js and billing_test.js. The concept graph does, and finds
scenario 1's decision sitting on FreeTier -> resolves without asking.
"""

import from schema { CodeConcept, File, Touches }

def build_codebase_graph() -> dict[str, File] {
    free_tier = CodeConcept(name="FreeTier");
    root ++> free_tier;

    pricing = File(path="pricing.js");
    root ++> pricing;
    pricing +>:Touches:+> free_tier;

    billing_test = File(path="billing_test.js");
    root ++> billing_test;
    billing_test +>:Touches:+> free_tier;

    return {"pricing.js": pricing, "billing_test.js": billing_test};
}

obj Scenario {
    has conflict_id: str;
    has file_path: str;
    has ours_dev: str;
    has ours_intent: str;
    has ours_diff: str;
    has theirs_dev: str;
    has theirs_intent: str;
    has theirs_diff: str;
}

glob SCENARIO_1 = Scenario(
    conflict_id="c_pricing_01",
    file_path="pricing.js",
    ours_dev="ben",
    ours_intent="Give free-tier users unlimited projects",
    ours_diff="1 file changed from f50e1f3",
    theirs_dev="ana",
    theirs_intent="Remove the free tier entirely",
    theirs_diff="commit 31100eb on main"
);

glob SCENARIO_2 = Scenario(
    conflict_id="c_billing_test_01",
    file_path="billing_test.js",
    ours_dev="ben",
    ours_intent="Add a test asserting unlimited free-tier projects",
    ours_diff="1 file changed from a9c02aa",
    theirs_dev="ana",
    theirs_intent="Remove free-tier assertions since the tier was removed",
    theirs_diff="commit 5c7e114 on main"
);
