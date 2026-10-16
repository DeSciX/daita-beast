---
name: connector
description: Run the Beast protocol without a shell, through the GitHub connector (Cowork, Claude.ai chat, or any surface with GitHub MCP tools and no Bash) — board, file a decision, request review on a PR, answer, status, inbox, close, and the desk (ask, answer, message, desk inbox). Use when a Beast verb is asked for and you have GitHub connector tools but no Bash tool.
---

# connector — the protocol as GitHub connector calls

Same objects, same bodies, same words as the scripts (`docs/protocol.md`); only the transport differs. Before the first recipe, prove access: fetch one known private issue by number through the connector; a denial or not-found is a connector-access problem (`docs/connector-access.md`), never a reason to retry with another query. The claude.ai GitHub connector's display name is `github` and its tools appear as `mcp__github__<name>` (measured 2026-10-12): `get_me` (your login), `search_issues` (`query` honours GitHub qualifiers such as `is:open label:decision assignee:<login>`, with `perPage`, `sort`, `order`, `fields`), `issue_read` (`method: get | get_comments`), `add_issue_comment` (returns `{html_url, id}`), the create/update issue tool (an interactive tool, consent per call), `get_file_contents`, `search_repositories`. Take argument shapes from the tool definitions in your list, never from memory; another install may name the connector differently. Where a recipe says "all repos", query without a repo filter; where the connector cannot do a step (no pin, no Projects, no label creation), say so and stop at that step.

**Board** (a decider's open rows, decision issues and PRs): search `is:open label:decision,needs-review assignee:<login>` (the comma is OR), newest updated first. A row with `pull_request` set is a PR: render its title and its phrase (the first quoted phrase of a `## Approve with` section of its body, else `approve`). Any other row is a decision: render its six sections (`## Decision`, `## Unblocks`, `## Waits`, `## Recommendation`, `## Approve with`, `## Record`); a body missing one is reported as malformed, never patched. Desks carry neither label and never appear. The decider's page is the board artifact, published from the plugin's template by `/daita-beast:board-ui` (`docs/board-ui.md`).

**File a decision** (you are the blocked seat), before you ask for the word: create an issue in your home repo (the roster's `repo`, always private; never a public repo or one the roster's `public_intended` lists), naming the repo it decides, when another, as the last line of `## Decision`: `Decides: https://github.com/<owner/repo>`: title `Decision: <plain question>`, labels `decision` and `seat:<your login>/<YOUR LABEL>` (`hands` when only the assignee can act), assignee the decider, body exactly the template `plugin/templates/decision.md` with every section non-empty and `## Record` citing a dated record by repo and commit id (or the comment URL that holds the words). Search the repo's open `decision` issues first; a question another seat carries is their row.

**PR request** (a code change for the decider's word): on the PR (the issues endpoints serve PRs), add the labels `needs-review` and `seat:<your login>/<YOUR LABEL>` and the decider as assignee; a review request is refused while every seat posts as the PR's author. If the connector cannot add labels or assignees, say so and hand it to a shell seat (`pr.sh request`).

**Answer** (you are the assignee, or relaying their exact words with attribution): one comment on the issue or PR, nothing else: the `## Approve with` phrase (a bare `approve`/`approved` counts the same there), or `<phrase> — <comment>`, or `revise: <what to change>`, or `reject: <reason>`. Never close, label or edit on an answer; the hearing seat does.

**Status**: comment on the workstream tracking issue `BEAST-STATUS seat=<login>/<LABEL> at=<UTC> state=working|blocked|done|handoff next=<act>` then a blank line and the evidence. Post at a blocker, a completion, a seam or a handoff, never a tick.

**Ack** (your consumption state on a row; nothing local): one comment whose first line is `BEAST-ACK seat=<login>/<LABEL> at=<UTC> state=seen|executed|blocked next=<the act>`, evidence below. `seen` when read, `executed` when done, `blocked` with what it waits on. Only for your own seat.

**Inbox** (each wake; computed, the same on every surface): search `is:open label:decision,needs-review label:"seat:<login>/<LABEL>" user:<owner>…` and `is:closed label:decision,needs-review label:"seat:<login>/<LABEL>" closed:>=<7 days ago> user:<owner>…` (one `user:` term per owner in the roster); for each row read its comments; the row's latest event is the newest of its creation, the assignee's newest answer-form comment (the phrase, `<phrase> — …`, bare `approve`/`approved`, `revise:`, `reject:`), and its close; a close comment "Closed by seat X at T." is X's seen ack at the issue's closed time. The row is yours to act on when your newest `BEAST-ACK` is older than that event (or absent). Act, then ack. Then the desk inbox, below.

**Close on the word** (you are the hearing seat): comment exactly
```
Closed on the word, verbatim: "<the words>"

Record: <comment URL or repo commit>. Closed by seat <login>/<LABEL> at <UTC>.

BEAST-ACK seat=<login>/<LABEL> at=<UTC> state=seen next=<the act>
```
(`Rejected on the word, verbatim` and label `rejected` on `reject:`), then update the issue to closed (reason not planned on reject). **PR close**: on approve, merge the PR first (the connector's merge tool); if GitHub refuses, report the refusal and stop, nothing commented; then the same close comment. On reject, the comment, the label `rejected`, and close the PR unmerged.

**Desk** (one issue per seat, `Desk: <login>/<LABEL>`, labels `desk` + `seat:<login>/<LABEL>`, in the seat's roster repo; find it with search `is:issue label:desk label:"seat:<login>/<LABEL>" repo:<seat repo>`; creating one is a shell act, `desk.sh open`). Its body is generated by `desk.sh publish`; never edit it, say a shell seat republishes. The test for a desk ask instead of a board row: it is a question you would ask a developer across the desk, not one a team would put on a PR or an issue for the lead's approval.
- **Ask**: read the desk's comments, n = the highest `BEAST-ASK n=` + 1, then comment `BEAST-ASK n=<n> seat=<login>/<LABEL> at=<UTC> milestone="<title>"` (the milestone field is required when the desk's repo has an open milestone; it names one), the question lines, then optionally `options: a | b | c`, `default: a` and one `Waits on: <seat id | owner/repo#N>` line per dependency.
- **Answer** (the decider, or relaying their exact typed words): comment `BEAST-ANSWER n=<n> <option or text>`; when relaying words typed to a seat's session add the line `(words typed to <login>/<LABEL>'s session, verbatim)`. Only an open ask is answerable. Withdraw your own ask with `BEAST-WITHDRAW n=<n>`.
- **Message**: on the recipient's desk comment `BEAST-MSG from=<your id> to=<their id> at=<UTC>` then the body. The decider may just comment.
- **Desk inbox**: your newest `BEAST-ACK seat=<you>` on your desk is the cut; list every `BEAST-ANSWER` to an open ask (by an assignee, or carrying the typed-words line) and every message (`BEAST-MSG … to=<you>`, or a plain assignee comment) created after it. Act, then ack on the desk (`BEAST-ACK seat=<you> at=<UTC> state=seen next=<act>`). The generated board is republished by a shell seat on its next close; you may not have a tool to pin or edit it, say so.

**Cannot be done here**, and is said rather than imitated: install labels or templates in a repo (init-repo), open a Project (workstream), run the relay, generate the ledger or a report. Hand those to a shell seat as one line with the issue URL.
