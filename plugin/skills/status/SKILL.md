---
name: status
description: Post a status report on a workstream's tracking issue with the fixed BEAST-STATUS header (seat, UTC, state, next act). Use at a blocker, a completion or a seam — "post status", "report blocked on X", "mark the workstream done".
---

# status — a report on the workstream's tracking issue

```
${CLAUDE_PLUGIN_ROOT}/scripts/status.sh acme/widgets#7 --seat BUILDER --state working|blocked|done|handoff \
  --next "<the next critical-path act and when it is measured>" --text "<evidence: what ran, exit code, hashes, links>"
```

Post at a blocker, a completion, a seam, or as a `handoff` before a compaction or reload (the resume skill reads the newest one back). Status is about the workstream; a row's consumption is the `ack` skill, on the row. Never post a tick ("still working"). The body carries measurements and links, never a story; "verified: <evidence>" or it is not verified. A blocked report names the decision issue or the cross-repo issue it waits on.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
