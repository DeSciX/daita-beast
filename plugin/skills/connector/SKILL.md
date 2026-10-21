---
name: connector
description: Run the Beast protocol without a shell, through the GitHub connector (Cowork, Claude.ai chat, or any surface with GitHub MCP tools and no Bash) — board, file a decision (new row), assign a row to a seat, request review on a PR, answer, status, ack, inbox, close, revise, resume, the desk (ask, answer, message, desk inbox), and the workstream seat map. Use when a Beast verb is asked for and you have GitHub connector tools but no Bash tool.
---

# connector — the protocol as GitHub connector calls

Same objects, same bodies, same words as the scripts (`docs/protocol.md`); only the transport differs. Each recipe below is numbered; a verb skill without a shell points here by the recipe's name. What a recipe cannot do is said in it, and the list at the end names the acts no recipe covers.

## 0. Before the first recipe

**Tools.** The claude.ai GitHub connector's display name is `github`; its tools appear as `mcp__github__<name>` in claude.ai and Cowork, and as `mcp__claude_ai_github__<name>` in a Claude Code session that has the claude.ai connector attached (seen 2026-10-19). The recipes use: `get_me`, `search_issues`, `search_pull_requests`, `issue_read` (`method: get | get_comments | get_labels`), `issue_write` (`method: create | update`; an interactive tool, consent per call), `add_issue_comment`, `update_issue_comment`, `get_file_contents`, `list_commits`, `create_or_update_file`, `create_branch`, `create_pull_request`, `merge_pull_request`, `search_repositories`. Take argument shapes from the tool definitions in your list, never from memory; a tool named here that your list lacks stops the recipe that needs it, naming the tool. `search_issues` `query` honours GitHub qualifiers (`is:open label:decision assignee:<login>`, the comma in `label:` is OR; measured 2026-10-12) and is scoped to is:issue (its definition, 2026-10-19): it never returns a pull request. Every recipe that reads rows labelled `needs-review` therefore makes the same query twice, `search_issues` for the issues and `search_pull_requests` for the PRs, and merges the two by `html_url`; a recipe that has only one of the two tools stops, naming the missing one.

**Access.** Fetch one known private issue by number through the connector (`issue_read`, `method: get`); a denial or not-found is a connector-access problem (`docs/connector-access.md`), never a reason to retry with another query. Where a recipe says "all repos", query without a repo filter and add one `user:<owner>` term per owner of the roster (`roster_owners`). Where the connector cannot do a step (no pin, no Projects, no label creation, no milestone creation), say so and stop at that step.

**The roster.** Every recipe that writes reads `.beast/roster.json` of the home repo first: `get_file_contents` `{owner, repo, path: ".beast/roster.json"}`. The home repo is the roster's `repo`; the decider is `people[]` with role `owner`; the seats are `seats[]` (id `<github>/<label>`, workstream `<workstream>`). The **coordination write guard** (what `coord_write_guard` in `lib.sh` does): a coordination write (a row, a comment, a label, an assignee, a body edit, a `## Seats` row) goes only to a repo that is private and not public-intended. The target is refused when it equals the roster's `publishes_to`, when its name or its owner is listed in the roster's `public_intended` (case-insensitive), or when `search_repositories` with query `repo:<owner/repo>` returns `private: false`. The refusal is the message, and nothing is written:
```
refused: <owner/repo> is <listed in the roster's public_intended (<entry>) | the roster's publishes_to | public on GitHub>. Coordination stays private: write in the roster's repo <twin>; a public repo receives only publishes.
```

**Seat ids and tags.** A seat is `<login>/<LABEL>` inside its workstream's artifacts (row labels `seat:<login>/<LABEL>`, acks, status) and `<slug>/<LABEL>/<login>` where workstreams meet (the `## Seats` table key, `BEAST-MSG from= to=`). The comment tags and their shapes are owned by `lib.sh` and the scripts (`BEAST-ACK` ack.sh, `BEAST-STATUS` status.sh, `BEAST-NOTES` notes.sh, `BEAST-ASK` / `BEAST-ANSWER` / `BEAST-WITHDRAW` / `BEAST-MSG` desk.sh and `desk_parse`, the close comment `row_close_comment`, the amend line `AMEND_LINE_RE`); each recipe quotes the one line it writes. A `BEAST-COWORK` line (the `cowork-tick` skill's stamp on the pinned board issue) is bookkeeping: never an event, never a message.

