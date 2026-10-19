---
name: milestone
description: Set out, list, move and close a seat's milestones (GitHub milestones on its home repo) so it schedules its own work. Use for "set the milestones", "M2 slips a week", "what is due", "close M3", "carry the open rows to the next milestone".
---

# milestone — the seat schedules its own work

A milestone is a GitHub milestone on the seat's home (the roster `repo`; `--repo` names another private repo): a title, a due date and what it delivers. Set them out at the start of a workstream (`workstream.sh new` requires at least one). Every row, desk ask and PR then names one (`--milestone`), and the scripts refuse one without it while the repo has an open milestone.

```
${CLAUDE_PLUGIN_ROOT}/scripts/milestone.sh new "M3 milestones and reports" --due 2026-10-30 --delivers "milestone-bound rows, waits-on, due flags, participant report" [--waits-on <seat | owner/repo#N>]...
${CLAUDE_PLUGIN_ROOT}/scripts/milestone.sh list [--state open|closed|all]
${CLAUDE_PLUGIN_ROOT}/scripts/milestone.sh move "M3 milestones and reports" --due 2026-11-06 --why "<one line>"
${CLAUDE_PLUGIN_ROOT}/scripts/milestone.sh close "M3 milestones and reports" [--carry "M4 wrap-up"]
```

- A title is one line without `"` or `|`. The due date is GitHub's own field, the only copy.
- Move a milestone with a why rather than letting it go stale. The description keeps the current due date and the latest why only (`Moved: later — <why>`), no history. A milestone moved later, or overdue, shows as **delayed** to every seat that waits on it.
- `close` refuses while issues, PRs or open desk asks are filed under it, naming each. `--carry <next>` moves them all to the next open milestone, then closes.
- After a close, send the participant report: `/daita-beast:report` (`report.sh milestone "<title>" --post --by <SEAT>`).
- `decision.sh inbox` and `board.sh` show the milestones due within 3 days or overdue, one line each; so does the Cowork page, on the desk chips.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
