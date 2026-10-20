---
name: board
description: Render the pending-decisions board — every open decision issue and every PR labelled needs-review assigned to a person, one row each (a decision with what it unblocks, who waits, the recommendation, the exact approving phrase and the record id; a PR with its title, what it unblocks, the recommendation and its phrase). Use for "what is pending on me", "show the board", "republish the decisions board".
---

# board — the pending-decisions board

The board is a GitHub search, not a system: `is:open label:decision,needs-review assignee:<decider>`, decision issues and PRs for review. This skill renders them as one table with a Kind column: a decision row parsed by shape from its body, a PR row from its title, its `## Unblocks` and `## Recommendation` (written by `pr.sh request`) and its phrase. Desks (label `desk`) are never board rows.

Render in the terminal (defaults to the gh user as assignee):
```
${CLAUDE_PLUGIN_ROOT}/scripts/board.sh [--assignee <login>] [--owner <owner>]...
```
Print the live URL the person can open in a browser:
```
${CLAUDE_PLUGIN_ROOT}/scripts/board.sh --web
```
Republish the generated table into the pinned issue "Pending decisions (generated)" of the coordinating repo (created and pinned when absent):
```
${CLAUDE_PLUGIN_ROOT}/scripts/board.sh --publish --repo <board repo>
```

If the script exits non-zero it names a row whose body lacks a required section: a decision issue (fix its body: the six sections of the decision template) or a PR (rerun `pr.sh request` with `--unblocks` and `--recommendation`); never patch the renderer to tolerate it.

Hand the person the two URLs (the search and the pinned issue) rather than file paths.

The decider's own page in claude.ai or Cowork is published from `templates/board.html` by `/daita-beast:board-ui` (that session needs the `github` connector and the Artifact tool); this skill renders the same rows in a terminal.

The generated issue carries two tables: pending (open rows, with a Seats column: ✓ and the ack state per seat when its newest ack is at or after the row's latest event, — when not) and decided (rows closed in the last 7 days with the words from the close comment and the Acks column; rows not yet acked by every seat sort first). A row closed by mistake is reopened with a comment; the decided table drops it on the next publish.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
