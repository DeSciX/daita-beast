---
name: award
description: Record an award on a pull request or issue as the owner's own comment (BEAST-AWARD amount token to for ref) plus the `awarded` label; only a repo admin or maintainer can. Use for "award 500 ACME to @login for the logo PR", "pay the bounty on #12", "self-award today's work".
---

# award — the owner's word on a PR or issue

```
${CLAUDE_PLUGIN_ROOT}/scripts/award.sh <owner/repo#N | PR or issue URL> --amount 500 --token ACME --to @login --for "accepted logo (PR #12)" [--ref <bounty or decision URL>]
```
It writes one comment of the fixed shape `BEAST-AWARD amount=500 token=ACME to=@login for="…" ref=…`, adds the label `awarded`, and prints the comment URL. GitHub notifies the recipient. The script refuses when the caller is not an admin or maintainer of the repo, when the amount is not a whole number, when the token is not a symbol, when the recipient is not a GitHub login, or when the checkout has no filled `.beast/award-policy.md` for that repo (written by `init-repo.sh <owner/repo> --path <checkout> --token <SYMBOL>`; a repo that takes no outside contributions has no policy and awards nothing). The token awarded must be the policy's token.

Rules: the token is the community's token (community id == token symbol); a sub-app has no token of its own. The amount is the owner's figure; a bounty's amount is the floor, not a cap. Awards are conceptual until the DeSciX DIP import exists; nothing here touches a chain. The ledger (`/daita-beast:ledger`) is the roll-up; never edit it by hand.
