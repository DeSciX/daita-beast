---
name: init-repo
description: Make a repository a Beast coordinating repo — the four labels, the decision and workstream issue templates, and a roster skeleton. Use for "set this repo up for beast", "init beast here", or when seats or board report a missing roster.
---

# init-repo — labels, templates, roster

```
${CLAUDE_PLUGIN_ROOT}/scripts/init-repo.sh <owner/repo> --path <local checkout> [--token <SYMBOL>]
```
Idempotent: labels are created or updated in place; `.github/ISSUE_TEMPLATE/decision.md`, `workstream.md`, `bounty.md` and `.beast/roster.json` are written only when absent. `.beast/award-policy.md` is written only with `--token` (the community token, e.g. ACME), filled; a repo that takes no outside contributions has no policy. No written file carries a placeholder.

After the skeleton is written, fill `.beast/roster.json`: each seat the repo legitimately coordinates with (label, role, repo, lane, GitHub login) and the people (login, name, role). List only what this repo needs to know; a repo for one app does not carry the whole ecosystem. Commit the roster and the templates.
