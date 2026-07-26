"""
The graph. This is the whole bet: a merge conflict is not a text diff with an
LLM sprinkled on it, it is a position in a graph of concepts, files, commits
and past decisions -- and "have we been here before" is a traversal, not an
embedding search.
"""

node CodeConcept {
    has name: str;
}

node File {
    has path: str;
}

node Commit {
    has sha: str;
    has dev_id: str;
    has intent: str;
    has diff_summary: str;
}

node Conflict {
    has id: str;
    has status: str = "open";  # open | resolved
}

node Decision {
    has id: str;
    has choice: str;
    has custom_text: str | None = None;
    has reasoning: str = "";

    # decisions are made by asking (escalated) or by matching a precedent
    has via_precedent: bool = False;
}

edge Touches {}
edge Changes {}
edge OursCommit {}
edge TheirsCommit {}
edge OnFile {}
edge PrecedentFor {}
edge Resolves {}
