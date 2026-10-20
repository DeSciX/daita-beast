# Beast design

Beast is a coordination protocol for teams of agent sessions ("seats") and the people whose word they need ("deciders"), built entirely on GitHub's own objects: a pending decision is an assigned issue, a pull request awaiting review is labelled and assigned, a seat's small questions and messages are comments on one issue per seat (its desk), status is a comment on a workstream tracking issue, a workstream's seat map is a table on that issue, a seat's address is a comment there, and a seat's consumption of any of these is an `ack` comment. A seat is one role (an agent file) held under a label in one workstream; its identity is `<slug>/<LABEL>/<login>`. A thin Claude Code plugin wraps the few REST calls a seat makes (`plugin/scripts/*.sh`, with `lib.sh` the one owner of shared logic), adds three hooks, a generic seat agent and a handful of helper agents (among them the machine watchdog's), one skill per verb, and ships a board page for the decider. GitHub holds every durable fact, the permissions and the history; a machine holds only caches. The same protocol runs on Claude Code local (scripts plus an optional relay), Claude Code cloud (scripts over REST from a committed pointer skill) and Cowork or Claude.ai chat (GitHub connector recipes and a scheduled tick for the decider).

These documents describe the design as built. `docs/protocol.md` is the specification and wins on any conflict; these pages explain how the parts fit, why they are shaped the way they are, and how another coordination system moves onto them.

## Two readers

- **The team**: read in the order below. Every as-built claim cites `file::function` so it can be checked against the code.
- **An agent system adopting Beast**: start with `architecture.md` (what exists and where state lives), then `learnings.md` (the rules and the evidence behind them), then `adopting.md` (the mapping, the three choices, the order and the gates). Treat the citations as the place to verify a claim before relying on it.

## Reading order

1. [architecture.md](architecture.md): the system context; roles, identities, seats and workstreams; the components; where every fact lives; the surfaces.
2. [flows.md](flows.md): sequence diagrams of every protocol flow, each with its failure behavior.
3. [components.md](components.md): the catalogue of scripts, skills, agents, hooks, templates and roster fields.
4. [messaging-paths.html](messaging-paths.html): every call the board, the relay and the seats make, which connector carries it, and whose identity, quota and billing it spends; the rate-limit behaviour.
4. [learnings.md](learnings.md): the rules the iterations produced, each with why and the measured evidence.
5. [adopting.md](adopting.md): moving an existing agent-coordination system onto Beast.

## Index

| Page | Holds |
|---|---|
| `architecture.md` | system context diagram; roles, identities, seats, workstreams and the seat map; component diagram; state table (fact, owner, rendered copies, never); the surfaces table |
| `flows.md` | joining; adding a seat to a workstream; a decision row end to end; desk ask and the seat-to-seat line (direct or desk); the relay tick; the board page refresh; the Cowork tick; publish; milestones, dependencies and the participant report; wrap-up; license; the watchdog tick |
| `components.md` | every script with its verbs, `lib.sh` functions and writes; every skill; every agent; the three hooks; templates; roster fields and their readers |
| `messaging-paths.html` | the interaction paths (GitHub connector, `gh`, relay, SendMessage; no DeSciX connector); identity and billing per path; GitHub quotas and the secondary limit; the page's read budget and backoff |
| `learnings.md` | rule / why / evidence, grouped: state, relay cost, silent caps, GitHub timing, privacy of the decider's words, the queue, seating, the live checkout, the board page, connector shapes, scrub tuning, license, gates, one owner per fact across repos |
| `adopting.md` | mechanism mapping; roles to agent files, workstream slugs and surfaces; migration order with the gate per step; what to delete and when; relay-versus-polling token arithmetic; what differs from a local system; an outside organization (another owner's workstream through `workstream_owners`, who publishes, who awards a token, and the guides in `docs/guides/`) |

## Conventions used here

- Placeholders: `acme/widgets-dev` is a private twin, `acme/widgets` its public repo, `alice` the decider's login, `widgets` a workstream slug, `widgets/BUILDER/alice` a seat's identity and `alice/BUILDER` its short id inside that workstream, `<home>` a seat's home directory.
- "Row" means a board item: a `decision` issue or a pull request labelled `needs-review`.
- "Measured" means the evidence is a recorded run (a commit, a test, a fixture issue), not an expectation.