## 1. board

A decider's open rows (decision issues and PRs): `search_issues` `{query: "is:open label:decision assignee:<login>", perPage: 100, sort: "updated", order: "desc"}` and `search_pull_requests` `{query: "is:open label:needs-review assignee:<login>", perPage: 100, sort: "updated", order: "desc"}`. A row whose `html_url` contains `/pull/` is a PR: render its title, its `## Unblocks` and `## Recommendation` (a PR missing one is reported as malformed, never patched) and its phrase (the first quoted phrase of a `## Approve with` section of its body, else `approve`). Any other row is a decision: render its six sections (`## Decision`, `## Unblocks`, `## Waits`, `## Recommendation`, `## Approve with`, `## Record`); a body missing one is reported as malformed, never patched. Desks carry neither label and never appear. The decider's page is the board artifact, published from the plugin's template by `/daita-beast:board-ui` (`docs/board-ui.md`); the pinned issue "Pending decisions (generated)" is written by a shell seat (`board.sh --publish`), never here.

## 2. decision (new row; "file a decision")

You are the blocked seat, filing BEFORE you ask for the word. Search the home repo's open `decision` issues first (`search_issues` `is:open label:decision repo:<home>`); a question another seat carries is their row, and a row with your title already filed is yours (a rerun). Then one `issue_write` `{method: "create", owner, repo: <the roster's repo>, title: "Decision: <plain question>", body, labels, assignees: [<the decider>], milestone}`:

- **body:** exactly the template `plugin/templates/decision.md` (read it with `get_file_contents` on `DeSciX/daita-beast`, main, so the `## Approve with` paragraph is the template's own): its six sections, every one non-empty, `## Approve with` opening with the exact phrase in double quotes (one phrase, no `|`: a choice between options is a desk ask), `## Record` citing a dated record by repo and commit id or the comment URL that holds the words. When the row decides another repo, the last line of `## Decision` is `Decides: https://github.com/<owner/repo>`. Each dependency is a line `Waits on: <login/LABEL | owner/repo#N>` at the end of `## Waits`. The row's content is inline or a URL at a commit, never "see session" or a path on one machine.
- **labels:** `decision`, your own `seat:<login>/<LABEL>` (the filing seat's, always) and one per other seat that waits on it, and `hands` when only the assignee can perform the act. A label the repo lacks cannot be created here: the create fails naming it, and a shell seat adds it (`decision.sh new --seat` creates seat labels).
- **milestone:** required when the repo has an open milestone. The connector lists no milestones: take the number from the `milestone` field of any open row of that repo (`search_issues` `is:open repo:<home>` with `fields: ["milestone"]`); when no row carries one, ask a shell seat for `milestone.sh list` and stop.

Then one `add_issue_comment` on the new row, your seen ack as filer, exactly `BEAST-ACK seat=<login>/<LABEL> at=<UTC now> state=seen next=filed; waits on the decider's word`: the filer is current on its own row, and the relay never sends the filing back to it.

Refuse a title that is not a plain question, a section left empty, a phrase with `|`, and any repo the write guard refuses.

## 3. assign (a row to a seat)

The decider, or a seat at a seam, puts a row in a seat's queue. `<issue>` is `owner/repo#N` or its URL; `<seat>` resolves through the roster to `<login>/<LABEL>` (and its workstream slug for the composite). Both the issue's repo and the write pass the guard.

1. `issue_read` `{method: "get_labels", owner, repo, issue_number}`; refuse when `seat:<login>/<LABEL>` is already there ("<seat> already waits on <issue>") and stop.
2. `issue_write` `{method: "update", owner, repo, issue_number, labels: [<every current label>, "seat:<login>/<LABEL>"]}` (update replaces the label set: pass the full list). A missing label fails naming it; a shell seat creates it.
3. One comment, `add_issue_comment`, whose first line is exactly
   ```
   BEAST-MSG from=<your composite id, or your login when you hold no seat> to=<slug>/<LABEL>/<login> re=<owner/repo#N> blocking=no
   ```
   then one line saying what the seat does with the row. This comment is the news that wakes the seat: the relay turns a comment that is not seat bookkeeping into the seat's `UPDATED` event, and the seat's inbox recipe lists the row until it acks.

Never assign by changing the assignee: the assignee is the decider whose word the row needs; the seat label is who waits.

## 4. pr (request review)

You have what the merge unblocks and your recommendation, both inline (no "see session", no local path); without either, stop before any write. On the PR (the issues endpoints serve PRs): first `issue_write` `{method: "update", body: <the PR body with a `## Unblocks` section and a `## Recommendation` section holding the two texts, each replacing a section of that heading when the body has one>}`, then `issue_write` `{method: "update", labels: [<current labels>, "needs-review", "seat:<login>/<LABEL>"], assignees: [<the decider>]}`. A GitHub review request is refused while every seat posts as the PR's author, so none is made. Then one `add_issue_comment`, your seen ack as requester: `BEAST-ACK seat=<login>/<LABEL> at=<UTC now> state=seen next=review requested; waits on the decider's word`. If the connector cannot add labels or assignees, say so and hand it to a shell seat (`pr.sh request`).

## 5. answer

You are the assignee, or relaying their exact words with attribution: one `add_issue_comment` on the issue or PR, nothing else: the `## Approve with` phrase (a bare `approve`/`approved` counts the same there), or `<phrase> — <comment>`, or `revise: <what to change>`, or `reject: <reason>`. Never close, label or edit on an answer; the hearing seat does. On an amended row (a comment whose first line matches `Amended at <UTC>: `), an approval older than the newest amend line no longer counts: answer again after it. While your newest answer is a `revise:` with no amend line after it, the row was not revised: an approval does not close it (recipe 10); reply, revise or reject.

## 6. status

`add_issue_comment` on the workstream tracking issue, first line exactly
```
BEAST-STATUS seat=<login>/<LABEL> at=<UTC> state=working|blocked|done|handoff next=<act>
```
then a blank line and the evidence (what ran, exit codes, links; never a story). Post at a blocker, a completion, a seam or a handoff, never a tick. A `handoff` is read back by recipe 9.

## 7. ack

Your consumption state on a row or your desk; nothing local: one `add_issue_comment` whose first line is exactly
```
BEAST-ACK seat=<login>/<LABEL> at=<UTC> state=seen|executed|blocked next=<the act>
```
evidence below. `seen` when read, `executed` when done, `blocked` with what it waits on. Only for your own seat; nobody acks for another.

## 8. inbox

Each wake; computed, the same on every surface. `search_issues` and `search_pull_requests` (step 0), each with `is:open label:decision,needs-review label:"seat:<login>/<LABEL>" user:<owner>…` and `is:closed label:decision,needs-review label:"seat:<login>/<LABEL>" closed:>=<7 days ago> user:<owner>…` (one `user:` term per roster owner); for each row `issue_read` `get_comments` (pages of up to 100 until a short page). The row's latest event is the newest of its creation, the assignee's newest answer-form comment (recipe 5's four forms), and its close; a close comment "Closed by seat X at T." is X's `seen` ack at the issue's closed time. The row is yours to act on when your newest `BEAST-ACK` is older than that event (or absent). Act, then ack (recipe 7). Then the desk inbox (recipe 11).

## 9. resume

Your state lives on GitHub. On the workstream tracking issue (recipe 12 finds it by `workstream` + `ws:<slug>`), `issue_read` `get_comments`: your newest comment whose first line starts `BEAST-STATUS seat=<login>/<LABEL> ` is your handoff; the one comment whose first line is `BEAST-NOTES seat=<login>/<LABEL>` is your notes (edit it in place with `update_issue_comment`; create it once when absent). The seat map is the issue's `## Seats` table. Then recipe 8. Nothing is rebuilt from a session or a memory file.

## 10. close (on the word)

You are the hearing seat. One `add_issue_comment`, exactly the shape `row_close_comment` writes:
```
Closed on the word, verbatim: "<the words>"

Record: <comment URL or repo commit>. Closed by seat <login>/<LABEL> at <UTC>.

BEAST-ACK seat=<login>/<LABEL> at=<UTC> state=seen next=<the act>
```
Before an approving close, read the comments (`issue_read` `get_comments`): when the assignee's newest answer-form comment is a `revise:` and no comment whose first line matches `Amended at <UTC>: ` is newer, stop: "the decider asked for a revision at <url> and the row was not revised: the seat runs decision.sh revise first" (recipe 13). A reject still closes. (`Rejected on the word, verbatim` on `reject:`, with the label `rejected` added through `issue_write` `update` with the full label list), then `issue_write` `{method: "update", state: "closed", state_reason: "completed"}` (`not_planned` on reject). **PR close:** on approve, `merge_pull_request` first; if GitHub refuses, report the refusal and stop, nothing commented; then the same close comment. On reject, the comment, the label `rejected`, and close the PR unmerged (`issue_write` `update` `state: "closed"`). The pinned generated board is republished by a shell seat on its next close; say so.

## 11. desk (ask, answer, message, desk inbox)

One issue per seat, `Desk: <login>/<LABEL>`, labels `desk` + `seat:<login>/<LABEL>`, in the seat's roster repo; find it with `search_issues` `is:issue label:desk label:"seat:<login>/<LABEL>" repo:<seat repo>` (exactly one; two is named and stops). Creating one is a shell act, `desk.sh open`. Its body is generated by `desk.sh publish`; never edit it, say a shell seat republishes. The test for a desk ask instead of a board row: a question you would ask a developer across the desk, not one a team would put on a PR or an issue for the lead's approval.

- **Ask:** read the desk's comments, n = the highest `BEAST-ASK n=` + 1, then `add_issue_comment` with the first line exactly `BEAST-ASK n=<n> seat=<login>/<LABEL> at=<UTC> milestone="<title>"` (the milestone field is required when the desk's repo has an open milestone, and names one; an ask without one is written without the field), the question lines, then optionally `options: a | b | c`, `default: a`, and one `Waits on: <login/LABEL | owner/repo#N>` line per dependency.
- **Answer** (the decider, or relaying their exact typed words): `BEAST-ANSWER n=<n> <option or text>`; when relaying words typed to a seat's session add the line `(words typed to <login>/<LABEL>'s session, verbatim)`. Only an open ask is answerable. Withdraw your own ask with `BEAST-WITHDRAW n=<n>`.
- **Message:** on the recipient's desk, first line exactly `BEAST-MSG from=<slug>/<LABEL>/<login> to=<slug>/<LABEL>/<login> re=<owner/repo#N | url | none> blocking=no at=<UTC>` (the one shape, `MSG_HEADER_RE` at `plugin/scripts/lib.sh:2013`; `desk.sh msg` writes it, `desk_parse` and the board page read it; both ids are the composite, the seat's roster row's `workstream` giving the slug; `blocking` is always `no`: a seat that needs the decider's word files a row), then the body. The decider may just comment: a plain comment by an assignee of the desk is a message. A body whose first line starts `BEAST-` is refused: it would be read as a protocol line.
- **Desk inbox:** your newest `BEAST-ACK seat=<login>/<LABEL>` on your desk is the cut; list every `BEAST-ANSWER` to an open ask (by an assignee, or carrying the typed-words line) and every message (`BEAST-MSG … to=<you>`, or a plain assignee comment) created after it. Act, then ack on the desk (recipe 7).

