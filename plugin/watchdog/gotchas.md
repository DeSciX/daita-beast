# Beast watchdog: the catalogue

The data file the watchdog agent (`plugin/agents/watchdog.md`) reads for each SIGNAL, and the list of what the tick (`plugin/scripts/watchdog.sh`) does without a model. Severity: **S1** a seat is missing the decider's word or a peer's message now; **S2** a defect that will cause an S1; **S3** hygiene. "Tick" means the shell acts alone; "agent" means the signal reaches the Haiku session. A new gotcha is filed as `watchdog: NEW:<slug> …` on the plugin twin and promoted into this file by the BEAST seat in a commit; the watchdog never edits this file.

Bounds, the same for every check: a nudge once per (seat, check, object) every 2 h (`unacked`, `unreachable`, `milestone-required`, `duplicate-address`) or once a week (`untagged-comment`, `old-plugin`, `row-shape`); at most 3 nudges a tick and 1 per seat; at most 1 new bug a tick and 5 a day; at most 1 relay re-point a tick. Tuning: three `false-alarm` replies on one check within 7 days double its parameter, once per three: `unacked.grace` 900 to 7200 s, `<check>.every` 7200 to 28800 s; each change is a `TUNE` line in the notes.

## unreachable (S2, agent: nudge the live session)

- **Signal.** relay.log `not sending to <seat> at <address>: not reachable on 2 messenger replies …`: the relay stopped sending to that address (its unreachable ledger, `~/.beast/relay-unreachable.json`), for a seat with a live session here whose live name is that address's name. The tick counts every such line as waste (`waste:<seat>` in state) whether or not the seat is live. A seat live here under another name is no signal: the address check re-stamps it this tick, and the new address resets the relay's count.
- **Act.** Send the block to the signal's address (the live name) when `ListAgents` lists it; else `reported not listed`. `seats.sh forget` is the decider's word, never the watchdog's.

## unacked (S1, agent: nudge)

- **Signal.** A row or desk in a live seat's relay snapshot (`~/.beast/watch/<login>/<LABEL>.json`), updated in the last day, whose latest event (created, the decider's answer-form comment, closed: `row_events`; on a desk, an answer or message newer than the seat's desk ack) is newer than the seat's newest `BEAST-ACK` (`seat_acks`) and older than the grace (15 min). The tick reads a row only when its `updatedAt` moved, and caches the result per row and seat.
- **Act.** Send the block (the rows, the ack line to run). The inbox is the contract; the nudge is a second push. A seat not live is never signalled: its inbox waits for its wake.

## untagged-comment (S2, agent: judge, then nudge)

- **Signal.** On a row the tick re-read, a comment by the seats' login since the last tick whose first line is neither bookkeeping, an answer form, nor a seat tag, and whose body carries a seat's tell (`Closed by seat`, `seat=`, `--by `, a `cd /Users/…` command, "builder"). Such a comment is read as the decider's (`event_actors`: the `-` actor) and relayed to every seat on the row as the decider's news.
- **Act.** A heuristic: when the comment reads as the decider's own words, reply `false-alarm <why>`. Otherwise send the block (delete it and repost through `ack.sh --text`; delete, never edit). The watchdog never deletes or edits a comment.

## row-shape (S1, agent: nudge)

