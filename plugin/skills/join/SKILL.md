---
name: join
description: Join or rejoin the Beast workflow as a seat — the first act of every session (the SessionStart hook names the seat in a seat's home), after any reload or compaction. Checks the session runs in the seat's home, records its address, regenerates the Beast block in the CLAUDE.md the home loads, lists the home's auto-memory files that duplicate GitHub state, and ends with the seat's handoff, notes and inbox. Use for "join as BUILDER", "rejoin", "I'm back", "set this seat up", "how do I get into Beast".
---

# join — the one way in, every session

A seat is created once with `/daita-beast:seat` (`seat.sh new`), which also makes its home. Join runs in that home every session.

1. Call `ListAgents`; its first line names this session (`This session is <name> [<ref>]`).
2. From the seat's home (`seat.sh where <SEAT>` prints it; a session opened in a home is told its seat by the SessionStart hook):
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/join.sh <SEAT> --address "<name> [<ref>]" [--tracking <owner/repo#N>] [--role "<what this seat owns>"]
   ```
   `--role` only when the role changed; `--tracking` once, when the roster has none for the seat (it lists the open ones).
3. Act on what it prints: commit `.beast/roster.json` (in the main checkout) and the CLAUDE.md when they changed; delete or trim each memory file it lists (working state is the handoff on your tracking issue, durable seat facts are your notes, `notes.sh`, the rules are the CLAUDE.md block; memory keeps lessons about the repo only) and fix `MEMORY.md`'s index; then work the inbox it printed. A long inbox or memory list: hire the `seat-clerk` agent, which drafts acks, the handoff and the triage, and posts nothing.

Join refuses a session that is not in the seat's home and names the home: open a session there instead (one seat per directory: a subdir seat never joins from the checkout root, nor a checkout seat from a subdir). It refuses a seat that is not in the roster (create it with `seat.sh new`) and a seat of another repo. The Beast block goes into the CLAUDE.md the home loads: the repo's for a checkout or worktree home, the wrapper's own for a wrapper, the subdir's own for a subdir (never the checkout root's). It is generated from `templates/claude-block.md`: never edit it by hand, the next join undoes it. A roster row without a `home` is read as a checkout home, and join tells you once to record it with `seat.sh new <SEAT> --kind checkout`.