## 12. workstream (seat map)

The seat map of workstream `<slug>` is the `## Seats` table on its tracking issue, in the master repo; this recipe adds or removes one row and re-renders the master's CLAUDE.md block. A seat's roster row and its home stay shell acts (`seat.sh new --agent`, `seat.sh retire`): say so, and that the roster row is made first.

1. **Find the issue:** `search_issues` `is:open label:workstream label:"ws:<slug>" user:<owner>…` (one `user:` per roster owner). Exactly one: 0 or 2+ is refused naming them ("workstream <slug>: <n> open issues labelled workstream + ws:<slug>: <urls>"). Its repo is the master; it passes the write guard.
2. **Read the body:** `issue_read` `{method: "get"}`. The table is the section between the line `## Seats` and the next `## ` line (`section` in `lib.sh`). Its first two lines are the header
   ```
   | Seat | Repo | Home | Agent | Account | Address | Seen |
   |---|---|---|---|---|---|---|
   ```
   and each row is one seat. The parser (`ws_seats_parse`) reads the first four cells and ignores the rest: `Seat` is `<login>/<LABEL>`, `Repo` is a private `owner/repo`, `Home` is one of `checkout`, `worktree <branch>`, `wrapper`, `subdir <dir>`, `Agent` is the agent name (`daita-beast:seat` or a file in the seat repo's `.claude/agents/`). A body without `## Seats` is refused naming the issue. A `## Seats` section holding anything but this table (prose or a list from before the schema, a header that differs) is refused naming the line, here and in the shell alike: `seat-add` never rewrites prose. The reset is one hand edit of the body (`issue_write` `update`, the section's content replaced by exactly the two header lines above and nothing else, every other byte the same), then the first add.
