---
name: Decision
about: A decision waiting on one person's word. Assign it to that person; label `decision` (add `hands` when only they can perform the act).
title: "Decision: <plain-language question>"
labels: decision
assignees: ''
---

## Decision
<the question in plain language, one or two sentences>
<!-- A program row adds the section "## Sub-acts" right here, one "- <slug>: <one-line act>" line per act the one approval covers (decision.sh new --sub). A follow-on of an approved program ends this section with "Follows: <owner/repo#N> sub-act <slug>" (decision.sh new --follows --sub-act). -->

## Unblocks
<what starts or ships once this is decided>

## Waits
<seat label(s) that are blocked, and what each does on the word>

## Recommendation
<the recommended answer and why, one or two sentences>
<!-- Optional, right here, in this order: "## Stops if" (one "- <condition>" line per condition under which the seat halts and comes back; decision.sh new --stops-if) and "## Undo" (how the act is undone, the rollback named; every deploy, release or publish row carries it; --undo). A sub-act line may end " when: <condition>". A hands row may end ## Decision with "Run sheet: <https url>" (--run-sheet). -->

## Approve with
"<the exact phrase that approves it>" — typed to the orchestrator session, or commented here by the assignee (here a bare `approve` also counts; `<phrase> — <comment>` approves with a comment; `revise: <what to change>` sends it back; `reject: <reason>` closes it). Any other wording is a question back.

## Record
<repo> <commit id> — <record path or title>. The verbatim ruling lives in the record; this issue cites it.
