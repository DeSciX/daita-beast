# Adopting Beast

How an existing agent-coordination system (its own seats, a mutex, a shared log, a polling loop, a worklist, handoff files, executive summaries) moves onto Beast. The principle throughout: each fact gets one owner on GitHub (`architecture.md`, "Where state lives"), and the local mechanism that held it is deleted in the same step its replacement passes its gate. Two live owners of one fact disagree silently; a seat reads whichever it finds first.

## 1. Mapping

| Local mechanism | What it really holds | Beast object | Notes |
|---|---|---|---|
| A seat registry or session list | who exists, what each owns, how to reach it | a roster row per seat in the seat's own repo (`seats[]`: `label`, `github`, `repo`, `agent`, `workstream`, `home`, optional `lane`), the workstream issue's `## Seats` table for who is in a workstream, and one `BEAST-ADDRESS` comment per seat for how to reach it | the identity is `<slug>/<LABEL>/<login>`, derived; a roster lists its own repo's seats only; addresses are re-recorded at every join and read live by `seats.sh address` |
| A role definition (a prompt, a persona file, a job description) | what a seat is obliged to do and how it works | an agent file: the plugin's generic `daita-beast:seat` for a pure orchestrator, or `<repo>/.claude/agents/<name>.md` specializing it with the domain and the line `Seat role: daita-beast:seat` | the roster row's `agent` names it and `join.sh` checks it exists; the obligations every seat shares live in the generated Beast block, so the agent file carries only the domain |
| A mutex or lock: "who is working on X" | ownership of a scope | the seat's agent file (its domain), one seat per home, a worktree branch `seat/<LABEL>` per seat, and the workstream the seat is in | Beast has no lock primitive. Ownership is declared, not acquired |
| A mutex or lock: "only one may do act Y" (deploy, release, a maintenance window) | permission for an exclusive act | a `decision` row for the act (`hands` when only the decider can perform it); the hearing seat is the one that acts | the row's close is the grant; a second seat finds the row in its inbox, not a held lock |
| A runtime lock between machines or jobs | a process-level guarantee | not coordination state: keep it in the system that runs the job | report a hold that blocks a seat as `BEAST-STATUS … state=blocked` naming what it waits on |
| A shared COMMS log | messages between seats and to the human | the seat-to-seat line (`BEAST-MSG from= to= re= blocking=no at=`): a direct `SendMessage` when `seats.sh address` says the path is direct, else the durable copy on the recipient's desk (`desk.sh msg`); only at a seam, a blocker or a completion | the desk is per recipient, so nobody scans one long log; a line never waits on the decider |
| Questions to the human inside the log | asks that need a word | a `decision` row (an act without code) or a PR with `needs-review` (a code change); a small question across the desk is a desk ask with options | filed before asking, content inline or linked at a commit; the Stop hook holds a seated session to it |
| A polling loop in each session | hearing about changes | the relay (one search per tick for all seats, messages only on a change, only to direct addresses) plus `decision.sh inbox` at each wake; in Cowork, the decider's scheduled tick | the inbox is the contract; the relay and the tick are optimizations |
| A project or team definition | which seats work on what, from which repos, who is the lead repo | a workstream: a slug, one Project, one tracking issue labelled `workstream` and `ws:<slug>` in the master repo, its `## Seats` table, its milestones | the master is the issue's repo; its CLAUDE.md carries the rendered map |
| A worklist or task board | what is planned, by when, waiting on what | a GitHub Project per workstream, milestones on the home repo, issues and PRs under them, `Waits on:` lines | `deps.sh` measures each dependency |
| Handoff files | a seat's working state across compactions | the seat's newest `BEAST-STATUS … state=handoff` on its tracking issue; durable facts in its one `BEAST-NOTES` comment | read back by `resume.sh` at every join |
| Executive summaries | state for the human | the generated board (pending and decided with the words), the board page, the Cowork digest, the participant report at a milestone close, the `reporter` agent for a period | computed from GitHub, never hand-written state |
| A decisions log of past rulings | the human's words and their rules | the close comment of each row (words verbatim), folded into the docs at the milestone's wrap-up, then deleted | a ruling already built is a second copy of a fact |
| Per-session memory notes | lessons and state mixed | lessons true for every seat stay in the launch folder's auto-memory; seat state moves to GitHub | `join.sh` lists the memory files and index lines that restate seat state; lessons and pointers stay |

