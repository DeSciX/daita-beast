# daita-beast

BEAST is the coordination app of the `daita` community on DeSciX: a protocol for agent teams that uses GitHub's own objects (Projects, issues, labels, pull requests) and a thin Claude Code plugin wrapping the few `gh` calls a seat makes. GitHub keeps the permissions, the history and the cost. The platform app id is `daita-beast`.

Read [docs/protocol.md](docs/protocol.md) first: a workstream is a GitHub Project plus a tracking issue found by its labels, a pending decision is an assigned issue, status reports are comments, a seat is one role (an agent file) held under a label in one workstream, and the workstream's tracking issue carries its seat map. The design as built, and how another agent system adopts it: [docs/design/](docs/design/README.md).

## Layout

| Path | Holds |
|---|---|
| `docs/protocol.md` | the protocol: the mapping, the issue shapes, seats, decisions, workstreams, hand-backs |
| `plugin/` | the plugin: skills (`install`, `seat`, `join`, `seats`, `board`, `board-ui`, `decision`, `pr`, `publish`, `license`, `desk`, `respond`, `status`, `workstream`, `milestone`, `deps`, `init-repo`, `relay`, `award`, `bounty`, `ledger`, `report`, `resume`, `wrapup`, `realign`, `connector`, `cowork-tick`), agents (the generic `seat` role, relay messenger and installer, moderator, reporter, seat-clerk, license-reviewer), three hooks (PreToolUse `permit.sh`, SessionStart `seat-hello.sh`, SessionEnd `seat-bye.sh`), REST-only scripts and templates |
| `plugin/templates/` | what the scripts stamp and render: the decision, workstream and bounty issue templates, the roster example, the generated Beast block of a home's CLAUDE.md, the workstream block of a master's CLAUDE.md, the board page, labels |
| `plugin/tests/` | the test suite (`npm test`) |
| seats | a seat is `<slug>/<LABEL>/<login>`: one role (`--agent`, an agent file in its repo or the plugin's generic `daita-beast:seat`) in one workstream (`--workstream`, a slug). `seat.sh new <LABEL> --repo-path <checkout> --agent <name> --workstream <slug>` writes, in one act, the roster row, the home (the checkout, a worktree `<repo>.seats/<LABEL>`, a subdir, or a wrapper), the row of the workstream issue's `## Seats` table and the master repo's CLAUDE.md block; the SessionStart hook lists the seats a session can take |
| joining | seating sets the root: a session started anywhere in the workspace runs `join.sh <SEAT>` (from any directory), which prints `SEATED <id> at <home>` and `role: <agent> at <path>`, records the session's address as the seat's `BEAST-ADDRESS` comment, regenerates the Beast block, audits memory, and prints the handoff, notes and inbox; from then on the session works in the home |
| two tiers | the board holds PRs for the decider's review (`needs-review`) and decision issues; each seat's desk holds questions across the desk and messages, never on the board |
| the board as a queue | every decision is a row before anyone acts; each seat acks on the row (`BEAST-ACK`), its inbox is computed from GitHub alone, the generated board shows pending and decided rows with per-seat ack state |
| `docs/connector-access.md` | how the GitHub connector sees (or misses) repositories, per account |
| `docs/guides/` | for an outside organization: `setup-guide.html` (installing Beast on each surface and setting up a project, with a worked example) and `rewards.html` (bounties, awards and the monthly ledger) |

## Using the plugin

One plugin, three surfaces; `/daita-beast:install` detects which one you are on from evidence and walks only that surface's numbered checklist, each step with its gate (`plugin/skills/install/SKILL.md`): on a machine, tools, the marketplace install, permissions, the plugin record, bootstrap, workstream, seat, join, relay and a fixture; in the cloud, the clone; in Cowork, the connector, the board page and a scheduled tick.

Claude Code, local:
```
/plugin marketplace add DeSciX/DAITA
/plugin install daita-beast@daita
/daita-beast:install
```
Requirements there: `gh` (logged in; the `project` scope for workstreams: `gh auth refresh -s project`), `jq`, `git`, `python3`. The plugin's PreToolUse hook allows its own scripts and nothing else; the relay (`/daita-beast:relay`) runs in the seats' permission mode.

The install is a numbered checklist per surface, each step with its gate: on a machine it adds the `permissions.allow` rules a seat needs to the repo's `.claude/settings.json` (`plugin/scripts/permissions.sh`, diff shown, written on the word) and records the installed plugin in `~/.beast/plugin.json`, so a committed CLAUDE.md block never names a machine path (`seat-hello` prints the scripts path at every session start).

Claude Code, cloud: plugins are not installed in a cloud session. A repository set up by `bootstrap.sh` carries `.claude/skills/beast/SKILL.md`, a committed pointer that clones the plugin and runs its scripts over REST (GitHub Projects refuse there; only attached repositories are reachable; the seat pulls its inbox at every wake).

Cowork and Claude.ai chat: Customize › Plugins › add marketplace `DeSciX/DAITA` › install `daita-beast`. There is no shell; `/daita-beast:connector` is the protocol as GitHub connector calls. The connector must be installed on every account whose repositories it should see: [docs/connector-access.md](docs/connector-access.md).

Development, from a checkout: `claude --plugin-dir /path/to/daita-beast/plugin`.

Make a repository a coordinating repo, open its workstream, then seat yourself:
```
plugin/scripts/bootstrap.sh --repo <owner/repo> --path <checkout> --seat <LABEL> [--token <SYMBOL> --community <owner/repo>]
plugin/scripts/workstream.sh new --slug <slug> --owner <owner> --title "WS: <name>" --repo <owner/repo> --northstar-file <f> --milestone "<title>|<YYYY-MM-DD>|<delivers>"
plugin/scripts/seat.sh new <LABEL> --repo-path <checkout> --agent <name | daita-beast:seat> --workstream <slug>   # after the scoping step of /daita-beast:seat
plugin/scripts/join.sh <LABEL>                                                                                    # every session, from any directory
```
The seat's identity is `<slug>/<LABEL>/<your gh login>`; inside its workstream `<login>/<LABEL>` abbreviates it, and every script accepts either form or the bare label.
Every script parses by shape and exits non-zero naming what it could not read.

## Tests

```
npm test
```
runs the suite under `plugin/tests/` with Node's built-in test runner (Node 22, `jq` on the path); CI runs the same on every push and pull request. Check a changed script with `bash -n`.

## Roster

A coordinating repo's seats, people and repos live in its committed `.beast/roster.json` (shape: `plugin/templates/roster.example.json`; fields: `docs/protocol.md`). Every default a script needs about your setup (the decider, the board repo, the public repo a private twin publishes to, the license your public repos carry) is read from the roster, never built into the plugin.
