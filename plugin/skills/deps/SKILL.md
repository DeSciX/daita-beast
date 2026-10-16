---
name: deps
description: What a seat waits on and the state of each (released, delayed, changed direction, waiting on time), computed from GitHub. Use for "what am I waiting on", "has the thing I need shipped", "did anything I depend on change direction".
---

# deps — dependencies as data

Declare what you wait on when you file it, never in prose: `--waits-on <seat | owner/repo#N>` (repeatable) on `decision.sh new`, `desk.sh ask` and `milestone.sh new`. Each is stored as one line, `Waits on: <seat id | owner/repo#N>`: at the end of a row's `## Waits` section, among an ask's lines, in a milestone's description.

```
${CLAUDE_PLUGIN_ROOT}/scripts/deps.sh <SEAT>
```

It reads the declarations on your open decision rows in your home, your open desk asks and your home's open milestones, and measures each:

| State | When |
|---|---|
| released | the row closed approved, or the PR merged; a seat whose milestones are all closed (the latest one) — with the link |
| delayed | still open, and its milestone (the row's, or the seat's soonest open one) is overdue or was moved later — with the why |
| changed direction | the row was rejected or revised, or the PR closed unmerged — with the link, and the first line of the words when the row is in your own home |
| waiting, on time | still open and not late |
| waiting, no milestone | a seat that has set no milestone |

The participant report (`/daita-beast:report`) uses the same measure.
