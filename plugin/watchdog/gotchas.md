# Beast watchdog: the catalogue

The data file the watchdog agent (`plugin/agents/watchdog.md`) reads for each SIGNAL, and the list of what the tick (`plugin/scripts/watchdog.sh`) does without a model. Severity: **S1** a seat is missing the decider's word or a peer's message now; **S2** a defect that will cause an S1; **S3** hygiene. "Tick" means the shell acts alone; "agent" means the signal reaches the Haiku session. A new gotcha is filed as `watchdog: NEW:<slug> …` on the plugin twin and promoted into this file by the BEAST seat in a commit; the watchdog never edits this file.

Bounds, the same for every check: a nudge once per (seat, check, object) every 2 h (`unacked`, `stale-address`, `unreachable`, `milestone-required`, `duplicate-address`) or once a week (`untagged-comment`, `old-plugin`); at most 3 nudges a tick and 1 per seat; at most 1 new bug a tick and 5 a day; at most 1 relay re-point a tick. Tuning: three `false-alarm` replies on one check within 7 days double its parameter, once per three: `unacked.grace` 900 to 7200 s, `<check>.every` 7200 to 28800 s; each change is a `TUNE` line in the notes.

## stale-address (S1, agent: touch)

- **Signal.** A live seat (a claim in `~/.beast/sessions.json` with no `ended_at` whose transcript was written in the last 30 min) whose `BEAST-ADDRESS` comment is older than 24 h (`ADDRESS_FRESH_S`, lib.sh), recorded on this machine, and whose cached cwd is the seat's home. The relay sends such a seat nothing (`seats.sh address` says `path: desk — a stale address`; relay.log `no direct address from this machine: <seat>`).
- **Act.** When `ListAgents` lists the recorded `name [ref]` exactly, run the signal's `run:` line, `seats.sh touch <identity> --verified "<name [ref]>"`: it re-stamps only `at=` and claims no session, and refuses when the address, the machine or the home differs. Not listed: `reported not listed` (the seat re-records at its next join).
- **Never.** `seats.sh record` for the seat: it writes the caller's session as the seat's claim.

## unreachable (S2, agent: report, nudge a renamed session)

- **Signal.** relay.log `not sending to <seat> at <address>: not reachable on 2 messenger replies …`: the relay stopped sending to that address (its unreachable ledger, `~/.beast/relay-unreachable.json`), for a seat with a live session here. The tick counts every such line as waste (`waste:<seat>` in state) whether or not the seat is live.
- **Act.** If `ListAgents` lists a session whose cwd is the signal's `home` under another name, send the block to THAT address (the seat renamed its session); else `reported no live session under another name`. `seats.sh forget` is the decider's word, never the watchdog's.

## unacked (S1, agent: nudge)

- **Signal.** A row or desk in a live seat's relay snapshot (`~/.beast/watch/<login>/<LABEL>.json`), updated in the last day, whose latest event (created, the decider's answer-form comment, closed: `row_events`; on a desk, an answer or message newer than the seat's desk ack) is newer than the seat's newest `BEAST-ACK` (`seat_acks`) and older than the grace (15 min). The tick reads a row only when its `updatedAt` moved, and caches the result per row and seat.
- **Act.** Send the block (the rows, the ack line to run). The inbox is the contract; the nudge is a second push. A seat not live is never signalled: its inbox waits for its wake.

## untagged-comment (S2, agent: judge, then nudge)

- **Signal.** On a row the tick re-read, a comment by the seats' login since the last tick whose first line is neither bookkeeping, an answer form, nor a seat tag, and whose body carries a seat's tell (`Closed by seat`, `seat=`, `--by `, a `cd /Users/…` command, "builder"). Such a comment is read as the decider's (`event_actors`: the `-` actor) and relayed to every seat on the row as the decider's news.
- **Act.** A heuristic: when the comment reads as the decider's own words, reply `false-alarm <why>`. Otherwise send the block (delete it and repost through `ack.sh --text`; delete, never edit). The watchdog never deletes or edits a comment.

## old-plugin (S2, agent: nudge)

