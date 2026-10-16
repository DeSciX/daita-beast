---
name: publish
description: Publish chosen changes of a private twin to its public repo — one new scrubbed commit on a PR there, approved on a row in the twin, squash-merged on the word — and pull outside contributions back. Use for "publish this to the public repo", "release X publicly", "the owner approved the publish, merge it", "pull the public repo's contributions into the twin".
---

# publish — from the private twin to its public repo

A public product has a private twin: the roster's `repo`, whose `publishes_to` names the public repo. All work and coordination happen in the twin. `publish.sh` is the only writer to the public repo, and it writes only a publish: a branch, its PR, the squash-merge and the branch's deletion. Every coordination write (row, desk, status, notes, ack, review request) to the public repo is refused by the other scripts. Run it in a checkout of the twin. The public repo must already exist; creating it is its owner's act.

1. Prepare. Write the commit message for outside readers (the subject on line 1), then choose what goes out: paths as they are on the twin's main branch, or named commits squashed together:
```
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh prepare <slug> --paths <path>... --message-file <msg.txt>
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh prepare <slug> --commits <sha>... --message-file <msg.txt>
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh prepare <slug> [--paths <path>...] --delete <path> --message-file <msg.txt>
```
It cuts `publish/<slug>` from the public repo's main with ONE new commit (`--commits` are applied in topological order, oldest first). The twin's history never travels. An empty public repo gets an orphan branch: an empty root, then the commit.

The overlay: a file `.publish/<p>` in the twin publishes as `<p>`, replacing the twin's own copy. The twin's root `CLAUDE.md` never publishes; a public `CLAUDE.md` is `.publish/CLAUDE.md`. `--paths .publish/<p>` and `--paths <p>` name the same public path. `--commits` refuses a commit that touches the root `CLAUDE.md`, `.publish/` or a shadowed path: use `--paths` for those.

To remove a twin-only file from the public repo while the twin keeps it (for example the `.claude/skills/beast/SKILL.md` pointer), add `--delete <path>` (repeatable, alone or with `--paths`/`--commits`). It is refused when the path overlaps a `--paths` item, is shadowed by a `.publish/` file, or is not on the public main. The commit message gains a `Removed from this repository:` list; name those paths in the PR body too.

To publish a milestone's release notes, use `publish.sh release <tag> --title "<title>" --notes-file <f>` (`--check` only scrubs). `wrapup.sh run` calls it.

2. The scrub gate runs inside prepare, and again in `scrub`, `request` and `merge`. It accepts only prepare's shape: exactly one commit on the public base (for an empty public repo, the empty root plus one commit). Any other branch is refused with its commit count; prepare it again instead of adding commits to it. The gate scans that commit's diff, its message and the PR body. When it finds anything, it creates nothing and lists every hit (`<file>:<line>`, `<path>: path name`, `commit <sha> message:<line>`, `body:<line>`). A hit is:
   - a private repo's `owner/repo` (any case) or its bare name (exact case; names under 5 characters and the roster's `scrub_allow` are checked only as `owner/repo`);
   - a local `/Users/…/` or `/home/…/` path, a filled-in `BEAST-` line, a dated-records path, words from a closed row of the twin;
   - a roster `scrub` pattern: a string applies to every text file, or `{"pattern": "<regex>", "paths": ["<glob>", …]}` applies only to matching paths;
   - a path name: a secret-shaped file (`wallet.json`, `.env*`, `*.pem`, `*.key`, `id_rsa*`, `id_ed25519*`, `*.p12`, `*.pfx`, `keystore*.json`, `credentials*.json`), or a path carrying a private repo's name or a roster pattern.

   Binary files (a NUL byte in the first 8000 bytes) are not read for content; each one is named on stderr, and its path name is still checked. Fix the content or the message, then prepare again. To check a branch or a body by hand, run `publish.sh scrub <slug> [--body-file <f>]`.

3. Request. Write the PR description for outside readers:
```
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh request <slug> --seat <YOUR SEAT> --body-file <body.md> [--milestone "<title>"]
```
`--milestone` names the twin's open milestone the approval row is filed under; it is required when the twin has one, and checked before anything is pushed. It re-scrubs the branch and the body, pushes, opens the PR on the public repo and files the approval row in the twin (approve with `publish <slug>`). Beast writes nothing else on the PR: no comment, no label, no assignee. The decider answers on the twin's row.

4. On the word:
```
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh merge <slug> --words "<verbatim>" --by <YOUR SEAT> [--record <commit — path>]
```
The words `publish <slug>` (or a bare `approve`) re-scrub, squash-merge the PR, delete the public branch and record the merge in the twin's main. The recording commit has the same tree, so the next pull brings only outside changes. Then it closes the row; push the twin's main afterwards. With `reject: …` it closes the PR unmerged and the row rejected. `revise: …` is not a close. The record defaults to the decider's answer comment on the row. For words typed to a session, record them first and pass `--record`. If the public main carries outside work the twin lacks, merge refuses and tells you to pull first.

5. Pull back outside contributions merged on the public repo. Run it where the twin's main branch is checked out with a clean tree:
```
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh pull
```
On a conflict it aborts, leaves main unchanged and names the files; merge them by hand.
