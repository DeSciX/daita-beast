---
name: ledger
description: Regenerate a community's monthly award ledger from GitHub (every BEAST-AWARD comment by a repo admin or maintainer on an `awarded` issue or PR) as awards/<YYYY-MM>.jsonl and .md in the community repo. Use for "build the October ledger", "how much has @login been awarded", "publish the awards".
---

# ledger — the generated roll-up, never hand-edited

```
${CLAUDE_PLUGIN_ROOT}/scripts/ledger.sh --community ACME --repos acme/ACME,acme/acme-widgets --month 2026-10 --out <path to the community checkout>/awards
```
Rows are kept only when the comment parses, its token is the community's, it was made in the month, and its author is an admin or maintainer of that repo (checked live). Every dropped comment is named on stderr with the reason and the script exits 2, so a roll-up with holes is never published by accident: fix the cause (a wrong token, a malformed comment, an author without the role) and rerun. A role that cannot be read (a 403: your gh login lacks push access to the repo) stops the run with exit 1 before anything is written, naming the repo, the login and the 403: rerun with a login that has push access.

A ledger bound for a public repo lists only public repos: when `--out` is in a checkout of a public or public-intended repo, a private repo in `--repos` is refused before anything is read, naming it. Its awards stay in a private ledger (an `--out` in the private repo's own checkout). A public ledger is the community repo's, so every repo in `--repos` must be listed in that repo's `.beast/awarders.json` for the token; an unlisted one is refused before anything is read, naming the file and the entry (`/daita-beast:award`, Token authority).

Publishing is the community owner's commit of `awards/<month>.jsonl` (the DIP import artifact: login, token, amount, for, ref, by, at) and `awards/<month>.md` (per-login totals and the award list) to the community repo. The jsonl is what the DeSciX airdrop engagement system imports later; the login-to-wallet mapping is the platform's claim flow, not this ledger's.
