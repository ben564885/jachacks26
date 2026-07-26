"""
Entrypoint: seed the codebase graph, run both scenarios through the same
four walkers, prove the contrast -- scenario 1 has no precedent and has to
ask; scenario 2 lands on a different file but the same concept, and the
graph already knows the answer.
"""

import from schema { File, Conflict }
import from walkers { DetectConflict, CheckPrecedent, Escalate, ApplyDecision }
import from surface { EscalationSurface, ScriptedSurface }
import from scenarios { build_codebase_graph, Scenario, SCENARIO_1, SCENARIO_2 }
import from judgment { Verdict }

def run_scenario(scenario: Scenario, files: dict[str, File], surface: EscalationSurface) {
    print(f"\n=== {scenario.conflict_id} :: {scenario.file_path} ===");
    file_node = files[scenario.file_path];

    detect_res = file_node spawn DetectConflict(
        conflict_id=scenario.conflict_id,
        ours_dev=scenario.ours_dev, ours_intent=scenario.ours_intent, ours_diff=scenario.ours_diff,
        theirs_dev=scenario.theirs_dev, theirs_intent=scenario.theirs_intent, theirs_diff=scenario.theirs_diff
    );
    conflict = detect_res.reports[0] as Conflict;

    precedent_res = conflict spawn CheckPrecedent();
    precedent_choices = precedent_res.precedent_choices;
    print(f"precedent found on this concept: {precedent_choices if precedent_choices else 'none'}");

    escalate_res = conflict spawn Escalate(
        ours_dev=scenario.ours_dev, ours_intent=scenario.ours_intent,
        theirs_dev=scenario.theirs_dev, theirs_intent=scenario.theirs_intent,
        precedent_choices=precedent_choices,
        surface=surface
    );
    print(f"verdict: {escalate_res.verdict}");

    if escalate_res.verdict == Verdict.ESCALATE and escalate_res.resolution is not None {
        resolution = escalate_res.resolution;
        conflict spawn ApplyDecision(
            decision_id=f"d_{scenario.conflict_id}",
            choice=resolution.choice,
            custom_text=resolution.custom_text,
            reasoning="developer answered the escalation",
            via_precedent=False
        );
    } else {
        chosen = precedent_choices[0] if precedent_choices else "green";
        reasoning = "matched existing precedent on this concept" if precedent_choices else "resolved mechanically, no product decision needed";
        conflict spawn ApplyDecision(
            decision_id=f"d_{scenario.conflict_id}",
            choice=chosen,
            reasoning=reasoning,
            via_precedent=len(precedent_choices) > 0
        );
    }
    print(f"{scenario.conflict_id} resolved.");
}

with entry {
    files = build_codebase_graph();
    surface = ScriptedSurface(answers={"c_pricing_01": "green"});

    run_scenario(SCENARIO_1, files, surface);
    run_scenario(SCENARIO_2, files, surface);
}
