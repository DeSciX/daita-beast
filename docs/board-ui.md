# The decisions board in Claude.ai — page spec (H0)

A published artifact the decider opens in claude.ai. Its Board tab holds every open decision issue and every pull request that needs the decider's review, one collapsible card each, with three answers: first the rows waiting on the decider, then, folded below, the rows already with a seat, grouped by the seat that waits. Above the groups, a strip of desks (one per seat) counts each seat's open asks and opens the seat's drill-down. It reads and writes GitHub through the viewer's own GitHub connector (the `mcp` capability), so permissions are the viewer's and nothing is hosted. The relay on the owner's machine turns a posted answer into the seat's `BEAST-EVENT`.

## Build it from a claude.ai session that has the GitHub connector

This page is published from a claude.ai (or Cowork) session where the GitHub connector is attached, because that session can read the connector's tool names and argument shapes; a Claude Code session without the connector cannot and must not guess them. Prompt for that session:

> Load the artifact-capabilities skill. Read the GitHub connector's tools (list/search issues, get an issue, create an issue comment) and their argument shapes from this session's tool definitions. Then build and publish the page specified in the daita-beast plugin's `docs/board-ui.md` with `capabilities: {mcp: {servers: [{server: "<the GitHub connector's display name>", tools: [<the exact upstream tool names you used>]}]}, user: {}}`. Exercise it once: list my open decisions, and post an answer on one fixture decision (title starting "FIXTURE") only.

## Data

Two `search_issues` calls, both for the viewer's login from `get_me`, across every organization:

| Search | Query | When | Feeds |
|---|---|---|---|
| Open | `is:open assignee:<login> label:decision,needs-review,desk` (a comma in `label:` is OR; issues and PRs) | at load, then every 2 min | split by label: an issue carrying `desk` and neither row label is a desk (the desks strip and the drill-down); anything carrying `decision` or `needs-review` is a row of the Board tab (a row that also carries `desk` breaks the protocol; it is shown as a row and logged once); "as of" is that search's time |
| Decided | `is:closed assignee:<login> label:decision,needs-review closed:>=<seven days ago>` | at load, then every 15 min, and at once when the viewer opens the Decided tab or presses Refresh | the Decided tab (closed issues, closed and merged PRs) |

The read budget is one open search per 2 min, one closed search per 15 min, and a row's or desk's comments read only when its `updated_at` changed since the last read. A search answered with a rate limit (a 429, "rate limit" in the error, or a 403 naming a secondary limit or a retry-after) pauses both searches until max(the retry-after it carries, 60 s), doubled on each consecutive one up to 15 min and reset by a success, and the page keeps its lists and shows one muted line under the header, "GitHub asked the page to slow down; showing the list as of <time>; next try <time>.", instead of an error block.

- A row is a PR when its `html_url` contains `/pull/<n>`. This connector's search results carry no `pull_request` field, and its `labels` and `assignees` are strings.
- A decision issue's body is parsed by shape into six sections: `## Decision`, `## Unblocks`, `## Waits`, `## Recommendation`, `## Approve with`, `## Record`. A body missing a section renders the card with "malformed: <missing section>" and no buttons. The exact phrase is the quoted string in `## Approve with`.
- A PR body is not parsed into sections. If it has a `## Approve with` heading, the phrase is its quoted string (no quoted string there is "malformed", no buttons); otherwise the phrase is a bare `approve`.
- Labels shown as chips: `PR` (the row is a pull request), `hands` (red: only the viewer can perform the act), `seat:<id>` (who waits).

## Cards

Header: repo#number, title without the `Decision: ` prefix, chips. Body of a decision: Decision, Unblocks, Waits, Recommendation, Record (the commit id or link). A PR card has no body sections; it has an "Open on GitHub" link to the PR (read the diff there) next to Context. Footer: the phrase in a monospace box (when `## Approve with` quotes an instruction containing a single-quoted phrase, the inner phrase is the one; a plain quoted phrase is used as is) and three buttons.

| Button | Posts as an issue comment | Then |
|---|---|---|
| Approve (optional comment box) | the exact phrase; with a comment, `<phrase> — <the typed comment>` | the card shows "answered <UTC>" and greys out |
| Revise (text required) | `revise: <what to change>` | the card shows "revision requested" until the seat replies on the issue, then offers "Answer again" |
| Reject (reason required) | `reject: <the typed reason>` | the card shows "answered <UTC>" and greys out |

