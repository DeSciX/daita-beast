# daita-beast

BEAST is the coordination app of the `daita` community on DeSciX: a protocol for agent teams that uses GitHub's own objects (Projects, issues, labels, pull requests) and a thin Claude Code plugin wrapping the few `gh` calls a seat makes. GitHub keeps the permissions, the history and the cost. The platform app id is `daita-beast`.

Read [docs/protocol.md](docs/protocol.md) first: a workstream is a GitHub Project, a pending decision is an assigned issue, status reports are comments, seats resolve each other through a repo-scoped roster.

## Layout

| Path | Holds |
|---|---|
| `docs/protocol.md` | the protocol: the mapping, the issue shapes, seats, decisions, workstreams, hand-backs |
| `plugin/` | the plugin: skills (`install`, `seat`, `join`, `seats`, `board`, `decision`, `pr`, `publish`, `desk`, `respond`, `status`, `workstream`, `init-repo`, `relay`, `award`, `bounty`, `ledger`, `report`, `resume`, `connector`), agents (relay messenger and installer, moderator, reporter, seat-clerk), the PreToolUse permit hook and the SessionStart seat hook, REST-only scripts and templates |
| `plugin/templates/` | what the scripts stamp and render: the decision, workstream and bounty issue templates, the roster example, the generated CLAUDE.md block, the board page, labels |
| `plugin/tests/` | the test suite (`npm test`) |
| seat homes | `seat.sh new <LABEL>` adds a seat and creates its home (the checkout, a worktree `<repo>.seats/<LABEL>`, or a wrapper opened with `claude.sh`); the SessionStart hook names the seat in a session started there |
| joining | every session starts with `join.sh <SEAT>` from the seat's home: address, the generated CLAUDE.md block, memory audit, handoff, notes and inbox |
| two tiers | the board holds PRs for the decider's review (`needs-review`) and decision issues; each seat's desk holds questions across the desk and messages, never on the board |
| the board as a queue | every decision is a row before anyone acts; each seat acks on the row (`BEAST-ACK`), its inbox is computed from GitHub alone, the generated board shows pending and decided rows with per-seat ack state |
| `docs/connector-access.md` | how the GitHub connector sees (or misses) repositories, per account |

## Using the plugin

One plugin, three surfaces; `/daita-beast:install` detects which one you are on and does only its setup (`plugin/skills/install/SKILL.md`).

Claude Code, local:
```
/plugin marketplace add DeSciX/DAITA
/plugin install daita-beast@daita
/daita-beast:install
```
Requirements there: `gh` (logged in; the `project` scope for workstreams: `gh auth refresh -s project`), `jq`, `git`. The plugin's PreToolUse hook allows its own scripts and nothing else; the relay (`/daita-beast:relay`) runs in the seats' permission mode.

Claude Code, cloud: plugins are not installed in a cloud session. A repository set up by `bootstrap.sh` carries `.claude/skills/beast/SKILL.md`, a committed pointer that clones the plugin and runs its scripts over REST (GitHub Projects refuse there; only attached repositories are reachable; the seat pulls its inbox at every wake).

Cowork and Claude.ai chat: Customize › Plugins › add marketplace `DeSciX/DAITA` › install `daita-beast`. There is no shell; `/daita-beast:connector` is the protocol as GitHub connector calls. The connector must be installed on every account whose repositories it should see: [docs/connector-access.md](docs/connector-access.md).

Development, from a checkout: `claude --plugin-dir /path/to/daita-beast/plugin`.

Make a repository a coordinating repo, then fill its roster:
```
plugin/scripts/bootstrap.sh --repo <owner/repo> --path <checkout> --seat <LABEL> [--token <SYMBOL>]
plugin/scripts/seat.sh new <LABEL> --repo-path <checkout> --role "<what it owns>" --tracking <owner/repo#N>   # after the scoping step of /daita-beast:seat; the seat's id is <your gh login>/<LABEL>
```
Every script parses by shape and exits non-zero naming what it could not read.

## Tests

```
npm test
```
runs the suite under `plugin/tests/` with Node's built-in test runner (Node 22, `jq` on the path); CI runs the same on every push and pull request. Check a changed script with `bash -n`.

## Roster

A coordinating repo's seats, people and repos live in its committed `.beast/roster.json` (shape: `plugin/templates/roster.example.json`; fields: `docs/protocol.md`). Every default a script needs about your setup (the decider, the board repo, the public repo a private twin publishes to) is read from the roster, never built into the plugin.
