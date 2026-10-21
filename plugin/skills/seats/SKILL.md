---
name: seats
description: Announce this session as a named seat (its address, account and machine, published as the seat's BEAST-ADDRESS comment on its tracking issue) and resolve another seat's address and whether a direct SendMessage applies or its desk. Use as the first act of any seated session ("seat me as BUILDER", "who is REVIEWER right now", "/daita-beast:seats BUILDER").
---

# seats — the seat map and the seats' addresses

A seated session starts with `/daita-beast:join` in the seat's home, which records the address for you; this skill is the address map. Where a seat's home is: `/daita-beast:seat` (`seat.sh where <SEAT>`). A session's name changes when it restarts (join, the SessionStart rejoin and the machine watchdog record the new one), so a seat reads others' addresses only through this skill, never from memory.

1. Record it under your seat (a seat of this repo's `.beast/roster.json`; one the roster does not know is refused: a seat is created with `seat.sh new`). With no address it reads this session's name from its Claude Code session file (`~/.claude/sessions/<pid>.json`, by `$CLAUDE_CODE_SESSION_ID`) and fails naming the file and the field when it cannot. It writes the seat's one `BEAST-ADDRESS seat=<slug>/<LABEL>/<login> account=<claude account> address="<name>" machine=<hostname> at=<UTC>` comment on its workstream tracking issue (created once, then edited in place: the one owner), the machine-local cache `~/.beast/sessions.json` (keyed by the identity), and the rendered Account/Address/Seen cells of the issue's `## Seats` table:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/seats.sh record <LABEL>
   ```
   When the session file cannot be read, call `ListAgents` (its first line is `This session is <name> [<ref>]`) and pass the name: `seats.sh record <LABEL> "<name>"` (`"<name> [<ref>]"` is accepted too). A name two live sessions carry is recorded and printed `ambiguous: …`: rename one of them.
2. Show the map: every seat of every open workstream among the workstream owners (the roster's owners plus its `workstream_owners`), with its account, address and when it was seen:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/seats.sh list
   ```
3. To message a seat, read its address live and follow the path it prints:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/seats.sh address BUILDER
   ```
   Line 1 is the address (a session name, or `name [ref]`; SendMessage takes the bare name); then its account, machine, age, and `path: direct` (same Claude account, same machine, recorded within 24h, an approximation of "after that seat's newest session start": `SendMessage` to it, the first line `BEAST-MSG from=<your identity> to=<its identity> re=<ref|none> blocking=no at=<UTC>`, then the body) or `path: desk` (another account, another machine or a stale address: `desk.sh msg <SEAT> --from <you> --text "…" [--re <ref>]`, the durable copy on its desk, read at its next wake). A direct line never names the decider's board, never waits on him and is never shown on the board. An address is verified by a reply, never assumed. If `address` reports nothing recorded, that session has not announced itself since its last reload: write to its desk.

Rules: the roster is committed and lists this repo's own seats (a seat of another repo lives in that repo's roster and on the workstream issue's `## Seats` table, which `list` reads). A LABEL argument resolves through the roster, then the workstream tables; `login/LABEL` and the identity `slug/LABEL/login` work anywhere a LABEL does (the same login and label in two workstreams are two identities). Inter-seat traffic is a direct line or a desk message at a seam, a blocker or a completion; cross-repo asks are GitHub issues in the target repo.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
