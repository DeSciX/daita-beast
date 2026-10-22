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

## Approve with
"<the exact phrase that approves it>" — typed to the orchestrator session, or commented here by the assignee (here a bare `approve` also counts; `<phrase> — <comment>` approves with a comment; `revise: <what to change>` sends it back; `reject: <reason>` closes it). Any other wording is a question back.

## Record
<repo> <commit id> — <record path or title>. The verbatim ruling lives in the record; this issue cites it.