- **Signal.** On a row the tick re-read for check 7 (no other read, no search): an open decision issue or `needs-review` pull request, assigned (it waits on its decider), whose required sections (`ROW_SECTIONS`, `PR_ROW_SECTIONS`) are empty or missing by `section_required`, the one owner (`lib.sh::row_shape_missing`). The decider's board shows it `malformed: empty or missing ## <section>` with no buttons, so the row cannot be answered. Only the filing seat hears it (`row_filer`, the seat of the row's first `BEAST-ACK`; a row with none, its `row_seats`), and only while it is live. Measured 2026-10-21: a decision row was filed whole by `decision.sh new`; 33 s later a hand edit of its body under the shared login emptied `## Recommendation`.
- **Act.** Send the block: the row, the empty or missing sections, the repair path: `decision.sh restore <row> --by <SEAT>` (the seat puts back the last body a Beast script wrote, read from the body's edit history; no word of the decider's needed). Only when restore refuses (that body is itself malformed, or the row carries no `BEAST-BODY` record): a PR row, `pr.sh request` again; a publish row, `publish.sh request --amend`; a decision row, `decision.sh revise` after the decider's `revise:`. The object is the row and its missing set, so a fresh breakage of a repaired row is a fresh nudge. The watchdog never edits the row.

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
| live | `~/.beast/sessions.json` claims with no `ended_at`, against Claude Code's session files (`~/.claude/sessions/<pid>.json`, lib.sh `claude_sessions_read`: session id, name, cwd, pid alive by `kill -0`) | a claim whose session no live file names is logged `dead-claim: … reported, not re-stamped`; a session file that is not the shape is a bug (`claude-sessions`), and no seat is live that tick |
| address | a live seat's `BEAST-ADDRESS` comment, recorded on this machine, whose name is not its claimed session's live name (renamed), or older than 24 h (`ADDRESS_FRESH_S`) | `seats.sh touch <identity>`: the live name and `at=` now, refused unless the claim's session is live and runs in the seat's home or launch folder; logged `address: repaired …` and a `GOTCHA address` note. A comment recorded on another machine, or none, is logged and left |
| relay-repoint | `install-relay.sh --job relay --describe`: the program is not `$(plugin_root)/scripts/relay.sh`, the job is not loaded, or its mode is not the roster's `relay.permissionMode` | `install-relay.sh --job relay --repo <its repo> --permission-mode <roster> --model <its model>`, then `--describe` again: `repaired` only when the program and `loaded=yes` read back; otherwise a bug |
| plugin-record | `installed_plugins.json` names a version `~/.beast/plugin.json` does not | `plugin_root_record <installPath>` (the one writer), before the relay check |
| relay-silent | loaded and right, but no `poll:` line in 6 min, three ticks running | a bug with the last 40 log lines |
| corrupt-mark | relay.log `the mark <file> is corrupt …; delete it` | deletes exactly that `.mark` under `~/.beast/watch/` (watch.sh's own instruction) |
| ws-seats-table | relay.log `workstream <slug> (<ref>): its \`## Seats\` table does not parse; skipped by ws_seats_all …` (watch.sh names it once per message) | a bug per tracking issue with the parser's message and the vocabulary; never edits the issue |
| watch-failed | relay.log `watch failed (exit <n>, named above)` | a bug with the lines before it |
| rate-limit-burst | three `GitHub rate limit at …` lines (watch.sh's backoff start) in one hour | a bug for that hour with the poll and baseline lines around them |
| hook-misfire | a line in `~/.beast/hooks.log` (`<UTC> <hook> block|fault session=<id> <message>`, lib.sh `hook_log`), or a SessionStart fault (`could not decide whether to rejoin`, `could not name this directory's seat`) in a live transcript's tail | a bug per hook and message class (`<hook>/<kind>-<class>`), the excerpt and the installed version in its body |
| stale-board | a stale marker `~/.beast/board/stale/<owner>__<repo>__<login>` (`BEAST-BOARD stale since=<UTC> repo=<owner/repo> assignee=<login> why=<…>`), left by a `decision.sh close`, `pr.sh close` or `publish.sh merge` whose board republish failed after `rate_retry` (a GitHub secondary rate limit, measured 2026-10-22: three bursts in one afternoon) | `board_republish`: `board.sh --assignee <login> --publish --repo <owner/repo>` under `rate_retry`; a success deletes the marker (`board.sh`, the one clearer) and logs `board: repaired`; a failure keeps the marker and its first `since=` for the next tick. Skipped with the other GitHub checks when the quota is low. The close itself already succeeded and exited 0; nobody reruns it |
| weekly | a retired roster row's `~/.beast/watch/<login>/<LABEL>.{json,mark}`; a legacy `~/.beast/watch-*.json` | deletes those relay cache files, each logged |

Not measurable from a machine, so no check: a board page published without a capability (the Cowork tick's), a row that should have been a seat-to-seat message (the decider's board says it).

## Memory

- `~/.beast/watchdog/state.json`: the log offsets (`offsets.relay_log`, `offsets.hooks_log`, `offsets.tx:<session>`), the nudge ledger (`nudges`, pruned after 7 days), the bug ledger and queue (`bugs`, `bugs_queue`, `bug_days`), the row cache (`rows`, pruned after 7 days), counters (`counts`), false alarms and tuning (`falses`, `tune`), the Beast tracking issue (`beast_tracking`). A cache: losing it costs one duplicate nudge at most; bugs stay deduplicated because `watchdog.sh bug` lists the twin's issues.
- One `BEAST-WATCHDOG-NOTES machine=<host> at=<UTC> entries=<n>` comment on the Beast workstream's tracking issue, edited in place by the tick: `<date> GOTCHA|FALSE|TUNE <check> <object> — <one line>`, newest first, at most 60 lines, none older than 30 days. Bookkeeping: the relay never wakes a seat for it (`BOOKKEEPING_FIRST_LINE_RE`), and a wrap-up keeps it.
