"""
The escalation board: the notch's loop, in a browser.

Scenario 1 has no precedent, so it becomes a question. You answer it. Scenario
2 is a *different file* that reaches the same concept, and answers itself off
the decision you just made -- which is the entire argument for modelling the
codebase as a graph instead of diffing text.
"""

sv import from ..board {
    seed_board, board_state, run_scenario, answer_question, reset_board,
    BoardState, RunResult, ConceptView, PendingView
}


def:pub Board() -> JsxElement {
    has state: BoardState | None = None;
    has last: RunResult | None = None;
    has busy: str = "";
    has note: str = "";

    async can with entry {
        state = await board_state();
    }

    async def handle_seed -> None {
        busy = "seed";
        note = "";
        state = await seed_board();
        busy = "";
    }

    async def run_one -> None {
        busy = "1";
        note = "";
        result = await run_scenario("1");
        last = result;
        note = result.error;
        state = await board_state();
        busy = "";
    }

    async def run_two -> None {
        busy = "2";
        note = "";
        result = await run_scenario("2");
        last = result;
        note = result.error;
        state = await board_state();
        busy = "";
    }

    async def handle_reset -> None {
        busy = "reset";
        note = "";
        last = None;
        state = await reset_board();
        busy = "";
    }

    async def answer_green -> None {
        pending_now = state.pending if state is not None else [];
        if len(pending_now) > 0 {
            busy = "answer";
            state = await answer_question(pending_now[0].conflict_id, "green");
            busy = "";
        }
    }

    async def answer_red -> None {
        pending_now = state.pending if state is not None else [];
        if len(pending_now) > 0 {
            busy = "answer";
            state = await answer_question(pending_now[0].conflict_id, "red");
            busy = "";
        }
    }

    concepts: list[ConceptView] = state.concepts if state is not None else [];
    pending: list[PendingView] = state.pending if state is not None else [];
    decisions: list[str] = state.decisions if state is not None else [];
    backend: str = state.backend if state is not None else "";

    return <main className="board">
        <header className="board-head">
            <h1>Synqit</h1>
            <p className="tagline">
                A merge conflict becomes a question, not a rejected push.
            </p>
            {if backend {
                <p className="backend">judgment backend: <code>{backend}</code></p>
            }}
        </header>

        <section className="controls">
            <button onClick={handle_seed} disabled={busy != ""}>
                {"seeding..." if busy == "seed" else "1. seed the codebase graph"}
            </button>
            <button onClick={run_one} disabled={busy != ""}>
                {"running..." if busy == "1" else "2. push pricing.js"}
            </button>
            <button onClick={run_two} disabled={busy != ""}>
                {"running..." if busy == "2" else "3. push billing_test.js"}
            </button>
            <button className="ghost" onClick={handle_reset} disabled={busy != ""}>
                reset
            </button>
        </section>

        {if note {
            <p className="error">{note}</p>
        }}

        {if len(pending) > 0 {
            <section className="escalation">
                <span className="badge">waiting on you</span>
                <h2>{pending[0].title}</h2>
                <p className="summary">{pending[0].summary}</p>
                <p className="file">{pending[0].file}</p>
                <div className="options">
                    <button className="green" onClick={answer_green} disabled={busy != ""}>
                        {pending[0].option_green}
                    </button>
                    <button className="red" onClick={answer_red} disabled={busy != ""}>
                        {pending[0].option_red}
                    </button>
                </div>
            </section>
        }}

        {if last is not None {
            <section className="verdict">
                <h3>{last.file}</h3>
                <p>
                    <strong>{last.verdict}</strong>
                    {" — " + last.reasoning if last.reasoning else ""}
                </p>
                {if len(last.precedent_choices) > 0 {
                    <p className="precedent">
                        {"precedent found on this concept: " + ", ".join(last.precedent_choices)}
                    </p>
                }}
                {if last.applied_choice {
                    <p className="precedent">
                        {"resolved as '" + last.applied_choice + "' without asking anyone."}
                    </p>
                }}
            </section>
        }}

        <section className="graph">
            <h3>the graph</h3>
            {if len(concepts) == 0 {
                <p className="empty">Nothing seeded yet.</p>
                skip;
            }}
            {for c in concepts {
                <div className="concept" key={c.name}>
                    <h4>{c.name}</h4>
                    <p className="files">{"touched by: " + ", ".join(c.files)}</p>
                    <p className="decided">
                        {"decided: " + ", ".join(c.decisions) if len(c.decisions) > 0 else "no decision yet"}
                    </p>
                </div>
            }}
            <p className="total">{str(len(decisions)) + " decision(s) on the graph"}</p>
        </section>
    </main>;
}
