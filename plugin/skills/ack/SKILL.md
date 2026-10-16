---
name: ack
description: Post a seat's ack on a decision row (BEAST-ACK seat= at= state=seen|executed|blocked next=) — the queue's consumption state, readable from any surface. Use when a seat has read a decision that names it, executed one, or is blocked on one; "ack this", "mark executed", "I've seen #14".
---

# ack — a seat's consumption state on a row

```
${CLAUDE_PLUGIN_ROOT}/scripts/ack.sh <owner/repo#N | url> --seat <LABEL> --state seen|executed|blocked --next "<the act and when it is measured>" [--text "<evidence or the blocker>" | --text-file <f>]
```
One comment, fixed first line: `BEAST-ACK seat=<login>/<LABEL> at=<UTC> state=<state> next=<act>`; evidence below it. A seat is current on a row when its newest ack is at or after the row's latest event (the row was created, the decider answered, the row was closed); otherwise the row is in its inbox. A close by a seat (`decision.sh close --by`) is that seat's `seen` ack at the close; `executed` is posted by whoever executed, with the evidence; `blocked` names what it waits on. Every seat the row names (`seat:<login>/<LABEL>` labels) acks for itself; nobody acks for another seat. The page and the generated board show per seat ✓ with the state, or — when unacked.
