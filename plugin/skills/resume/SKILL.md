---
name: resume
description: Rebuild a seat's working state after a compaction or reload from GitHub alone — its last BEAST-STATUS handoff, its BEAST-NOTES, the decisions decided for it meanwhile, the open ones waiting on it, and the live seat map. Use as the second act of a resumed session, right after seats ("resume as BUILDER", "what was I doing", "catch me up on my seat").
---

# resume — a seat's state lives on GitHub, not in a session

Before a compaction or a hand-off, the seat posts a handoff on its workstream tracking issue:
```
${CLAUDE_PLUGIN_ROOT}/scripts/status.sh <owner/repo#N> --seat <SEAT> --state handoff \
  --next "<the next critical-path act>" --text "<northstar in one line; waiting on; branches, worktrees, fixtures left; gotchas>"
```
After the compaction or reload, in this order:
1. `/daita-beast:join <SEAT>`, from any directory (prints `SEATED <id> at <home>`, records the new address, regenerates the CLAUDE.md block, lists memory that duplicates GitHub; it runs step 2). From then on every command starts with `cd <home> &&`.
2. ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/resume.sh <SEAT>
   ```
   It prints the live seat map, the seat's newest BEAST-STATUS comment (the handoff), its notes (the one `BEAST-NOTES seat=<id>` comment on its tracking issue) and its inbox (rows naming it whose latest event is newer than its ack).
3. Re-read the home's own instruction surfaces (`<home>/CLAUDE.md`, the agent definition the seat runs as): those are the role, served by the repo, never carried in a session; a session started elsewhere did not load them.

After a compaction the SessionStart hook reminds the seat to post the handoff from its summary first (a PreCompact hook cannot add context, so the reminder comes after the compaction).

Notes: things the seat must not relearn on another surface (where its home is, a standing constraint) go in its notes, edited in place:
```
${CLAUDE_PLUGIN_ROOT}/scripts/notes.sh <SEAT> show | set --text-file <f> | append --text "<line>"
```

What goes where: the ROLE (obligations, tools, invariants) is the repo's agent definition and CLAUDE.md, shared by every seat of that role. The SEAT's working state (what it is doing, waiting on, left behind) is its BEAST-STATUS comments; its durable facts are its BEAST-NOTES comment. The auto-memory is the launch folder's, shared by every seat started there: it holds only short pointers and lessons true for all of them; seat state lives on GitHub.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