- **Signal.** A live transcript's SessionStart context (`scripts: <root>/scripts`, seat-hello.sh) names a plugin root whose version is not the installed one (`~/.claude/plugins/installed_plugins.json`, `daita-beast@daita`): the session's hooks run an old cache.
- **Act.** Send the block (restart at a seam, after the handoff). Restarting is the person's act.

## milestone-required (S3, agent: nudge)

- **Signal.** The refusal `has open milestones; pass --milestone with one of:` (`milestone_require`) twice in one live transcript's tail.
- **Act.** Send the block. Moving or closing a milestone is the seat's act; the rule is the decider's.

## duplicate-address (S2, agent: nudge)

- **Signal.** relay.log `… has 2 BEAST-ADDRESS comments …` (`seat_address_read` dies): every script that reads that seat's address dies until one is deleted.
- **Act.** Send the block to the live seat; never delete a comment.

## Tick only (no agent)

| Check | Signal | What the tick does |
|---|---|---|
| quota | `rate_limit` (uncharged): search < 5 or core < 200 | runs only the local checks; no GitHub read or write this tick |
| relay-repoint | `install-relay.sh --job relay --describe`: the program is not `$(plugin_root)/scripts/relay.sh`, the job is not loaded, or its mode is not the roster's `relay.permissionMode` | `install-relay.sh --job relay --repo <its repo> --permission-mode <roster> --model <its model>`, then `--describe` again: `repaired` only when the program and `loaded=yes` read back; otherwise a bug |
| plugin-record | `installed_plugins.json` names a version `~/.beast/plugin.json` does not | `plugin_root_record <installPath>` (the one writer), before the relay check |
| relay-silent | loaded and right, but no `poll:` line in 6 min, three ticks running | a bug with the last 40 log lines |
| corrupt-mark | relay.log `the mark <file> is corrupt …; delete it` | deletes exactly that `.mark` under `~/.beast/watch/` (watch.sh's own instruction) |
| ws-seats-table | relay.log `workstream <slug> (<ref>): its \`## Seats\` table does not parse; skipped by ws_seats_all …` (watch.sh names it once per message) | a bug per tracking issue with the parser's message and the vocabulary; never edits the issue |
| watch-failed | relay.log `watch failed (exit <n>, named above)` | a bug with the lines before it |
| rate-limit-burst | three `GitHub rate limit at …` lines (watch.sh's backoff start) in one hour | a bug for that hour with the poll and baseline lines around them |
| hook-misfire | a line in `~/.beast/hooks.log` (`<UTC> <hook> block|fault session=<id> <message>`, lib.sh `hook_log`), or a SessionStart fault (`could not decide whether to rejoin`, `could not name this directory's seat`) in a live transcript's tail | a bug per hook and message class (`<hook>/<kind>-<class>`), the excerpt and the installed version in its body |
| weekly | a retired roster row's `~/.beast/watch/<login>/<LABEL>.{json,mark}`; a legacy `~/.beast/watch-*.json` | deletes those relay cache files, each logged |

Not measurable from a machine, so no check: a board page published without a capability (the Cowork tick's), a row that should have been a seat-to-seat message (the decider's board says it).

## Memory

- `~/.beast/watchdog/state.json`: the log offsets (`offsets.relay_log`, `offsets.hooks_log`, `offsets.tx:<session>`), the nudge ledger (`nudges`, pruned after 7 days), the bug ledger and queue (`bugs`, `bugs_queue`, `bug_days`), the row cache (`rows`, pruned after 7 days), counters (`counts`), false alarms and tuning (`falses`, `tune`), the Beast tracking issue (`beast_tracking`). A cache: losing it costs one duplicate nudge at most; bugs stay deduplicated because `watchdog.sh bug` lists the twin's issues.
- One `BEAST-WATCHDOG-NOTES machine=<host> at=<UTC> entries=<n>` comment on the Beast workstream's tracking issue, edited in place by the tick: `<date> GOTCHA|FALSE|TUNE <check> <object> — <one line>`, newest first, at most 60 lines, none older than 30 days. Bookkeeping: the relay never wakes a seat for it (`BOOKKEEPING_FIRST_LINE_RE`), and a wrap-up keeps it.
