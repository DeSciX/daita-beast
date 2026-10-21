# Learnings

Each lesson is a rule, why it holds, and the evidence: a measurement, a fixture or a defect found in use, written without private names. The rule is what the code does today; the citation says where. Where the evidence is a sequence of versions, the commit history of the plugin's private twin holds it.

## 1. GitHub is the only state

**Rule.** Every durable fact is a GitHub object or comment. A seat's inbox is computed from the rows' acks (`decision.sh inbox`, which takes no options: "it is computed from the rows' acks, nothing local"). The relay is an optimization, delivery is at-least-once, and a seat de-duplicates by issue URL.
**Why.** A seat moves between machines and surfaces (local, cloud, Cowork) and loses its session on every compaction; anything held locally is wrong on the next surface.
**Evidence.** An earlier inbox swept closes since a machine-local watermark; it differed per machine, and a seat that missed an `UPDATED` line never saw the row, so a second pass for rows the assignee had commented on had to be added. Replacing the watermark with per-seat `BEAST-ACK` comments (read by `lib.sh::seat_acks`, compared with `lib.sh::row_events`) made the inbox identical on every surface. The relay overlaps its search window by an hour, so it re-reads rows by design; an `UPDATED` whose last comment is the seat's own is its echo.

**Rule.** A row a seat cannot find by label does not exist. `decision.sh new` creates the `decision` and `seat:` labels in a repo on first use (`lib.sh::label_ensure_template`, `lib.sh::seat_label_ensure`).
**Evidence.** Rows filed in two repos before their labels existed were invisible to the board and the relay.

**Rule.** A seat's address is a fact of the seat, published on GitHub (its `BEAST-ADDRESS` comment, `seats.sh record`), not of the machine that minted it; `~/.beast/sessions.json` is a cache keyed by the identity.
**Why.** Two seats on two machines, or on two Claude accounts, cannot message each other directly however fresh the address: `seats.sh address` decides direct or desk from the comment's account, machine and age, and the relay sends only on a direct path.

## 2. Relay cost

**Rule.** One search per tick for every seat together, from a high-water mark minus an hour (`watch.sh::poll`, `WATCH_OVERLAP_S=3600`).
**Why.** The search API has no conditional request and its own quota (30 a minute); per-seat searches multiply both. The index lags writes, so the window must overlap.
**Evidence.** Measured: one comment took 10 s to appear in search; a decision issue was still absent from an `updated:>=` search six minutes after it was created. An unscoped `label:decision` search competed with all of GitHub for its result window and dropped a live fixture, so the search is scoped to the roster's owners (`lib.sh::roster_user_terms`). The first design had each seat hold its own polling monitor; one shared search replaced it.

**Rule.** Every GET goes through the ETag cache (`lib.sh::gh_request`); search cannot be conditional and is never cached between runs (within one run it is memoized, lesson 15).
**Why.** A 304 Not Modified costs nothing from the 5,000-an-hour REST quota that every seat, the relay and the board of one login share.
**Evidence.** With `BEAST_CALL_LOG`: `board.sh` cost 307 core requests cold and 0 warm (318 answered 304; only its 3 searches were charged), with byte-identical output; `decision.sh inbox` for five seats cost 15 to 145 cold and 0 warm. `gh api -i` on a 304 prints the status with an empty body and exits 1, and the core `used` count did not move. Search answers `Cache-Control: no-cache` with no ETag.

**Rule.** Bookkeeping never wakes a seat: one list of first lines, `lib.sh::BOOKKEEPING_FIRST_LINE_RE` (an ack, a status, the notes, an address, the Cowork tick's stamp, the watchdog's lines and notes, a close comment, a publish `Amended at` line), is never an `UPDATED` (`watch.sh::poll`, `lib.sh::comment_is_bookkeeping`). Label and body edits are silent. Only `BEAST-EVENT` lines reach the messenger (`relay.sh`).
**Why.** Every wake costs the receiving seat a turn; acks would otherwise wake every other seat on the row, and their acks would wake the first; an address refresh at every join and a stamp every 15 minutes would wake every seat on the pinned issue.
**Evidence.** A transient search failure once woke a messenger with nothing to send, because the watcher's own notes reached it; they now go to stderr and the relay filters to event lines.

**Rule.** The messenger runs in the seats' permission mode (`relay.sh --permission-mode`, the roster's `relay.permissionMode`).
**Why.** A receiver holds a message from a sender in another permission mode and never tells a one-shot sender.
**Evidence.** Measured: 23 lines reported sent to a bypass-mode seat by a default-mode messenger; none was delivered. The messenger now reports `queued`, never "delivered".

