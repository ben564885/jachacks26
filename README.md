# jachacks26

shared source control where a merge conflict becomes a question in your notch, not a rejected
push.

no branches, no pull requests. you edit normally and run `synqit push "add avatars"`; an agent
integrates your feature into the newest `main` and syncs you back. when it hits a decision that
isn't its to make, it suspends mid-integration, asks the developer who pushed — in their mac's
notch — and resumes with their answer.

the same decision is never asked twice. the codebase is modeled as a graph of concepts, files,
commits and decisions, and the agent is a walker over it, so "have we already decided this" is a
traversal rather than an embedding search — two different files that touch the same concept hit
the same precedent.

live: [the graph, visualized](https://synqit-jac.fly.dev/graph) ·
[swagger](https://synqit-jac.fly.dev/docs) · [healthz](https://synqit-jac.fly.dev/healthz)

there is no index page — `jac start` serves the api, not a site, so the bare origin is a 404.
start at `/graph`. the machine sleeps when idle, so the first request takes ~15s while the
`.jac` modules compile; after that it's under a second.

## layout

| | |
| --- | --- |
| `*.jac`, `main.jac` | the system, in [jac](https://www.jaseci.org) — graph schema, walkers, the integration agent, github i/o, the cli, and the websocket the notch reads. at the repo root, because `main.jac` is the entry point. see [docs/jac.md](docs/jac.md) |
| `components/` | the web board (`.cl.jac`) — the notch's loop in a browser, so the demo runs on a machine that isn't a mac. served at `/` |
| `notch/` | the macos escalation surface (swift, `LSUIElement`). see [notch/README.md](notch/README.md) |
| `landing/` | the marketing site (next.js). see [landing/README.md](landing/README.md) |

## install

```bash
make setup    # .jacvenv + pinned jaclang, jac-scale, byllm
make test     # type-check + all six jac suites, no api key needed
make serve    # every walker as a REST API on :8080
```

the macos app:

```bash
make install  # builds the .app and copies it to /Applications
```

and the landing site:

```bash
cd landing && npm install && npm run dev
```

`make help` lists the rest — `make cli`, `make demo` (needs `OPENAI_API_KEY`), `make deploy`.

## the demo

open `/` and work down the buttons: seed the graph, push `pricing.js`, answer the question it
raises, then push `billing_test.js` — a different file that reaches the same `FreeTier` concept
and answers itself off the decision you just made. needs `OPENAI_API_KEY` in the environment;
without it the board still seeds and traverses, and says so where the verdict would be.

the same thing in a terminal:

```bash
make demo
```

two scenarios, scripted. the first conflict has no precedent, so it escalates and a human
answers. the second is in a *different file* that reaches the same `FreeTier` concept — the walk
from the file to its `CodeConcept` and back down a `PrecedentFor` edge finds the first answer
sitting there, and nobody gets asked again.

built for jachacks sf 2026.
