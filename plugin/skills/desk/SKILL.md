---
name: desk
description: A seat's desk — the tier below the board for questions you would ask the developer across the desk (a name, a rewording, which of two options, a clarification) and for durable messages between seats. Use for "ask the owner on the desk", "what should X be named", "message seat Y", "the owner said b to ask 2", "check my desk".
---

# desk — asks, answers and messages that never touch the board

The test: would a development team put this on a PR or an issue for the lead's approval? Yes → the board (`/daita-beast:pr` for code, `/daita-beast:decision` for an act without code). No, it is a question across the desk → the seat's desk. An ask that grows big is filed on the board and the ask is answered `→ <row url>`.

A desk is one issue per seat in the seat's roster repo (`Desk: <login>/<LABEL>`, labels `desk` + `seat:<login>/<LABEL>`, assigned to the decider). Its body is generated; never edit it.

Compose every question to the rule `ask` enforces (`desk.sh --help` states it): the content inline, or a URL to a file or diff at a commit (`https://github.com/<owner>/<repo>/blob/<sha>/<path>`, `…/commit/<sha>`); never a local path (`/Users/…`, `/home/…`, `~/…`) or "see session", "as discussed", "per our chat". The decider reads only the desk. A question that breaks it is refused before anything is written.

```
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh open <SEAT>                     # once; idempotent
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh ask <SEAT> --text "<question>" [--options "a | b | c"] [--default a] [--milestone "<title>"] [--waits-on <seat | owner/repo#N>]... [--supersedes <n>]
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh answer <SEAT> <n> "<the decider's words, verbatim>" --by <YOUR SEAT>
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh withdraw <SEAT> <n>
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh msg <TO-SEAT> --from <SEAT> --text "<body>"
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh publish <SEAT>
${CLAUDE_PLUGIN_ROOT}/scripts/desk.sh inbox <SEAT>
```

- `ask` needs `--milestone` when the desk's repo has an open milestone (it refuses, listing them); the header becomes `BEAST-ASK n=<n> seat=<id> at=<UTC> milestone="<title>"`. Each `--waits-on` adds a `Waits on: <ref>` line. An ask written before milestones has no milestone field and still parses.
- `ask` prints the comment URL and republishes the body. `--default` is what you do if no answer comes by your next seam; it must be one of `--options`.
- The decider answers on the desk with `BEAST-ANSWER n=<n> <option or text>`. When they type the answer to your session instead, post it with `answer --by <YOUR SEAT>`, verbatim; it marks the words as typed to your session and ends the comment with your seen ack, so the answer is your own act: the relay sends you no event for it and the watchdog does not remind you of it, while it stands as the decider's answer to the ask. Your ack also covers anything else on your desk newer than your last ack: `answer` lists those first, so read them. Never answer your own ask with words the decider did not give.
- `withdraw` an ask that no longer matters; an ask never stays open forever.
- An ask is never edited: its options bind. When what it asks about changed, re-ask with `--supersedes <n>`: it posts the new ask with the line `Replaces: n=<n>`, then withdraws `n`, in one act, and the decider sees "replaces n=<n>" on the new ask (the desk body and the board page). It refuses, before writing, when `n` is answered, withdrawn or no ask on the desk. If the withdrawal fails after the new ask landed, run `desk.sh withdraw <SEAT> <n>`.
- `msg` leaves a durable message on another seat's desk; `SendMessage` stays the fast path on one machine, the desk message survives reloads and surface switches. A plain comment by the decider on your desk is a message from them.
- `inbox` lists answers and messages newer than your last ack on the desk (a message you sent yourself, such as your own section of a milestone report, is not listed); `decision.sh inbox` prints it at its end. Act, then `ack.sh <desk> --seat <SEAT> --state seen --next "<act>"`.
- Answers to no open ask, asks or messages addressed to another seat, and malformed `BEAST-` lines are named on stderr and dropped; fix the comment, never the parser.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