3. **Change one row.** Add: refuse when `Seat` is already in the table; append
   ```
   | acme/DEVX | acme/widgets-dev | worktree seat/DEVX | devx-evangelist | — | — | — |
   ```
   (the three cells the parser ignores are `—` until the seat's `BEAST-ADDRESS` comment fills them, by `seats.sh record`). Remove: delete the row whose `Seat` matches; refuse when none does. Then `issue_write` `{method: "update", body}` with the body changed only inside that section: every other byte the same.
4. **Re-render the master block.** `get_file_contents` `{owner, repo: <master>, path: "CLAUDE.md", ref: "refs/heads/main"}`: the text and its blob `sha`. The block is the text between the lines `<!-- beast:workstream begin <slug> -->` and `<!-- beast:workstream end <slug> -->`; refuse when the pair is absent ("no workstream block for <slug> in <master>/CLAUDE.md: a shell seat runs `workstream.sh render <ref>` once"). Replace what lies between the markers with the rendered block (`plugin/templates/workstream-block.md` on `DeSciX/daita-beast` main, its `## Seats` table being the issue's, verbatim), nothing else. Then either
   - `create_or_update_file` `{owner, repo, path: "CLAUDE.md", branch: "main", sha, content, message: "workstream <slug>: seat map (<add|remove> <id>)"}`; a sha conflict (the file moved) is reported and the step is rerun from the fetch, never forced; or, when the person wants a PR,
   - `create_branch` `{branch: "beast/ws-<slug>-seats", from_branch: "main"}`, the same `create_or_update_file` on that branch, then `create_pull_request` `{title: "workstream <slug>: seat map", head, base: "main"}` and recipe 4 on it.

`workstream.sh new` (a Project, milestones, the tracking issue) is a shell act.

## 13. revise (answer a `revise:` by revising the row)

You are the hearing seat and the assignee's newest answer-form comment on the open row is `revise: <what to change>`; any other standing answer is refused ("not a revise: decision.sh revise answers a revise only"). A comment-only reply is not a revision. Two writes, in this order:
1. `issue_read` `{method: "get"}`, then `issue_write` `{method: "update", body}` with only the sections the revise changes rewritten (each the text between `## <Section>` and the next `## `); every other byte the same. A new phrase replaces the quoted phrase in `## Approve with` and keeps its paragraph. Run recipe 2's checks on the result (six non-empty sections, one phrase, no `|`, the content inline).
2. One `add_issue_comment` whose first line is exactly the amend line (`amend_line`, `AMEND_LINE_RE` in `lib.sh`), then a short summary:
   ```
   Amended at <UTC>: revised after <the revise comment URL>; changed: <the sections, in body order, comma-separated>

   The row's body is revised in answer to the decider's revise (by seat <login>/<LABEL>). Approve with "<the phrase>", or answer again; an approval given before this line no longer counts.
   ```

## Cannot be done here

Said rather than imitated, and handed to a shell seat as one line with the issue URL: install labels or templates in a repo (`init-repo`); open a workstream, its Project or its milestones (`workstream.sh new`, `milestone.sh new|move|close`); create a seat, its roster row or its home, or retire one (`seat.sh`); record a session's address (`join`, `seats.sh record`: there is no Claude Code session here; the map is read from the `## Seats` table, recipe 12); open a desk (`desk.sh open`); run the relay; generate the ledger, a report, or the pinned board issue (`board.sh --publish`).
