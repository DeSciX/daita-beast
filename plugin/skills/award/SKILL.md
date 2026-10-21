---
name: award
description: Record an award on a pull request or issue as the owner's own comment (BEAST-AWARD amount token to for ref) plus the `awarded` label; only a repo admin or maintainer can. Use for "award 500 ACME to @login for the logo PR", "pay the bounty on #12", "self-award today's work".
---

# award — the owner's word on a PR or issue

```
${CLAUDE_PLUGIN_ROOT}/scripts/award.sh <owner/repo#N | PR or issue URL> --amount 500 --token ACME --to @login --for "accepted logo (PR #12)" [--ref <bounty or decision URL>]
```
It writes one comment of the fixed shape `BEAST-AWARD amount=500 token=ACME to=@login for="…" ref=…`, adds the label `awarded`, and prints the comment URL. GitHub notifies the recipient. The script refuses when the caller is not an admin or maintainer of the repo, when the amount is not a plain decimal (`500`, `12.5`: no separator, no sign, no leading or trailing zero; `AWARD_AMOUNT_RE` in `lib.sh`), when the token is not a symbol, when the recipient is not a GitHub login, when `--ref` is given and is not an https URL (without `--ref` the ledger cites the awarded item's URL), or when the checkout has no filled `.beast/award-policy.md` for that repo (written by `init-repo.sh <owner/repo> --path <checkout> --token <SYMBOL> --community <owner/repo>`; a repo that takes no outside contributions has no policy and awards nothing). The token awarded must be the policy's token.

**Token authority.** The repo's policy names the token's community repo on its `Community: <owner/repo>` line, and that repo's `.beast/awarders.json` (`{"token": "ACME", "awarders": ["acme/widgets", …]}`, read through GitHub at its default branch) lists the repos that may award the token. A repo it does not list is refused, naming the community repo, the file and the missing entry; a community repo without the file refuses every award, naming the file to create; a malformed file dies naming it. Nothing is written before these pass. The community repo's owner adds a repo by committing it to `awarders`.

Rules: the token is the community's token (community id == token symbol); a sub-app has no token of its own. The amount is the owner's figure; a bounty's amount is the floor, not a cap. An award reaches the recipient as a DeSciX offer through the ledger's sheet (`/daita-beast:ledger`, `--sheet`); nothing here touches a chain. The ledger (`/daita-beast:ledger`) is the roll-up; never edit it by hand.
