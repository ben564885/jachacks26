# the jac server

Synqit, in [Jac](https://www.jaseci.org) — Jaseci's graph-native language. The `.jac` modules at the repo root **are**
the system: the Node server this project started from has been ported module for module and
removed. A merge conflict is a position in a graph of concepts, files, commits and past
decisions, and "have we already decided this" is a traversal, not an embedding search.

See the root README for the pitch. This file is setup and reference.

## Try it live — no install

It's already running at **https://synqit-jac.fly.dev**. There is no index page — `jac start`
serves the API, not a site, so the origin itself answers `404 Not found`. Three things are open
to anonymous callers, so start at one of these:

```bash
curl -s https://synqit-jac.fly.dev/healthz      # the service is up
open https://synqit-jac.fly.dev/graph           # the live graph, visualised
open https://synqit-jac.fly.dev/docs            # Swagger for every endpoint below
```

The machine sleeps when idle and boot recompiles the `.jac` modules, so the first request after
a quiet spell takes ~15s. Subsequent ones are under a second.

The walkers themselves are token-gated by design — this is shared source control, and a
developer's decisions are their own. Get a token:

```bash
curl -sX POST https://synqit-jac.fly.dev/user/register \
  -H 'Content-Type: application/json' \
  -d '{"identities":[{"type":"username","value":"judge"}],
       "credential":{"type":"password","password":"jachacks2026"}}'

TOKEN=$(curl -sX POST https://synqit-jac.fly.dev/user/login \
  -H 'Content-Type: application/json' \
  -d '{"identity":{"type":"username","value":"judge"},
       "credential":{"type":"password","password":"jachacks2026"}}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["token"])')

curl -s https://synqit-jac.fly.dev/walkers -H "Authorization: Bearer $TOKEN"
```

That whole API — auth, one endpoint per walker, Swagger, the graph visualiser — is generated
from the declarations in those modules. There is no route table anywhere in this repo.

## Run it locally

Only needed if you want to change the code. One command from the repo root:

```bash
make setup   # creates .jacvenv, installs pinned jaclang/jac-scale/byllm (idempotent)
make test    # type-checks everything + 49 tests, no LLM key or network needed
make demo    # scripted two-scenario walkthrough, needs OPENAI_API_KEY
make serve   # the same walkers as a local REST API on :8080
make deploy  # redeploy the live instance after a change
```

By hand: `python3.12 -m venv .jacvenv && source .jacvenv/bin/activate && pip install
"jaclang==0.16.7" "jac-scale==0.2.31" "byllm==0.6.19" requests`. Python 3.12 specifically —
jaclang doesn't run on 3.14 yet, and byllm needs a matched jaclang version.

**`jac-scale` is not optional.** Without it `jac start` still serves walkers, but `@restspec`
does not exist — which means `notchsocket.jac`'s WebSocket route, the one the macOS notch
connects to, is simply absent, along with `/docs`, `/healthz`, `/graph` and the admin portal.
It also needs `requests`, which its own package metadata does not declare; without that the
plugin fails to load quietly and you get the stripped-down server back with no error at the
call site. `jac plugins` is how you check — look for `jac-scale:scale`.

No wifi / no key at the venue? `jac model pull gemma-4-e2b` (~2.5GB) runs a local model instead
— swap the `Model(model_name=...)` in `llm_chain.jac`.

**If the host cannot load byllm.** byllm ships its own `.jac` source, which the *host's* jaclang
parses at import. A managed host running a jaclang other than the one byllm was built against
rejects that source, and the failure lands on `import from byllm.llm` — a syntax error in a file
nobody here wrote. No pin fixes it: every published byllm carries the syntax and every published
jaclang accepts it, so the mismatch is with a jaclang that is neither.

So nothing imports byllm at boot. `judge.jac` imports it inside the call that needs it and falls
back to `llm_http.jac`, which is the same two judgments over the OpenAI HTTP API using
`requests` — already a dependency, so it adds nothing to install. `by llm()` is still tried
first and still what runs wherever byllm loads.

```bash
SYNQIT_LLM_BACKEND=byllm   # require the Jac-native path, fail loudly if unavailable
SYNQIT_LLM_BACKEND=http    # skip byllm entirely
                           # unset (default): try byllm, fall back
```

`integrate.jac` is the exception. Its `by agent_llm(tools=[...])` ReAct loop has no HTTP
equivalent worth writing — reimplementing it means hand-rolling the tool schemas and dispatch
loop that Jac exists to delete. It is imported lazily from `push.jac`, so it costs nothing at
boot, but the full `synqit push` integration still needs a byllm the host can load.

## Layout

| File | What it is |
| --- | --- |
| **The graph** | |
| `schema.jac` | `CodeConcept`, `File`, `Commit`, `Conflict`, `Decision` nodes; `Touches`, `Changes`, `OnFile`, `PrecedentFor`, `Resolves` edges |
| `walkers.jac` | `DetectConflict`, `CheckPrecedent`, `Escalate`, `ApplyDecision` — one job each |
| `ingest.jac` | `IngestRepo` — builds the graph from a **real** repository, so it is derived rather than seeded |
| **The system** | |
| `github.jac` | The real GitHub Contents API. Jac compiles to Python bytecode, so `requests` imports directly |
| `conflict.jac` | Does anything you touched collide with main? (port of the old `conflict.js`) |
| `integrate.jac` | The integration agent. `by llm(tools=[...])` replaces a 190-line hand-rolled ReAct loop |
| `identity.jac` | Developers and projects as graph nodes — the old JSON store disappears |
| `escalation.jac` | `Ask` / `Resolve` / `Pending` / `Withdraw`. Escalations are nodes, so they survive a restart |
| `notchsocket.jac` | `NotchSocket` — the WebSocket the macOS notch speaks, via `@restspec(protocol=WEBSOCKET)` |
| `push.jac` | `SubmitPush` — the entire push flow as one walker, including the branch that never calls a model |
| `gitio.jac` | Real git via subprocess, with the server's tokens stripped from the child environment |
| `workspace.jac` | Snapshotting, change detection, and the path-safety gate |
| `settings.jac` | Where Synqit keeps credentials (0600) and per-workspace state |
| `ui.jac` | Terminal output, colour-aware |
| `cli.jac` | The `synqit` command line: `configure`, `doctor`, `init`, `status`, `push` |
| **Entrypoints** | |
| `main.jac` | **Servable.** Just imports — importing a module publishes its walkers as REST endpoints |
| `demo.jac` | The scripted two-scenario walkthrough. `make demo` |
| `llm_chain.jac` | The two `by llm()` judgment calls |
| `judgment.jac` | What a judgment *is* — `Verdict`, `JudgeResult`, `EscalationQuestion`. Types only, so importing them cannot drag byllm in |
| `judge.jac` | Which implementation answers. Imports byllm inside the call, not at module scope, and falls back to `llm_http.jac` |
| `llm_http.jac` | The same two judgments over plain HTTP, for hosts where byllm will not load |
| `surface.jac` | `EscalationSurface` seam + `TerminalSurface` + `ScriptedSurface` |
| `scenarios.jac` | Seeded two-file demo fixture |
| `jac.toml` | Project, pinned dependencies, server config |
| **Tests — 49, no key or network needed** | |
| `test_walkers.jac` | Precedent found across different files via a shared concept |
| `test_conflict.jac` | Mirrors the old `conflict.test.mjs` case-for-case |
| `test_ingest.jac` | The path→concept inference that makes cross-file precedent possible |
| `test_identity.jac` | Slug rules, id collisions, and token→developer resolution |
| `test_escalation.jac` | Per-developer scoping, double-resolve, expiry, reconnect catch-up |
| `test_workspace.jac` | The path-safety gate and change detection |

## The API, and where it comes from

Nothing below is hand-written routing. `jac start` reads the declarations and generates it.

| Endpoint | Declared as | LLM call? |
| --- | --- | --- |
| `POST /walker/IngestRepo` | `walker` — build the graph from a real repository | no |
| `POST /walker/DetectConflict` | `walker` — record a collision | no |
| `POST /walker/CheckPrecedent` | `walker` — has this concept been decided before? | no — pure traversal |
| `POST /walker/SubmitPush` | `walker` — the whole push flow | only when something collided |
| `POST /walker/Escalate` | `walker` — judge, then draft the question | yes — `judge_conflict` + `draft_escalation` |
| `POST /walker/Ask` · `Resolve` · `Pending` · `Withdraw` | `walker` — the escalation lifecycle | no |
| `POST /walker/RegisterDeveloper` | `walker` — identity + bearer token for a notch | no |
| `POST /walker/ApplyDecision` | `walker` — record the answer as precedent | no |
| `POST /walker/<name>/{nd}` | free with every walker: spawn it at a specific node id | — |
| `ws://…/ws/NotchSocket` | `@restspec(protocol=APIProtocol.WEBSOCKET)` on an `async walker:pub` | no |
| `/docs` · `/graph` · `/healthz` · `/admin` · `/user/*` | free from `jac-scale` | no |

A walker's `has` fields are the request body and its `report` values are the response, so the
interface cannot drift from the implementation — there is no schema to keep in sync, and no
client SDK to regenerate. `NotchSocket` is the only `:pub` walker: the notch connects before it
has a token, everything else requires one.

## Deployed

Fly.io, `python:3.12-slim`, `jac start main.jac --port 8080 --no_client`, `OPENAI_API_KEY` as a
Fly secret. `make deploy` (or `fly deploy -a synqit-jac`).

Three things the deployment learned the hard way:

- **2GB, not 512MB.** Boot compiles the `.jac` modules and initialises LLVM; 512MB and 1GB both
  OOM-killed the process mid-startup (410MB and 875MB RSS) into a 502 reboot loop.
- **One machine.** The graph persists to SQLite under `.jac/data` inside the machine, so a
  second machine answers reads from its own private copy. Going wider means `MONGODB_URI`
  (+ Redis for the cache tier and locks), not more machines.
- **`jac start` exits when stdin closes.** Not hypothetical in a container: the server drained
  and exited 0 about five minutes into a run, and the machine sat stopped until the next request
  woke it — taking the graph with it. The CMD holds stdin open with a pipe that never EOFs, and
  a `/healthz` check catches it in 15s if it dies anyway.
- **Nodes must be reachable from `root` to persist.** `OnFile` and `Resolves` both point
  *outward* from a new `Conflict` / `Decision`, so nothing linked `root` to them. Invisible in a
  script that does everything in one process; in a server it means the node is never persisted
  and the next request cannot find it.

There is no Jaseci-run PaaS to deploy to instead — `jac start --scale` generates Kubernetes
manifests and auto-provisions Mongo/Redis/ingress into a cluster *you* own. For one demo box
that is more moving parts than one Fly machine. [JacHammer](https://jachammer.ai) is the other
Jac-native option: a browser IDE that builds, previews and hosts a Jac project.

## Status

Every `.jac` file passes `jac check`. **49 tests pass** across six suites (`make test`) with no
LLM key and no network.

**Verified against live systems**, not just compiled:

- `github.jac` reads this repository's real head and commit history over the GitHub API.
- `IngestRepo` walked this repo and built **81 `File` nodes, 85 `CodeConcept` nodes and 3
  `Commit` nodes**, with `Config`, `Models`, `UI` and others genuinely reached by more than one
  file — the cross-file link a text diff cannot see.
- `jac run cli.jac -- doctor OWNER/REPO` verifies a real token against the real API, and
  correctly reports a token that lacks Contents scope.
- The deployed service answers `/healthz`, `/docs`, `/graph` and the full walker surface, and
  `/ws/NotchSocket` completes a real WebSocket handshake (101).

The `by llm()` integration agent is wired end to end and deployed with a real `OPENAI_API_KEY`.
It is the least-exercised path here: everything else is covered by tests that need no model.

One wire-shape gotcha worth knowing before you add an endpoint: a walker field typed `T | None`
is emitted as a **required** body field by the generated schema even when it has a default, so
wire-facing fields want concrete defaults (`custom_text: str = ""`) rather than Optionals.
