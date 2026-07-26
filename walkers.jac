"""
The four walkers. Each is one job:

  DetectConflict  -- a collision landed on a file, record it as a node
  CheckPrecedent  -- has this project already decided this concept before?
  Escalate        -- draft the question and hand it to whatever surface is live
  ApplyDecision   -- record the answer, and make it precedent for next time

Nothing here calls an LLM directly except through llm_chain's two focused
functions -- this file is the graph logic, that file is the judgment.
"""

import from schema {
    CodeConcept, File, Commit, Conflict, Decision,
    Touches, OursCommit, TheirsCommit, OnFile, PrecedentFor, Resolves
}
import from judgment { Verdict }
import from judge { judge_conflict, draft_escalation }
import from surface { Escalation, Resolution, EscalationSurface }

walker DetectConflict {
    has conflict_id: str;
    has ours_dev: str;
    has ours_intent: str;
    has ours_diff: str;
    has theirs_dev: str;
    has theirs_intent: str;
    has theirs_diff: str;

    can detect with File entry {
        conflict = Conflict(id=self.conflict_id);
        conflict +>:OnFile:+> here;
        # OnFile points conflict -> file, so the conflict is not reachable from
        # root by itself. In a script that is invisible; in the server it means
        # the node is never persisted and the next request cannot find it.
        root ++> conflict;

        ours = Commit(sha=f"{self.conflict_id}_ours", dev_id=self.ours_dev,
                       intent=self.ours_intent, diff_summary=self.ours_diff);
        conflict +>:OursCommit:+> ours;

        theirs = Commit(sha=f"{self.conflict_id}_theirs", dev_id=self.theirs_dev,
                         intent=self.theirs_intent, diff_summary=self.theirs_diff);
        conflict +>:TheirsCommit:+> theirs;

        report conflict;
    }
}

"""Structural traversal: conflict -> file -> concept -> (backward) any prior
Decision on that concept. No embeddings, no similarity score -- either the
graph has a Decision hanging off this concept or it doesn't."""
walker CheckPrecedent {
    has precedent_choices: list[str] = [];
    has concepts: list[CodeConcept] = [];

    can check with Conflict entry {
        files = [here ->:OnFile:->] as list[File];
        for f in files {
            found_concepts = [f ->:Touches:->] as list[CodeConcept];
            for c in found_concepts {
                self.concepts.append(c);
                decisions = [c <-:PrecedentFor:<-] as list[Decision];
                for d in decisions {
                    self.precedent_choices.append(d.choice);
                }
            }
        }
        report self.precedent_choices;
    }
}

"""Ask the two `by llm()` questions in sequence and hand the result to
whatever EscalationSurface is plugged in. Only actually escalates (calls
the surface) when the verdict says a human is needed."""
walker Escalate {
    has ours_dev: str;
    has ours_intent: str;
    has theirs_dev: str;
    has theirs_intent: str;
    has precedent_choices: list[str];
    has surface: EscalationSurface;

    has verdict: Verdict | None = None;
    has resolution: Resolution | None = None;

    can run with Conflict entry {
        file_nodes = [here ->:OnFile:->] as list[File];
        file_path: str = file_nodes[0].path if file_nodes else "unknown";

        judged = judge_conflict(
            file_path,
            self.ours_dev, self.ours_intent,
            self.theirs_dev, self.theirs_intent,
            self.precedent_choices
        );
        self.verdict = judged.verdict;

        if judged.verdict == Verdict.ESCALATE {
            question = draft_escalation(
                file_path,
                self.ours_dev, self.ours_intent,
                self.theirs_dev, self.theirs_intent
            );
            escalation = Escalation(
                conflict_id=here.id,
                dev_id=self.ours_dev,
                title=question.title,
                summary=question.summary,
                file=file_path,
                option_green=question.option_a_label,
                option_red=question.option_b_label
            );
            self.resolution = self.surface.ask(escalation);
        }

        report {"verdict": judged.verdict, "reasoning": judged.reasoning};
    }
}

"""Write the human's (or the precedent's) answer back as a Decision node,
resolved against this Conflict and made precedent for every CodeConcept the
conflict's file touches. This is the entire "the agent learns" mechanism --
a new edge, not a retrain."""
walker ApplyDecision {
    has decision_id: str;
    has choice: str;
    has custom_text: str | None = None;
    has reasoning: str = "";
    has via_precedent: bool = False;

    can apply with Conflict entry {
        decision = Decision(
            id=self.decision_id,
            choice=self.choice,
            custom_text=self.custom_text,
            reasoning=self.reasoning,
            via_precedent=self.via_precedent
        );
        decision +>:Resolves:+> here;
        root ++> decision;   # same reachability rule as Conflict above

        files = [here ->:OnFile:->] as list[File];
        for f in files {
            concepts = [f ->:Touches:->] as list[CodeConcept];
            for c in concepts {
                decision +>:PrecedentFor:+> c;
            }
        }

        here.status = "resolved";
        report decision;
    }
}