**Rule.** A scheduled job names a fault once and backs off a rate limit; it never dies mislabelled and never drops the other workstreams. The relay stops sending to an address the messenger could not reach twice (`relay.sh`, `~/.beast/relay-unreachable.json`), until the seat records a new one. `watch.sh` names a GitHub rate limit once and backs off (exit 75, `poll: skipped`); a workstream whose `## Seats` table does not parse is named once per message (`lib.sh::fault_once`) and skipped alone.
**Why.** Each tick is a new run: a fault logged by every tick is noise no one reads, a dead address costs one Haiku run per event tick and delivers nothing, and a usage line in place of the real error sends the reader the wrong way.
**Evidence.** Measured in one machine's relay log on 2026-10-20: a secondary-rate-limit 403 on the workstream search made `ws_seats_all` return no seats and `watch.sh` die with its usage line, logged `watch failed`; one workstream's malformed `## Seats` row (a Home cell outside the vocabulary) was logged on 112 consecutive ticks (720 a day at 120 s); two fresh-but-dead addresses were answered "no agent named … is reachable" tick after tick, one for about 18 hours. Gated in fixtures: the 403 tick exits 0 naming the limit and the next tick searches nothing; the bad table is logged once over three ticks while the other workstream's events are still sent; the third event to the dead address starts no messenger, and a re-recorded address is sent again.

**Rule.** The machine watchdog measures with a shell checklist and judges with a model only when a finding needs `ListAgents`; a quiet tick makes no search and starts no session (`watchdog.sh`). It re-stamps a live seat's stale address only after `ListAgents` lists it and the seat's cached cwd is its home (`seats.sh touch`, which claims no session), nudges at most once per seat, check and object every 2 hours, files bugs only on the plugin twin after listing its `watchdog` issues, and runs under `BEAST_WATCHDOG=1`, where every plugin script but two refuses (`lib.sh::watchdog_guard`).
**Why.** The 24-hour freshness rule approximates "recorded after the seat's newest session start"; a live seat whose address aged past it heard nothing while it worked. The relay delivers an event once; a seat that missed it had no second push. One login posts for every seat and the decider, so a watchdog that could comment could answer.
**Evidence.** Measured on 2026-10-20: a live seat's `BEAST-ADDRESS`, recorded the day before, went stale while its session ran; ten relay ticks of its events (a decision and its desk) were logged `no direct address from this machine` over 2 hours 24 minutes, until the seat re-recorded. Gated in fixtures: a quiet tick costs one `rate_limit` call and one conditional read (304) per tracking issue, no search, no session; the stale address of a live seat is re-stamped (only `at=` moves, `sessions.json` unchanged) and a touch with another address or a cwd that is not the home is refused; an unacked row past the 15-minute grace gets one tagged nudge and a second tick within 2 hours none; under `BEAST_WATCHDOG=1` `ack.sh`, `decision.sh close`, `desk.sh answer`, `notes.sh`, `seats.sh record` and `status.sh` all die, and a tick over a row whose text asks the watchdog to approve writes nothing on that row.

## 3. Never a silent cap

**Rule.** Every list is read to its end: `lib.sh::gh_get_all` follows full pages, `lib.sh::search_issues` reads every page and fails loud past the search API's 1000, and refuses a second argument ("a result cap would drop rows silently").
**Evidence.** A 100-row cap silently dropped 21 closes from the board's decided table once a bulk comment rewrite moved those rows up the updated order.

**Rule.** The published board body stays under GitHub's 65,536-character issue-body limit by a budget (`board.sh`, `BOARD_BUDGET=60000`): open rows and decided rows some seat has not acked are always kept; acked decided rows fill the rest newest first; a line counts the rest; if open and unacked rows alone exceed the budget, the publish fails loud.
**Evidence.** A published board reached 61,838 characters.

**Rule.** On the board page, a search reply goes through one reader (`itemsOf`) and a comment thread through another (`readComments`, pages of 20 until a short page).
**Evidence.** The page's Decided tab showed 100 of 150 rows with no notice, and a desk with 28 comments read as zero comments. Both readers now fail loud or say "showing the newest N of M".

## 4. GitHub timing facts

All measured; each shapes code.

