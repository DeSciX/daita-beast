---
name: init-repo
description: Make a repository a Beast coordinating repo — the labels, the decision, workstream and bounty issue templates, and a roster skeleton (a public repo gets the bounty and award labels only). Use for "set this repo up for beast", "init beast here", or when seats or board report a missing roster.
---

# init-repo — labels, templates, roster

```
${CLAUDE_PLUGIN_ROOT}/scripts/init-repo.sh <owner/repo> --path <local checkout> [--token <SYMBOL> --community <owner/repo>]
```
Idempotent: labels are created or updated in place; `.github/ISSUE_TEMPLATE/decision.md`, `workstream.md`, `bounty.md` and `.beast/roster.json` are written only when absent. `.beast/award-policy.md` is written only with `--token` (the community token, e.g. ACME) and `--community` (the repo that holds the token's community and its `.beast/awarders.json`, e.g. acme/ACME; the two go together), filled; the repo awards only once that community repo lists it in `awarders`; a repo that takes no outside contributions has no policy. No written file carries a placeholder.

A public or public-intended repo (public on GitHub, or listed in the checkout's roster `public_intended`) gets the public set only: the `bounty` and `awarded` labels, the bounty template and, with `--token` and `--community`, the award policy. Every coordination label (`decision`, `workstream`, `hands`, `blocked`, `needs-review`, `desk`, `rejected`, `seat:*`, `ws:*`), the decision and workstream templates and the roster are refused on stderr: coordination lives in the private twin. When the public repo already carries coordination labels, the script names them and exits 1; it deletes nothing, and their removal is the repo owner's act.

After the skeleton is written, fill `.beast/roster.json`: each seat the repo legitimately coordinates with (label, role, repo, lane, GitHub login) and the people (login, name, role). List only what this repo needs to know; a repo for one app does not carry the whole ecosystem. Commit the roster and the templates.
