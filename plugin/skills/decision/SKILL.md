---
name: decision
description: File a pending decision (an act without code) as a GitHub issue assigned to the person whose word it needs, close one on their verbatim word with its record id, or read your inbox (board rows and your desk). Use for "file this for the owner's word", "this needs the lead's decision", "the owner said X, close the decision", "what is in my inbox".
---

# decision — file or close a pending decision

Which tier: would a development team put this on a PR or an issue for the lead's approval? A code change → a PR on the board (`/daita-beast:pr`). An act without code (deploy PROD, release, spend, chain, secrets, scope, a design approval, ship-or-cut) → a decision issue, below. A question across the desk (a name, a rewording, which option, a clarification) → your desk (`/daita-beast:desk`), never the board.

A decision is an issue in your home repo (the roster's `repo`, always private), labelled `decision`, assigned to the decider, with six sections: Decision, Unblocks, Waits, Recommendation, Approve with, Record. Add `--hands` when only the assignee can perform the act (public flip, chain, secret, scope grant). The Record section cites the dated record (repo and commit id) that holds the context; the verbatim words of a ruling live in that record, the issue cites it.

File one BEFORE you ask the decider for anything you wait on (it files in the roster's `repo`; `--decides <owner/repo>` names the repo it decides, as a `Decides:` link at the end of the Decision section):
```
${CLAUDE_PLUGIN_ROOT}/scripts/decision.sh new --assignee <decider login> [--decides <owner/repo>] \
  --title "<plain-language question>" \
  --decision "<the question>" --unblocks "<what ships>" --waits "<SEAT — what it does on the word>" \
  --recommendation "<answer and why>" --approve-with "<exact phrase>" \
  --record "<repo> <commit id> — <record path>" [--hands] [--project <owner>/<number>]
```
Long text: write the six sections to a file and pass `--body-file <md>` instead of the section flags.

Add `--seat <LABEL>` for every seat that waits on it (label `seat:<login>/<LABEL>`, visible in the GitHub UI and filterable).

Every row belongs to a milestone: `--milestone "<title>"` files it under that open milestone of the repo, and `new` refuses a row without one when the repo has any open milestone, listing them (`/daita-beast:milestone`). Declare what you wait on as data with `--waits-on <seat | owner/repo#N>` (repeatable): each becomes a `Waits on: <ref>` line at the end of the `## Waits` section, read by `/daita-beast:deps` and the participant report.

Close one on the word (comments the verbatim words with the record, closes, republishes the decider's board in the roster's `board` repo, and prints the waiting seats with their live addresses):
```
${CLAUDE_PLUGIN_ROOT}/scripts/decision.sh close acme/widgets#12 --words "<verbatim>" --record "<repo> <commit id> | <issue comment URL>" --by <YOUR SEAT>
```
The close comment's last line is your `BEAST-ACK … state=seen` (`--next` names your act). Then send each other seat printed as unacked ONE line by `SendMessage`: the words verbatim and the issue URL. A seat with no live address is not sent; its inbox lists the row until it acks.

`record` is ONLY for a significant decision the decider already gave in a session before a row existed (scope, engine, ship-or-cut, release; anything needing explanatory content): it is filed AND closed in one act. Never use it for something you are about to ask: that is `new`, filed before you ask, open until the word; a minor word (wording, copy, a link) goes only into the repo's dated record, never onto the board. Filing it closed puts it in the board's decided table; the dated record is committed first and cited:
```
${CLAUDE_PLUGIN_ROOT}/scripts/decision.sh record --assignee <login> [--decides <owner/repo>] --seat <YOUR SEAT> --title "…" <the six sections or --body-file> --words "<verbatim>" --record "<repo commit — path>" --by <YOUR SEAT> [--rejected]
```
A significant word acted on without a row is a protocol defect.

A seat's inbox is computed from GitHub alone, the same on every machine and surface: the board rows (decision issues and PRs labelled `needs-review`) labelled `seat:<login>/<LABEL>` (open, or closed in the last 7 days) whose latest event (created, the decider answered, closed) is newer than the seat's newest `BEAST-ACK`, then the seat's desk (`desk.sh inbox`: answers and messages newer than its last ack on the desk):
```
${CLAUDE_PLUGIN_ROOT}/scripts/decision.sh inbox <SEAT>
```
It opens with your home's milestones due within 3 days or overdue, one line each (move one with a why rather than letting it go stale: `milestone.sh move`), then lists the rows as closed on the word (execute, ack), answered by the decider (on a PR's approve: `pr.sh close --merge`; otherwise reply on the row, ack) and new (read, ack seen), with each row's kind (`decision` or `PR`). Ack with `/daita-beast:ack`; a close you make is your own seen ack. Nothing is written locally. While every seat runs under one GitHub login, a seat's own comment also reads as the assignee's; the four answer forms tell them apart.
If the decider commented their answer on the issue itself, that comment is the record: pass its URL as `--record`. Words typed to a session are committed to the coordinating repo's dated records first, then cited by commit.

Rules: decisions are repo- and project-specific, never Beast-wide. A decision is filed by the seat that is blocked, in its home repo, naming the repo it decides with `--decides`, and added to the workstream's Project. Every write refuses a public or public-intended repo (exit 1, naming the private repo to use): coordination stays in the private twin, and a public repo receives only publishes. Before filing, re-read the current end of the record you cite: a row built from an earlier snapshot files a decision already made. The approving phrase is exact; any other wording from the decider is a question back, not an approval. Never paraphrase a ruling: record the words first (the repo's dated records, committed), then close with the commit id.
