---
name: respond
description: How a decider answers a pending decision from any surface (the GitHub issue, the claude.ai board, a session) and how the hearing seat acts — approve, approve with comment, revise, or reject. Use when the owner says "approve #12", "revise this one…", "reject because…", or when a seat receives a BEAST-EVENT and must act.
---

# respond — the decider's four answers

A decision issue carries its exact approving phrase in `## Approve with`. Only the assignee's words are answers. On the issue, a comment is the record (its URL); words typed to a session are committed to the coordinating repo's dated records first, then cited by commit.

| Answer | On the issue | Typed to a session | The hearing seat then |
|---|---|---|---|
| Approve | the exact phrase, or a bare `approve` / `approved` (the assignee and the issue are unambiguous there) | the exact phrase (it names the decision) | `decision.sh close <ref> --words "<the words>" --record "<comment URL or commit>" --by <SEAT>` and acts |
| Approve with comment | `<phrase> — <comment>` | same | same, the words quoted in full; the comment shapes the act |
| Revise | `revise: <what to change>` | same | not an approval: revise the row itself, `decision.sh revise <ref> --by <SEAT> --<section> "<new text>"…` (only the named sections change; it posts one comment whose first line is the amend line), and leave it open; a reply comment is not a revision, and no approval closes the row until it is revised; the decider answers again |
| Reject | `reject: <reason>` | same | `decision.sh close <ref> --words "reject: <reason>" --record "…" --by <SEAT> --rejected` (label `rejected`, closed as not planned); nothing is executed |

Any other wording, and any comment by someone who is not the assignee, is a question back, not an answer: the seat replies on the issue and leaves it open.

**A program row** lists `## Sub-acts`. One approving answer on it pre-authorizes every listed sub-act: the seat files each as a follow-on (`decision.sh new … --follows <program> --sub-act <slug>`), which the board lists under the program and never as the decider's turn, and closes it with `decision.sh close <follow-on> --covered --by <SEAT>`, quoting no new words; the close line cites the program's approval. A `revise:` of the program, or any amend of it, re-opens all of its sub-acts until the decider approves the program again; a reject covers nothing. The decider answers the program, never a follow-on.

**Before any answer**, a seat may amend its own row when the facts under it changed (`decision.sh revise <ref> --by <SEAT> …`, posting `Amended at …: amended by <seat> before any answer`); an approval older than that line no longer counts, so the decider approves the amended row. Once the decider has approved or rejected, the seat no longer amends it.

**Queued.** A row whose `Waits on:` names a row that is still open shows as "queued behind <ref>" and is not the decider's turn until that row closes; the decider may still answer it.

A seat learns of the answer from its inbox (`decision.sh inbox <SEAT>`, computed from acks on GitHub: every answer is a new event for every seat the row names) or, sooner, from the relay where one runs (`BEAST-EVENT kind=UPDATED` when the decider commented, `kind=DECIDED` when a session closed it). On an answer, act as above, then ack (`/daita-beast:ack`): `seen` when read, `executed` with the evidence when done, `blocked` with what it waits on. The board republishes itself on every close.