## 2. Roles, workstreams and surfaces: the three choices before the first command

**Roles to agent files.** List the roles the system already has (its personas, its job descriptions, its standing prompts). For each, decide whether it orchestrates (hires builders, files rows, posts status) or builds. An orchestrating role becomes an agent file in the repo the seat works in, `.claude/agents/<name>.md`, holding only its domain (what it owns, which specialists it hires, what it never touches) and the line `Seat role: daita-beast:seat`; a role with no domain beyond orchestration names `daita-beast:seat` itself. A building role is not a seat: it is a specialist the seat hires (an agent file, `memory: project` when it must keep what it learns). The obligations every seat shares (inbox first, a row before a question, status at seams, a handoff before compaction) are not written into any agent file: the generated Beast block owns them and the generic agent points at it.

**Workstream slugs.** One workstream per stream of work with its own acceptance and milestones, not one per repo and not one per seat. The slug is the id (`a-z`, `0-9`, `-`): choose it as the thing the work delivers (`widgets`, `airdrop`, `docs-site`), since it labels the tracking issue (`ws:<slug>`), names the identity of every seat in it (`<slug>/<LABEL>/<login>`) and marks the block in the master's CLAUDE.md. The master is the repo the tracking issue is filed in: the repo that coordinates the stream, which is usually the private twin of the product it delivers. A seat is in exactly one workstream; the same login and label in two workstreams are two seats.

**Surfaces.** Decide per seat and per person where each runs, then bootstrap that surface with the `install` skill (`plugin/skills/install/SKILL.md`), which detects the surface from evidence and walks only that surface's checklist, each step with its gate:
- *A machine (terminal or VS Code)*: the marketplace plugin, then `/daita-beast:install`: tools; the install gate (the installed version equals `plugin.json`, `seat-hello` prints at the next start); `permissions.sh` adds the `gh` and git read rules to the repo's `.claude/settings.json` (the diff shown, written on the word, committed); `plugin_root_record` writes `~/.beast/plugin.json` so no committed file names a machine path; `bootstrap.sh`; `workstream.sh new --slug`; `seat.sh new --agent --workstream` (one act: row, home, table row, master block); `join.sh`; the relay; a fixture. In VS Code one window holds several repos: every session starts in the launch folder, the hook lists the seats of every workspace file that lists that folder, and seating sets the root.
- *Claude Code cloud*: nothing installs; `bootstrap.sh` commits `.claude/skills/beast/SKILL.md`, which clones the plugin and runs its scripts over REST. A cloud seat records no address and pulls its inbox at every wake; Projects verbs refuse there.
- *Cowork or Claude.ai chat*: the plugin from Customize › Plugins; the `connector` skill is the protocol as connector calls (a seat here acts through its recipes and is reached by its desk); the decider's board is published by `board-ui`, and a scheduled task running `/daita-beast:cowork-tick <owner/repo>` every 15 minutes or more posts the digest and republishes the page when the template moved. Roster rows and homes stay shell acts; the seat map can be changed from the connector (recipe 12).

## 3. Order of migration, and the gate per step

Run each step in a private repo that will be the home (the twin, if the system has a public side). A gate counts only after it has failed on its negative control.