A PR is answered with the same three forms, as a comment on the PR (`add_issue_comment` takes a PR number). Two facts make that the form: every seat posts as the same login as the viewer, so a PR that needs the viewer is marked by the label `needs-review` and the viewer as assignee rather than by a review request; and the connector has no tool to submit a PR review. The seat that opened the PR reads the comment as it reads an answer on a decision.

The four answers and who may give them are the protocol's (`respond` skill): only the assignee's comment is an answer; a bare `approve` from the assignee on the issue counts like the phrase, so the page may post the phrase without loss. The comment is the record (its URL). The page never closes an issue, never labels, never edits a body, never acks: an ack is a seat's own `BEAST-ACK` comment, which the page only reads; the hearing seat acts on the relay's `UPDATED` (see `respond`).

Testing the write path: file a throwaway decision with `decision.sh new --repo <your private repo> --assignee <you> --by <SEAT> --seat <SEAT> --title "FIXTURE board write <UTC>" …` (placeholder sections, `--record fixture`), answer it from the page, confirm the comment on GitHub, then close it with `decision.sh close … --by <SEAT>`. The relay sends that seat your answer (an `UPDATED`), never its own filing or close; that is expected and harmless.

Multi-select: every answerable card (decision or PR) has a checkbox; a bar above the list offers "Approve selected", shows each comment it will post (`repo#number → phrase`), then posts one comment per issue, in order.

Context: each card has a "Context" button that loads the issue's comment thread and up to three files the body links by full GitHub URL (`https://github.com/<owner>/<repo>/blob/<ref>/<path>`), read through the viewer's connector. A record cited as free text is not fetched.

Deep link: the artifact link plus `#<owner>.<repo>.<number>` expands that row's card: in the waiting-on-you list when the row waits on the viewer, otherwise in the first seat group that holds it (opening "With the seats"); `#desk.<login>.<LABEL>` opens that seat's drill-down; `#decided` and `#awards` open those tabs.

## Desks

A desk is one open issue per seat: title `Desk: <id>`, labels `desk` and `seat:<id>`, assigned to the viewer. Its comments are the seat's small asks and its messages:

