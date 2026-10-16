---
name: seats
description: Announce this session as a named seat and resolve the other seats' SendMessage addresses from the repo's roster. Use as the first act of any seated session ("seat me as BUILDER", "who is REVIEWER right now", "/daita-beast:seats BUILDER").
---

# seats — the repo-scoped seat map

A seated session starts with `/daita-beast:join` in the seat's home, which records the address for you; this skill is the address map. Where a seat's home is: `/daita-beast:seat` (`seat.sh where <SEAT>`). Addresses are re-minted on every session reload, so a seat announces itself and reads others only through this skill, never from memory.

1. Call `ListAgents`. The first line names this session: `This session is <name> [<ref>]`.
2. Record it under the label you were given (the label must exist in this repo's `.beast/roster.json`; a label the roster does not know is refused: a seat is created with `seat.sh new`):
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/seats.sh record <LABEL> "<name> [<ref>]"
   ```
3. Show the map:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/seats.sh list
   ```
4. To message a seat, resolve its address and send with `SendMessage`:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/seats.sh address BUILDER
   ```
   An address is verified by a reply, never assumed. If `address` reports nothing recorded, that session has not announced itself since its last reload: ask the user to run this skill there.

Rules: the roster is committed and is the repo's visibility filter (a repo lists only the seats it legitimately coordinates with). The address file `~/.beast/sessions.json` is machine-local, never committed, and keyed by seat id `<login>/<LABEL>`; a LABEL argument resolves through the roster, and an id works anywhere a LABEL does. Inter-seat traffic is SendMessage at a seam, a blocker or a completion; cross-repo asks are GitHub issues in the target repo.