| Fact | Consequence in code |
|---|---|
| The search index lags a write by seconds to minutes, including a close and a label | `watch.sh` overlaps an hour; `board.sh` re-reads every candidate live and drops closed ones (a board once said "5 open" three seconds after a close); `lib.sh::workstream_candidates` re-reads every search hit live and keeps only an open issue carrying both labels |
| The issues list lags a create by about 6 s (absent at +0 s, listed at +6 s) | `lib.sh::issues_list_shows` waits up to 60 s after a create; a desk opened twice one second apart once minted a duplicate; finding the board issue by search once minted duplicate boards, so `board.sh --publish` uses the list API |
| Editing a comment does not bump the issue's `updated_at`; adding or deleting one does | no read is skipped on an unchanged `updated_at` (an edited answer would be served stale); the Cowork tick's "moved" test misses an edited answer until the next new comment, and says so |
| `since=` on comments shows edits but not deletions | comments are never read with `since=`; per-page ETags already charge only changed pages |
| A milestone `due_on` of `T00:00:00Z` is stored as the previous day | `lib.sh::milestone_write` writes `T12:00:00Z` and dies when the stored date differs |
| A renamed or transferred repo's old name resolves to the new repo | `publish.sh::public_info` checks the name GitHub answers with |
| A contents-API PUT with a stale `sha` is a 409 | `lib.sh::ws_block_write_remote` reads the sha first and exits 1 on the conflict, writing nothing; the rerun re-reads |

## 5. The decider's words stay private

**Rule.** A public product has a private twin; all rows, desks, status, notes, acks, addresses, seat maps and master blocks live there. `lib.sh::coord_write_guard` refuses every coordination write to a public or public-intended repo, with no override; `publish.sh` is the only writer to the public repo (`publish.sh::public_push`, `publish.sh::public_send`). `seat.sh new` and `workstream.sh seat-add` refuse a public seat repo before any write (`lib.sh::repo_public_why`).
**Why.** Close comments quote the decider verbatim, and a repo's visibility can change later.
**Evidence.** Rows had been filed and closed in repos that were public or intended to be; their close comments carried the decider's words. An interim scheme put a pointer in the public close comment and the words in a private record; it was deleted in favor of twins, which remove the case instead of patching it.

**Rule.** The scrub gate (`lib.sh::scrub_patterns`, `lib.sh::scrub_scan`) runs on every publish commit, its message, the PR body and release notes. Classes: private repo `owner/name`; private bare name (5 characters or more, exact case, minus `scrub_allow`); local home paths; filled-in `BEAST-` lines; records-directory paths; 5-word stretches of closed-row words; roster regexes; secret-shaped and private path names.
**Why.** What leaves the twin is the only thing that must never carry a private fact, and only a mechanical check holds across every seat.
**Evidence.** A private repo of an organization passed as a bare name until the scrub listed every private repo of every owner the roster names; a listing that fails now dies instead of passing.

**Rule.** Removing words from GitHub means deleting the comment (and posting a clean one if the content is needed), never editing it.
**Why.** GitHub keeps every earlier revision of an edited issue body or comment readable in its edit history, and no API deletes a revision.
**Evidence.** After a repo was made public, an issue body rewritten earlier to remove quoted words still showed them in its edit history; each old revision had to be deleted by a repo admin in the web UI.

**Rule.** An approval no newer than a publish row's latest `Amended at` line does not count (`lib.sh::row_answer_url`, `lib.sh::row_amended_at`); `publish.sh merge` on an amended row takes the approval only from the decider's comment.
**Why.** The decider approved what the amend replaced.

## 6. The board works only if seats file before asking

**Rule.** Anything a seat waits on from the decider is a row filed with `decision.sh new` before the seat asks, and stays open until the word. `decision.sh record` (file and close in one act) is only for a significant word already given in a session before any row existed. A minor word goes only into the repo's dated record. One check holds it: `lib.sh::ask_inline_check` makes `decision.sh new`, `record` and `desk.sh ask` refuse a question that points elsewhere for its substance ("see session", "as discussed", a local path).
**Why.** A record-and-close row is never pending, so the decider's board never shows it as a question; a question asked in a session or a chat is invisible to the decider's one view.
**Evidence.** In one repo, 19 of 66 decision rows were closed within two minutes of filing, so they never appeared as pending. A license carve-out question existed only in one seat's session until it was found there.

**Rule.** Every question is answerable from the board alone: the content inline, or a link to a file at a commit.
**Why.** The board page's Context button fetches files linked by full GitHub blob URL; a record cited as free text is not fetched (`docs/board-ui.md`, Context). A row is built from the current end of the record it cites, re-read at filing time.

