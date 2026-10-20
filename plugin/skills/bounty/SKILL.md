---
name: bounty
description: Open a bounty — an issue labelled `bounty` whose ## Bounty section states the amount the owner will award on acceptance; submissions are PRs that reference it. Use for "post a 500 ACME bounty for a new logo", "open a bounty on the ledger page".
---

# bounty — work the owner will award on acceptance

```
${CLAUDE_PLUGIN_ROOT}/scripts/bounty.sh --repo acme/widgets --title "New logo for widgets.example" --amount 500 --token ACME \
  --what "<the work, and what accepted means>" [--project <owner>/<number>]
```
Requires the checkout's filled `.beast/award-policy.md` for that repo with the same token (the bounty text cites it), and the policy's community repo listing the repo in its `.beast/awarders.json` (a bounty promises an award; see `/daita-beast:award`). Creates the issue from the bounty template (Bounty / What / How to submit / Decides) and prints its URL. Submissions are pull requests that reference the issue (`Closes #n` or `Bounty #n`), one per PR. On acceptance the owner merges and awards with `/daita-beast:award` (the bounty amount or more); a declined submission's PR is closed and may still receive an effort award. The moderator agent drafts suggestions; the owner decides.