| Comment (first line, then lines) | Meaning |
|---|---|
| `BEAST-ASK n=<seq> seat=<id> at=<UTC>[ milestone="<title>"]`, question lines, optional `options: a \| b \| c`, optional `default: a`, `Waits on: <ref>` lines | ask n from the seat, under a milestone, with what it waits on (shown on the ask) |
| `BEAST-ANSWER n=<seq> <text>` (the text may continue on the next lines) | the answer to ask n |
| `BEAST-WITHDRAW n=<seq>` | the seat withdrew ask n |
| `BEAST-MSG from=<slug>/<LABEL>/<login> to=<slug>/<LABEL>/<login> re=<ref|none> blocking=no at=<UTC>`, then the body (`MSG_RE`, the twin of `lib.sh`'s `MSG_HEADER_RE`) | a message from a seat |
| any other comment that does not start with `BEAST-` | a message from its author (the viewer, today) |

An ask is open while it has no answer and no withdrawal. Answers and withdrawals are read in comment order, as `desk.sh` reads them: the first one on an open ask settles it. One parser (`parseDesk`) reads a desk's comments; everything on the page that counts asks reads its result. A first line that names one of the four forms but does not match it is malformed, and so is an ask without a question line, with a second ask of the same n, with a seat other than the desk's, with `options:` of fewer than two non-empty choices, or with a `default:` that is not one of its options, an answer or withdrawal naming no ask on the desk or an ask no longer open, and an answer with no text. Malformed lines are counted on the desk's chip and listed in the drill-down; they are never guessed at. One exception, the rule `desk_parse` holds: a `BEAST-MSG` line that does not match the shape (the pre-1.5.0 tag) on a comment no newer than the seat's newest `BEAST-ACK` on the desk (read by the page's one ack reader, `ackLine`) is history the seat acted on: the chip shows it as a muted `· <n> earlier`, the drill-down as one line, never a list; with no ack by the seat every such line is malformed. Other `BEAST-` comments (acks, notes) are counted and not shown.

Comments come from `issue_read` `get_comments` per desk, through the page's one comment reader (`readComments`: pages of 20 until a short page), stored per desk and re-read when the desk's `updated_at` moves or after the page posts on it. The reader takes the reply as a bare comment array (the connector's shape inside a page) or as `{comments: [...]}` (its shape in a session); any other reply fails loud with `bad_payload` naming the issue, and the desk's chip shows `? open asks`.

Desks strip: above the groups on the Board tab, one chip per desk, `<LABEL> · <n> open asks` ("…" until its comments are read). A desk with no `seat:` label or several is shown as malformed. A desk is quiet when it is read, has no open or malformed ask, one seat label, no milestone due or overdue, and is not the one open; quiet desks are hidden behind "+<n> quiet" (all quiet: "Desks: no open asks" and "Show desks (<n>)"), and the choice persists with the other view settings. Clicking a chip opens or closes that seat's drill-down. A seat's group summary on the Board tab adds `· <n> asks` when its desk has open asks.

Drill-down (a panel above the groups):
- The open asks as cards: the question, one button per option (the seat's default highlighted), "Other answer" for free text, and "Promote to decision". An option or free text goes through the same confirm step as the board's answers: the exact comment `BEAST-ANSWER n=<n> <text>` is shown, then posted on "Post this comment". "Promote to decision" only shows copyable text asking the seat to file the ask as a decision; the page never files rows.
- The last ten answered asks (question, answer, link) and the count withdrawn.
- The messages thread, oldest first.
- "Message this seat": a plain comment on the desk, with the same confirm step. A message whose first line starts `BEAST-` is refused, because it would be read as a protocol line.

A write that may or may not have posted offers "Check the desk", which re-reads the desk and looks for the exact comment.

## Waiting on you, groups, acks, Decided

Waiting on you: each open row gets one status from what the page already reads (the viewer's answer on the issue and each seat's newest current ack), in this order: the seat replied after a revise → "Your turn — <seats> replied"; the viewer has answered: a revise → "Revision requested — waiting on <seats>", a current `executed` ack → "<SEAT> working on it", a current `blocked` ack → "<SEAT> blocked", a seat unacked → "Answered — <seats> hasn't picked it up", else "Answered — <seats> has it"; no answer → "Your turn", whatever the seats acked: an open row without the decider's answer waits on the decider (an ack says how the seat handled the row's latest event, never who decides), and the newest current `blocked` or `executed` ack is a muted note after it ("Your turn · <SEAT> blocked: <the ack's next=>", "Your turn · <SEAT> executed its part"). The rows whose status is "Your turn" are listed first, oldest first, under "<n> decisions are waiting on you" (expanded when there are three or fewer), and the tab's count reads "(<n> waiting)". Every other row goes in "With the seats (<n>)", a folded section holding the seat groups below.

Groups: the "With the seats" section is one `<details>` per `seat:` label present in the rows, sorted by name, plus a last group "no seat" for rows without one. The summary reads `<SEAT> · <n> open · <m> unacked`, where m counts the rows whose thread shows no current ack from that seat (while a row's thread has not been read yet the count shows "…"). A row with k seat labels appears once in each of its k groups; the copies share one state, so an answer given in one copy shows in all of them. Groups start collapsed; the set of open groups, the sort, and the Decided filter persist for the browser tab in `sessionStorage` (one key, `board-ui`). Controls above the groups: "Expand all", "Collapse all", and the sort toggle "Group by seat" (default) or "By updated" (the flat list, newest first, every card expanded). Inside a group the rows unacked for that seat come first, then by `updated_at`, newest first.

Cards: each card in a group starts collapsed as one summary row: the ref link, the title, the `hands` chip, one chip per seat (`SEAT ✓seen` / `✓executed` / `✓blocked` when the seat's ack is current, `SEAT —` when it is not; the chip's title carries the ack's `at`, or "no ack after the latest event"), and the row's status from "Waiting on you". Clicking the row expands that copy to the full card (body, Context button, phrase and answers). A card with an answer in progress (a chosen answer, a draft, or a post in flight) stays expanded.

Acks: the comment thread is read once per row (when the row has seat labels or comments) and feeds three things: the answer check, the Context drill-down, and the acks. An ack is a comment whose first line, or whose last non-empty line (a close comment carries it last), matches exactly `BEAST-ACK seat=<SEAT> at=<ISO time> state=<seen|executed|blocked>`; the newest such comment per seat counts. The row's latest event is the newest of its creation, the assignee's newest answer-form comment, and (closed rows) its close. A seat is current on a row when its newest ack is at or after the row's latest event (the row was created, the decider answered, the row was closed); the closer line of a close comment ("Closed by seat X at T.") is X's `seen` ack at the issue's closed time; a `BEAST-ACK` line that does not match the shape is counted as malformed and shown, never guessed. A comment whose first or last line starts with `BEAST-ACK` but does not match the form is never guessed at: the card shows "N malformed BEAST-ACK line(s)".

Decided: the "Decided" tab (label `Decided · last 7 days (<n>)`) lists the decisions and PRs assigned to the viewer and closed (or merged) in the last seven days, in the same seat groups (`<SEAT> · <n> closed · <m> unacked`). Each summary row shows the close time (UTC), the ref, the title and the ack chips; expanded, the card shows the words the decision was closed on, the first line of the newest comment beginning `Closed on the word, verbatim: ` or `Rejected on the word, verbatim: ` with that prefix removed (or "(closed without the words)"), a link to that comment, and the Context button. A PR without those words reads "(closed or merged on GitHub without the words; open it to see which)", since the search result does not say which, and carries "Open on GitHub". A checkbox filters to "only rows not yet acked by every seat".

Each answer has a confirm step that shows the exact comment before it posts. A card whose issue already carries the assignee's answer (including a bare `approve` / `approved`) renders as answered on load.

The page source is `plugin/templates/board.html`; `/daita-beast:board-ui` publishes it (connector check, capabilities, hand-over).

**The template on main is the page's only source.** A fix is made in the template (with this spec) and then published; the live page is never edited alone. Republish: fetch `plugin/templates/board.html` at a named commit of main (`get_file_contents` with that commit as `sha`), fill the stamp, publish it to the same artifact URL, and keep the page's capabilities as they are.

## The stamp and the tick

The template's first line is `<!-- board.html @ @@COMMIT@@ -->`. At publish, `/daita-beast:board-ui` replaces `@@COMMIT@@` with the template's newest commit on `DeSciX/daita-beast` main (`list_commits` with `path`), the only edit made to the template; the published page thus names the commit it was built from, and that line is the one owner of "which template is live". A page without the line predates stamps and is republished once.

The decider's Cowork scheduled task runs `/daita-beast:cowork-tick <owner/repo>` (the `cowork-tick` skill): it compares main's newest template commit with the page's stamp and, when they differ, republishes through the `board-ui` publish step, exactly once per template change; it also posts the decider's digest (open rows, open desk asks, seat messages since the last tick) when something moved, and keeps one bookkeeping comment per decider on the pinned board issue, `BEAST-COWORK by=<login> at=<UTC> rows=<n> asks=<m> msgs=<k>`, edited in place. A quiet tick posts nothing and republishes nothing. The relay, the desk parser and the inbox ignore a comment whose first token is `BEAST-COWORK`.

A second tab, "Awards", lists the current month's `awards/<YYYY-MM>.jsonl` of a community repo (path and repo chosen in a small selector; read through the connector's file-contents tool) as the per-login table.

## Rules

- Nothing a viewer can read here is embedded in the page: all data is fetched at view time through the connector with the viewer's credentials.
- Errors are shown per card with the connector's error code; `retryable` errors retry once; an authorization denial drops the data and says so.
- The page works with the connector absent (`use("mcp")` resolves null): it shows the two search URLs, board (`https://github.com/issues?q=is%3Aopen+assignee%3A<login>+label%3Adecision%2Cneeds-review`) and desks (`https://github.com/issues?q=is%3Aopen+is%3Aissue+label%3Adesk+assignee%3A<login>`), the answer forms for a decision or a PR, and the desk answer form `BEAST-ANSWER n=<n> <option or your words>`, as text to paste into GitHub.
- Tokens, fonts and layout per the artifact-design skill; phone width works.

## Milestones due

The GitHub connector has no tool that lists a repo's milestones, so the page reads them off the rows it already fetches: the search asks for the `milestone` field of every open and decided row. An open milestone with a due date within 3 days, or overdue, is shown on the desk chip of every seat whose desk is in that milestone's repo (`· milestone "<title>" due in 2d`, or `overdue 3d`). A due milestone with no row on the board is not seen by the page; `decision.sh inbox` and `board.sh` read every milestone of the home repos.