**Rule.** One exact approving phrase per row; `decision.sh new` refuses a phrase carrying `|`. A choice between options is a desk ask with `--options`.
**Why.** An answer is matched on its first line against the one phrase (`lib.sh::answer_kind`, the page's `answerKind`), and the board's Approve button posts that phrase. A desk ask carries options as buttons.
**Evidence.** A row whose `## Approve with` held no quoted phrase made the event reader (`lib.sh::row_events`) die; it now names the row instead (`lib.sh::row_phrase`), and `new` refuses such a row before filing.

**Rule.** A seat-to-seat line never waits on the decider: its tag carries `blocking=no` always (`lib.sh::MSG_HEADER_RE`), and a seat that needs his word files a row.
**Why.** A message between seats that silently waited on the decider would be a question off the board.

## 7. Seating sets the root

**Rule.** A session seats with `join.sh <SEAT>` from any directory and then works in the seat's home: every shell command carries `cd <home> &&` or uses `git -C <home>` and absolute paths (`permit.sh` allows the `cd` prefix before a plugin script).
**Why.** In VS Code every session starts in the launch folder, and the shell returns there after every command.

**Rule.** A VS Code workspace file is found walking up from the launch folder to `$HOME`, and counts when it lists the launch folder in any position (`lib.sh::vscode_workspace_folders`).
**Evidence.** The earlier rule (a file in the launch folder or its parent, with the launch folder as its first entry) never found a workspace that listed another repo before the launch folder; from a nested repo of a workspace listed three levels up, the workspace is now found, and from a scratch directory none is.

**Rule.** Auto-memory belongs to the launch folder and is shared by every seat started there (`lib.sh::automemory_dir`); a seat's state lives on GitHub (handoff, notes). `join.sh` triages the folder this session loads: only files and `MEMORY.md` lines restating seat state are listed; lessons, another seat's files and short pointers are not.

**Rule.** One editor window holds every seat; two seats never share a home (`join.sh` dies when `seat.json` names another seat).
**Evidence.** Requiring a separate window per seat was replaced, by the decider's approval on a row, with seating that sets the root inside one multi-folder workspace.

**Rule.** A wrapper home is entered with `claude --add-dir <checkout>`, not `permissions.additionalDirectories`.
**Evidence.** Measured twice, with a negative control: `--add-dir` loads the repo's agents, skills and imported CLAUDE.md; the settings key loads none and the import is denied.

## 8. The live checkout is the live plugin

**Rule.** Builders work in a worktree of the plugin's twin, never in its main checkout; commits reach main by review.
**Why.** The plugin's own seat runs `claude --plugin-dir <twin checkout>/plugin`, so an uncommitted edit in that checkout is live for its hooks and every script it runs; and the roster is read from the main checkout only (`lib.sh::repo_main_root`), so a roster change made in a worktree is not seen there.
**Evidence.** A builder measuring a new license render in a worktree saw `MISS` until main carried the roster change.

**Rule.** No committed file names a machine path: the block's `Scripts:` line is machine-neutral, `seat-hello` prints the path at every session start, and the relay job, `permit.sh` and `install-relay.sh` read `lib.sh::plugin_root` (`$CLAUDE_PLUGIN_ROOT`, else `~/.beast/plugin.json`).
**Evidence.** Every seat's committed block had named one machine's checkout of the plugin as its scripts path, which a marketplace install's `permit.sh` would have refused; the publish scrub's local-path class now catches such a line.

## 9. The board page has one source

**Rule.** `plugin/templates/board.html` on main is the page's only source; a fix is made in the template and republished byte-exact; the live page is never edited alone (`docs/board-ui.md`). The page's first line carries the commit it was published from, so the Cowork tick can tell when main moved.
**Evidence.** A live page edited apart from the template drifted: it read milestone-bearing asks as malformed and their answers as naming no ask, and saved a view setting it never read back. A three-way merge brought its improvements onto the template.

**Rule.** The page's parsers are JS twins of `lib.sh`'s regexes, held equal by `plugin/tests/regex-mirror.test.mjs`, which extracts both from their source files and runs them on one fixture list; the seat-to-seat tag is one of them.

## 10. Connector payload shapes

**Rule.** Accept exactly the shapes measured and fail loud on any other (`board.html::readComments`, `board.html::itemsOf`).

| Shape | Seen |
|---|---|
| `get_comments` inside a page | a bare array |
| `get_comments` in a session | `{comments: […]}` |
| a reply the runtime could not parse as JSON | a string payload |
| a search reply | `{items, total_count}`; `total_count` larger than `items` reveals truncation |

Anything else is `bad_payload` naming the issue, never an empty list. Connector access is per account: a missing set of rows is an app installation gap, tested by fetching one known private issue (`docs/connector-access.md`).

**Rule.** The connector's tool names and argument shapes are taken from the session's tool definitions, never from memory; a name a recipe needs that the list lacks stops that recipe naming the tool (`connector`, step 0).
**Evidence.** The same connector appears as `mcp__github__<name>` in claude.ai and Cowork and as `mcp__claude_ai_github__<name>` in a Claude Code session with the connector attached; its `search_issues` definition changed its wording between two reads.

## 11. Scrub tuning

**Rule.** The words class matches stretches of 5 consecutive words with at least 2 outside a common-word list (`lib.sh::WORDS_MIN`, `WORDS_MIN_RARE`, `WORDS_COMMON`), skips a close whose words are exactly the row's own phrase, and allows the roster's `scrub_allow_words`: a phrase of 5 words or more drops the stretches inside it, a shorter one only makes its words common.
**Evidence.** A builder's first reading of a short allow phrase, "drop every stretch containing the word", would have made a one-word entry a wildcard over any sentence of the decider's that used that word; the control that settled the rule: with one word allowed, a sentence of ordinary words around it is clean, and a sentence that still carries two other closed-row words still hits.

**Rule.** The roster's top-level `vendored` names byte-exact upstream copies once, for the license check and the scrub alike (`lib.sh::roster_vendored`); the scrub skips only the classes that match a private name on their content.
**Evidence.** A twin vendoring a public SDK drew 254 hits, all the package's own public bytes; secrets, local paths and BEAST- lines stay held there.
**Evidence.** A 12-character window flagged ordinary prose: a two-word stretch from one close hit seven lines of unrelated physics text in a seat's generated notes.

**Rule.** Private names shorter than 5 characters are checked only as `owner/name`; `scrub_allow` names bare names that are ordinary words.

**Rule.** Binary files (a NUL byte in the first 8000 bytes, git's own test) are not read for content; each one skipped is named on stderr, and its path name is still checked.

**Rule.** A publish branch is exactly one commit on its public base (`publish.sh::publish_base`).
**Why.** A scan of a longer branch's net diff passes a phrase one commit adds and the next removes, while `request` would push both commits.

**Rule.** The stable contract for another tool is `publish.sh scan` (exit 0 clean, 1 on a hit, 2 on a usage or pattern error), with `--dump-patterns` and `--patterns-file` for an offline run; `lib.sh` is internal.

## 12. License

**Rule.** One canonical source, rendered by a filter (`pandoc/latex-crossrefs.lua`: title as H1, headings and every `\ref` numbered as the PDF prints them, from the source's own `\the<counter>` formats), under one neutral header naming no repo (`license.sh::license_header`). `license.sh check` holds the body byte-equal to the render.
**Why.** Hand copies drift; a reference rendered raw is unreadable.

**Rule.** Every tracked `package.json` and `.claude-plugin/plugin.json` is a manifest, except under `node_modules` and the roster's top-level `vendored` directories (`license.sh::is_wanted`, `license.sh::is_vendored`); `exempt` repos keep their upstream license and a stale exemption fails the audit.
**Evidence.** Checking only the root manifest let a nested published package go unchecked. The fix, every tracked manifest, then stopped a twin that vendors a byte-exact published SDK from preparing any publish, since the vendored manifests are the upstream's; the `vendored` scope followed.

## 13. Gates count only when shown red

**Rule.** A check counts only after it has failed on a negative control and passed on the positive.
**Evidence.** The award-policy gate was accepted on five controls (absent, another repo, a planted placeholder, the wrong token refuse; filled passes). The PreToolUse hook was accepted when a bare plugin script ran in default mode and the same script with a pipe was refused. The relay is accepted only on a fixture's `NEW` and `DECIDED` lines in its log (`relay-installer`). The license filter's test includes the failure on a stray label. The wrap-up gate fixes found a dropped row counted as folded; it now never is. The seat-map parser is accepted on a 3-cell row, an unknown home word, a duplicate seat and a lowercase label each dying naming the line (`plugin/tests/seats-model.test.mjs`).

## 14. One owner per fact, across repos

**Rule.** No roster indexes another repo's seats: a row whose `repo` is not the roster's own is refused (`lib.sh::roster_check_unique`), and the one enumeration of all seats is the workstream issues' `## Seats` tables (`lib.sh::ws_seats_all`).
**Why.** A copy of a seat row in a second roster is a second owner of the fact, and the copies disagree silently.
**Evidence.** An ecosystem index repo had carried every seat's row beside each seat's own; one seat's role string differed three ways across the copies before the peer rows were deleted.

**Rule.** A role is an agent file, never prose in a row: `agent` names `<repo>/.claude/agents/<name>.md` or the plugin's `daita-beast:seat`, checked to exist at seat creation and at every join (`lib.sh::seat_agent_path`); a row carrying `role` is refused naming the key.
**Why.** A free-text role is a fact nothing reads and nothing checks; an agent file is loaded by the session that holds the seat.

**Rule.** The workstream issue is found by its labels (`workstream` and `ws:<slug>`), never stored by number; a row carrying `tracking` is refused naming the key (`lib.sh::workstream_issue`).
**Why.** A stored number is a second owner of "which issue tracks the workstream"; the labels are on the issue itself, and 0 or 2+ open issues with them is a defect named on sight.

**Rule.** The `## Seats` table is parsed by shape with every cell required, and a section holding prose is refused on every surface; the reset to the empty table is one hand edit before the first `seat-add`.
**Evidence.** Every tracking issue's `## Seats` section had been free text; the parser refused each until it was reset by hand to the two header lines, which is what made the table the owner rather than one more rendering.

**Rule.** The plugin a seat runs is the installed one, at the version `plugin.json` says, proved at install (`claude plugin list` equals `plugin.json`, `seat-hello` prints at the next start).
**Evidence.** The marketplace copy of the plugin had been disabled and three versions behind while every committed CLAUDE.md block pointed at one machine's development checkout, so no hook ran for any seat that followed the committed text.

**Rule.** A Cowork session cannot call `ListAgents`, so no address is recorded there: the SessionStart hook on a machine prompts the refresh (`ListAgents`, then `seats.sh record`) and the `seats` skill records it; a Cowork seat is reached by its desk, and the decider's Cowork hears by the scheduled tick, not by a message.
**Why.** An address exists only where a session can be named; a surface that cannot name itself has none to publish.

**Rule.** Which repo holds a seat's desk and milestones has one owner, `lib.sh::seat_repo`: this roster's row when the seat is rostered here, else the Repo cell of its `## Seats` row. A verb naming another seat (`desk.sh msg`, `desk.sh answer`, a `Waits on:` ref) resolves it through `lib.sh::seat_id` and reads or writes in that repo (`lib.sh::desk_find <id> <repo>`); a verb acting as a seat resolves it through this roster only (`lib.sh::seat_rostered`).
**Why.** A desk lives in the seat's own repo; a sender that could name only its own roster's seats could not reach a seat of another repo at all.

## 15. One search per query per run

**Rule.** The first script of a run makes `$BEAST_WS_CACHE`, exports it and deletes it at exit (`lib.sh::on_exit`); `lib.sh::search_issues` memoizes one result per query in it, `lib.sh::ws_seats_all` the one seat table (forgotten by `lib.sh::ws_seats_write`), and `lib.sh::workstream_candidates` reads the run's all-workstreams result instead of searching for one slug. A polling loop clears it before each poll (`lib.sh::run_cache_clear`, `watch.sh`). A 403 with no quota left names the reset time (`lib.sh::gh_request`).
**Why.** The search quota is 30 a minute per login and every seat of a machine is the same login; a run re-asks the same queries many times (the tracking issue of a slug, every open workstream), and a re-ask within a run is no fresher, since the index lags a write anyway.
**Evidence.** Three seats joining within one minute hit the quota, because one join ran 17 searches; with one memo per run a join runs 5 (the stub-gh harness counts them).

## 16. An identity is built by one function

**Rule.** A roster row is read only from a roster that passes `lib.sh::roster_check_unique`; a checkout whose roster fails it is named once on stderr and not searched (`lib.sh::seat_homes_on_machine`), and the sessions cache takes no key that is not `<slug>/<LABEL>/<login>` (`lib.sh::sessions_key_check`).
**Why.** An identity composed by hand from a row's fields is a second owner of the identity's shape; a row without a workstream then yields an identity with an empty slug, which every later check accepts as well-formed.
**Evidence.** An old-shape roster (no `workstream`) reachable through a VS Code workspace file produced the identity `/<LABEL>/<login>`, because the locator composed ids with `awk` instead of the one validating function; the locator now refuses the failing roster and names it.
