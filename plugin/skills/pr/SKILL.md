---
name: pr
description: Put a pull request on the decider's board and merge or reject it on their word. Use for "this PR needs the owner's review", "request review", "the owner approved the PR, merge it", "the owner rejected the PR".
---

# pr — a pull request on the board

A code change that needs the decider's word goes on the board as the PR itself. Every seat posts as the decider's login, and GitHub refuses a review request to, or an approval by, a PR's own author; so the request is a label plus the assignee:

```
${CLAUDE_PLUGIN_ROOT}/scripts/pr.sh request <owner/repo#N | PR url> --seat <YOUR SEAT> --unblocks "<what the merge unblocks>" --recommendation "<what you recommend, and why>" [--assignee <login>] [--milestone "<title>"]
```
`--unblocks` and `--recommendation` are required: without either (or with one empty, or pointing elsewhere for its substance) `request` refuses before any write. It writes them into the PR body as `## Unblocks` and `## Recommendation` (a rerun replaces them), the sections the generated board and the board page show on the PR's row, as on a decision row; a needs-review PR without them makes `board.sh` fail naming it. `--milestone` files the PR under that open milestone of its repo; `request` refuses without it when the repo has any open milestone, listing them. It labels the PR `needs-review` and `seat:<login>/<LABEL>` and assigns the decider (the roster's `people[]` owner; it dies when that is not exactly one, then pass `--assignee`). The body is the hand-back shape (`## What`, `## Evidence`, `## Review against the engineering rules`, `## Closes`, `docs/protocol.md`). Add `## Approve with` and a quoted phrase when "approve" alone would be ambiguous; without one the phrase is `approve`.

The decider answers on the PR with the decision forms, read on a comment's first line: the phrase, `<phrase> — <comment>`, bare `approve`/`approved`, `revise: <what>` (push the change, then `decision.sh revise <pr> --by <SEAT> …` posts the amend line; a reply alone is not a revision and `pr.sh close --merge` refuses until it; the PR stays), `reject: <reason>`. Any other comment, yours or the decider's, is not an answer: the PR stays in the decider's turn. Your inbox (`decision.sh inbox <SEAT>`) lists it as answered once he answers.

On approve:
```
${CLAUDE_PLUGIN_ROOT}/scripts/pr.sh close <pr> --merge --words "<verbatim>" --record "<answer comment url>" --by <YOUR SEAT> [--next "<act>"]
```
It merges, or dies naming GitHub's refusal (conflict, failing check) and changes nothing; fix the PR and run it again. On reject, `--rejected` closes it unmerged with the label `rejected`. A PR merged some other way takes neither flag; the close comment then only records the words. Every close writes the same close comment as `decision.sh close` (the words, the record, your `BEAST-ACK` seen line), republishes the board and prints the PR's other seats to tell.