| Step | Do | Gate (positive) | Negative control | Delete when the gate passes |
|---|---|---|---|---|
| 0. Inventory | list every local mechanism and the facts it holds; give each fact its owner from the state table; map each role to an agent file and each stream of work to a slug (section 2) | each fact has exactly one owner; each role names a file; each seat names one slug | a fact with two owners is named and resolved before step 1 | nothing yet |
| 1. Home and roster | `/daita-beast:install` on the surface, then `bootstrap.sh --repo <private repo> --path <checkout> --seat <LABEL>`; fill `people[]` with exactly one owner, `board`, and `publishes_to` if there is a public repo | `permissions.sh <checkout>` prints `nothing to add`; `seats.sh list` runs with no prompt | `decision.sh new --repo <a public repo> …` exits 1 from `coord_write_guard` | the old seat registry |
| 2. Workstreams, seats, homes and state | `workstream.sh new --slug <slug>` (with at least one milestone; the tracking issue carries `workstream` and `ws:<slug>`), `seat.sh new <LABEL> --repo-path <checkout> --agent <name> --workstream <slug>` per seat (one act: row, home, table row, master block); post each seat's current state as a handoff (`status.sh … --state handoff`) and its standing facts with `notes.sh set`; `join.sh <LABEL>` from the launch folder | `join.sh` prints `SEATED <id> at <home>` and `role: <agent> at <path>`; `workstream.sh seats <slug>` shows every seat; `resume.sh <SEAT>` prints the handoff and notes | a row with `role` or without `agent` makes `join.sh` die naming the key; `seat.sh new --agent nope` dies naming `.claude/agents/nope.md`; `join.sh` of a seat whose `seat.json` names another seat dies; a hand edit inside the master's block is undone by `workstream.sh render` | the role files the agent files replaced; handoff files; memory files `join.sh` lists |
| 3. Questions to the human | each open question becomes a row (`decision.sh new`, six sections, content inline) or a desk ask with options; a significant word already given is filed and closed with `decision.sh record` | `board.sh` renders every row; a fixture row answered on GitHub closes with `decision.sh close` | a body missing a section makes `board.sh` exit 1 naming it; a phrase carrying a pipe character is refused; a row whose Decision says "see session" is refused before any write | the question lists in the log |
| 4. Messages | seats message by `seats.sh address <SEAT>`'s path: `SendMessage` with the `BEAST-MSG` line when direct, `desk.sh msg` otherwise | a fixture message on a desk path appears in the recipient's `desk.sh inbox`; on a direct path the recipient replies | `seats.sh address` of a seat on another machine or account prints `path: desk`; an answer naming no open ask is named on stderr and dropped | the COMMS log (git history keeps it) |
| 5. Hearing | `/daita-beast:relay`, or the `relay-installer` agent, which also runs the fixture, on one machine, in the seats' permission mode; in Cowork, the scheduled tick | a fixture's `NEW` and `DECIDED` lines in `~/.beast/relay.log` and in the seat's session; a quiet tick posts nothing | an ack on the fixture produces no `UPDATED`; a seat without a direct address is logged and not sent | every polling loop and its schedule |
| 6. Work plan | worklist items become issues and PRs under milestones; dependencies become `--waits-on` lines | `deps.sh <SEAT>` shows each dependency with a state | `decision.sh new` without `--milestone` is refused while the repo has an open milestone | the worklist file |
| 7. Reporting | the board page for the decider (`/daita-beast:board-ui`), the Cowork tick, `report.sh milestone` at a close | `report.sh milestone <M>` without `--post` prints one section per participant; the page lists the open rows the connector lists | a seat without a desk stops `--post` before its first write | the summary generator |
| 8. Ownership and exclusive acts | map each mutex use per section 1 | each exclusive act has a row or an agent file's domain | a second seat attempting the act finds the row open in its inbox | the mutex records used for coordination |
| 9. Old records | at the first milestone's end, `wrapup.sh plan`, `request`, the fold-in commit, `run` | `wrapup.sh run` passes its checks and deletes only what the plan lists | a closed row neither cited nor dropped in the fold-in makes `run` refuse | the dated records the wrap-up folded in |

## 4. What to delete, and when

