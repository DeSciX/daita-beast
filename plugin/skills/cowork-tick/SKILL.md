---
name: cowork-tick
description: The prompt of a Cowork scheduled task for one decider — their digest (open rows waiting on them, open desk asks, seat messages since the last tick) when something moved, and a republish of their board page when the plugin's template moved on main. Connector only, no shell. Use as the scheduled task's prompt ("/daita-beast:cowork-tick <owner/repo>"), or by hand: "run my tick", "what moved since the last tick".
---

# cowork-tick — the decider's scheduled digest and board refresh

Runs in Cowork as a scheduled task whose prompt is `/daita-beast:cowork-tick <owner/repo>`, where `<owner/repo>` is the home repo whose `.beast/roster.json` names the board repo (the `install` skill creates the task). Without that argument the tick refuses: `cowork-tick: no roster repo given; the scheduled task's prompt is /daita-beast:cowork-tick <owner/repo>`. It uses the GitHub connector (recipes and tool names: the `connector` skill, step 0) and, for the page, the Artifact tool and the `board-ui` skill. It never runs a script, never files, closes, labels or acks: a tick reads, tells, and keeps one bookkeeping comment.

## 1. Who and where

1. `get_me` → `<login>`, the viewer. The digest is theirs.
2. `get_file_contents` `{owner, repo, path: ".beast/roster.json"}` → `board` (the repo of the pinned board issue) and the roster's owners (for `user:` terms).
3. The pinned board issue: `search_issues` `{query: "\"Pending decisions (generated)\" in:title repo:<board>", fields: ["number", "title", "state"]}`, then keep the open issues whose title is exactly `Pending decisions (generated)`; exactly one, else refuse naming them (`cowork-tick: <n> issues titled "Pending decisions (generated)" in <board>`; a shell seat fixes it with `board.sh --publish`).
4. The stamp: `issue_read` `{method: "get_comments", owner, repo, issue_number}` (pages until a short page); the viewer's stamp is the comment by `<login>` whose first line starts `BEAST-COWORK by=<login> `. Its shape, one line:
   ```
   BEAST-COWORK by=<login> at=<UTC> rows=<n> asks=<m> msgs=<k>
   ```
   `at` is the cut for this tick. No stamp yet: the cut is 24 hours before now, and step 3 of the digest creates the comment. Two stamps by one login: refuse naming both; a human deletes one.

The stamp is bookkeeping: the relay never makes an event of a comment whose first token is `BEAST-COWORK`, the desk parser and the inbox never read it as a message, and the pinned issue carries no `seat:` label, so nothing wakes on it.

## 2. The digest

Three reads, all for the viewer:

| Read | Call | Holds |
|---|---|---|
| rows | `search_issues` `{query: "is:open label:decision assignee:<login>", perPage: 100, sort: "updated", order: "desc", fields: ["number", "title", "html_url", "labels", "updated_at", "repository_url"]}` and `search_pull_requests` with the same arguments and `label:needs-review` (`search_issues` never returns a PR) | every open decision issue and PR waiting on the viewer (a PR when `html_url` contains `/pull/`) |
| desks | `search_issues` `{query: "is:open is:issue label:desk assignee:<login>", perPage: 100, fields: ["number", "title", "html_url", "labels", "updated_at", "repository_url"]}` | one desk per seat |
| desk comments | `issue_read` `get_comments`, only for a desk whose `updated_at` is newer than the cut | its open asks (a `BEAST-ASK n=` with no later `BEAST-ANSWER n=` or `BEAST-WITHDRAW n=` of that n, read in comment order as `desk_parse` does) and its messages created after the cut (`BEAST-MSG … to=<login>/<LABEL>` and `BEAST-MSG … to=<login>` lines, or a plain comment by someone other than the viewer) |

Something **moved** when any row or desk has `updated_at` newer than the cut. (Editing a comment does not move `updated_at`; an edited answer waits for the next new comment, as the protocol notes.)

- **Nothing moved: post nothing, edit nothing, republish nothing** (step 3 still runs). The reply is empty.
- **Something moved:** the reply is the digest, a short list with links, in this order:
  1. `Waiting on you (<n>)`: one line per row, `<owner/repo>#<N> <title> — <PR | decision>, <seat labels> <link>`, newest `updated_at` first; nothing else from the body.
  2. `Open asks (<m>)`: one line per open ask, `<LABEL> ask <n>: <first question line> [options: …] <link to the comment>`.
  3. `Messages since <cut> (<k>)`: one line per message, `<from> on <LABEL>'s desk: <first body line> <link>`.
  Then edit the stamp in place with `update_issue_comment` `{owner, repo, comment_id, body: "BEAST-COWORK by=<login> at=<now UTC> rows=<n> asks=<m> msgs=<k>"}`; when no stamp exists, `add_issue_comment` with that body once. Never a second comment for the same login.

Answers go through the board page or the `connector` skill's recipes (5, 11), never from the tick.

## 3. The board page

1. `list_commits` `{owner: "DeSciX", repo: "daita-beast", path: "plugin/templates/board.html", perPage: 1, fields: ["sha"]}` → `<sha>`, the template's newest commit on the public repo's main.
2. The viewer's board: the Artifact tool's list action (title `Decisions Board`), then read it; the page's first line is `<!-- board.html @ <published sha> -->` (the `board-ui` skill fills it at publish). A page without that line was published before stamps existed: republish it once.
3. `<sha>` equals the published sha: nothing. It differs: run the `board-ui` skill's publish step (section 4 of that skill: fetch the template at `<sha>`, fill the stamp, publish byte-exact to the same URL with that step's capabilities), and add one line to the reply: `Board page republished at <sha>`. No board artifact exists: say so once per tick (`no board page; publish one with /daita-beast:board-ui`) and republish nothing.

A template that moved republishes exactly once: the next tick reads the new stamp from the page.

## What a tick costs

A quiet tick: `get_me`, one `get_file_contents` (the roster), one `search_issues` and one `issue_read` (the stamp), three searches (rows: `search_issues` and `search_pull_requests`; desks: `search_issues`), one `list_commits`, and one Artifact read of the page (the whole page, the one large read). A tick that moved adds one `issue_read` per desk that changed and one comment edit; a template that moved adds the `board-ui` publish (one `get_file_contents` and one Artifact publish). The GitHub search quota (30 a minute) is shared with the board page's own searches (two calls every 2 min, two every 15 min) and the relay: schedule the task no more often than every 15 minutes.
