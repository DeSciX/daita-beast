---
name: desk
description: A seat's desk — the tier below the board for questions you would ask the developer across the desk (a name, a rewording, which of two options, a clarification) and for durable messages between seats. Use for "ask the owner on the desk", "what should X be named", "message seat Y", "the owner said b to ask 2", "check my desk".
---

# desk — asks, answers and messages that never touch the board

The test: would a development team put this on a PR or an issue for the lead's approval? Yes → the board (`/daita-beast:pr` for code, `/daita-beast:decision` for an act without code). No, it is a question across the desk → the seat's desk. An ask that grows big is filed on the board and the ask is answered `→ <row url>`.

A desk is one issue per seat in the seat's roster repo (`Desk: <login>/<LABEL>`, labels `desk` + `seat:<login>/<LABEL>`, assigned to the decider). Its body is generated; never edit it.

```
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh open <SEAT>                     # once; idempotent
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh ask <SEAT> --text "<question>" [--options "a | b | c"] [--default a] [--milestone "<title>"] [--waits-on <seat | owner/repo#N>]...
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh answer <SEAT> <n> "<the decider's words, verbatim>"
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh withdraw <SEAT> <n>
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh msg <TO-SEAT> --from <SEAT> --text "<body>"
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh publish <SEAT>
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh inbox <SEAT>
```

- `ask` needs `--milestone` when the desk's repo has an open milestone (it refuses, listing them); the header becomes `BEAST-ASK n=<n> seat=<id> at=<UTC> milestone="<title>"`. Each `--waits-on` adds a `Waits on: <ref>` line. An ask written before milestones has no milestone field and still parses.
- `ask` prints the comment URL and republishes the body. `--default` is what you do if no answer comes by your next seam; it must be one of `--options`.
- The decider answers on the desk with `BEAST-ANSWER n=<n> <option or text>`. When they type the answer to your session instead, post it with `answer`, verbatim; it marks the words as typed to your session. Never answer your own ask with words the decider did not give.
- `withdraw` an ask that no longer matters; an ask never stays open forever.
- `msg` leaves a durable message on another seat's desk; `SendMessage` stays the fast path on one machine, the desk message survives reloads and surface switches. A plain comment by the decider on your desk is a message from them.
- `inbox` lists answers and messages newer than your last ack on the desk; `decision.sh inbox` prints it at its end. Act, then `ack.sh <desk> --seat <SEAT> --state seen --next "<act>"`.
- Answers to no open ask, asks or messages addressed to another seat, and malformed `BEAST-` lines are named on stderr and dropped; fix the comment, never the parser.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