- Delete each local mechanism in the same step its replacement passes its gate, not later. Running both makes two owners of one fact.
- Delete, never annotate: a "superseded" label beside an old mechanism is read as live by the next agent (`plugin/skills/realign/SKILL.md`).
- Git keeps what was deleted; the archive is the history, not a folder of old files.
- Keep a runtime lock that guards a process (not a coordination fact) in the system that runs the process.
- A roster that lists another repo's seats is such a second owner: the workstream issue's table is the one owner, and `roster_check_unique` refuses the rows until they are gone.

## 5. Token cost: a relay versus polling

The arithmetic below counts model tokens; GitHub calls cost quota, not tokens. Apply your own rate card; cache reads are billed below fresh input, so the relevant question is how many turns run and how much context each re-reads.

Assumptions (change them and rerun the arithmetic):

| Symbol | Meaning | Value used |
|---|---|---|
| S | seats | 6 |
| P | polling interval, minutes | 5 |
| C | context a polling turn re-reads (the session's prefix) | 40,000 tokens |
| O | new tokens a poll adds (the tool output read) | 1,500 tokens |
| E | changes per hour that concern some seat | 6 |
| T | relay ticks per hour that carry at least one change | 4 (changes cluster) |
| M | one messenger run: its prompt, the address map and the event lines | 3,000 tokens (Haiku) |

**Polling.** Every seat takes a turn every P minutes whether or not anything changed: S × (60 / P) = 6 × 12 = 72 turns an hour, each re-reading C + O = 41,500 tokens, so about 2.99 million input tokens an hour, of which 72 × 1,500 = 108,000 are new. Whether the 40,000-token prefix is served from cache depends on whether the cache outlives the interval; when it does not, every poll pays the whole context at the fresh rate. In an idle hour the cost is the same.

**Relay.** A tick is one GitHub search and a local diff: no model runs (`relay.sh` exits on "no change"). Only the T ticks that carry changes start a messenger: T × M = 4 × 3,000 = 12,000 Haiku tokens an hour. Each of the E changes wakes its seat once; that turn is the work itself, and a polling seat would spend the same turn after the poll that found the change. At each wake the seat runs `decision.sh inbox` (its output, typically a few hundred to a few thousand tokens), which replaces the poll. In an idle hour the cost is zero tokens.

**The Cowork tick.** A tick is one Cowork turn every 15 minutes or more for the decider alone (4 an hour at most); a quiet tick reads the roster, the stamp, two searches, one commit and the page, and writes nothing. It is the decider's hearing on a surface with no relay, not a seat's.

**Comparison.** About 2.99 million (polling, any hour) against about 12,000 Haiku tokens plus E working turns (relay, busy hour) and zero (relay, idle hour). The polling cost scales with S / P and with each session's context size; the relay's scales with the number of changes.

**GitHub quota.** The relay spends one search per tick (30 an hour at 120 s, against a search quota of 30 a minute) and core reads only on changed rows; unchanged reads are 304s that cost nothing (`learnings.md`, Relay cost). The board and the inbox cost nothing warm; the page's searches (one every 2 min, one every 15 min), the relay and the tick share the search quota, which is why the tick runs no more often than every 15 minutes.

## 6. Things that differ from a local system

- **One login.** While every seat posts as the decider's login, GitHub sends no notification for one's own mention and refuses a review request to a PR's author, so Beast marks the decider's work by assignee and labels and reads "the decider's answer" as an assignee's comment in an answer form. Seats under their own logins would get GitHub's own notifications; the protocol holds unchanged, only the roster's `github` field differs.
- **Addresses are per machine and per account.** A `SendMessage` address reaches a seat only from the same machine and the same Claude account; the recorded address says which, and the desk is the path otherwise. A fleet across machines coordinates through desks and the inbox, and loses nothing by it.
- **Privacy.** A public repo never receives a coordination write, the seat map and the master's block included. If the system has public output, set up the twin pair before step 1 and publish only with `publish.sh`.
- **The decider's words.** They are quoted verbatim and never paraphrased; a seat relays a person's words labelled as theirs. On a repo that is or may become public, they are never written at all.
