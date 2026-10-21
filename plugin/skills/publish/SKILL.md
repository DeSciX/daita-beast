---
name: publish
description: Publish chosen changes of a private twin to its public repo — one new scrubbed commit on a PR there, approved on a row in the twin, squash-merged on the word — and pull outside contributions back. Use for "publish this to the public repo", "release X publicly", "the owner approved the publish, merge it", "pull the public repo's contributions into the twin".
---

# publish — from the private twin to its public repo

A public product has a private twin: the roster's `repo`, whose `publishes_to` names the public repo. All work and coordination happen in the twin. `publish.sh` is the only writer to the public repo, and it writes only a publish: a branch, its PR, the squash-merge and the branch's deletion. Every coordination write (row, desk, status, notes, ack, review request) to the public repo is refused by the other scripts. Run it in a checkout of the twin. The public repo must already exist; creating it is its owner's act. The scripts read the roster from the repo's main checkout, never a worktree; try a roster change in a clone of the repo.

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

When the roster has `license`, prepare and request first run the license gate (`license.sh check` on the publish commit, `/daita-beast:license`): a public tree without the license file, with a drifted body or header, or with a manifest not pointing at it is refused, and nothing is created or pushed.

2. The scrub gate runs inside prepare, and again in `scrub`, `request` and `merge`. It accepts only prepare's shape: exactly one commit on the public base (for an empty public repo, the empty root plus one commit). Any other branch is refused with its commit count; prepare it again instead of adding commits to it. The gate scans that commit's diff, its message and the PR body. When it finds anything, it creates nothing and lists every hit (`<file>:<line>`, `<path>: path name`, `commit <sha> message:<line>`, `body:<line>`). A hit is:
   - a private repo's `owner/repo` (any case) or its bare name (exact case; names under 5 characters and the roster's `scrub_allow` are checked only as `owner/repo`);
   - a local `/Users/…/` or `/home/…/` path, a filled-in `BEAST-` line, a dated-records path;
   - words from a closed row of the twin: a stretch of 5 consecutive words with at least 2 outside the common words (stopwords and approve, publish, merge, close, revise, reject, record), case, whitespace and punctuation folded. A row closed on exactly its own approving phrase is skipped. A phrase the roster lists in `scrub_allow_words` is allowed: one of 5 words or more drops every stretch inside it; a shorter one makes its words common (they stop counting toward the 2), and nothing beyond that;
   - a roster `scrub` pattern: a string applies to every text file, or `{"pattern": "<regex>", "paths": ["<glob>", …]}` applies only to matching paths;
   - a path name: a secret-shaped file (`wallet.json`, `.env*`, `*.pem`, `*.key`, `id_rsa*`, `id_ed25519*`, `*.p12`, `*.pfx`, `keystore*.json`, `credentials*.json`), or a path carrying a private repo's name or a roster pattern.

   The private-repo class lists every private repo of every owner the roster names (its `repo`, `publishes_to`, `board` and seat repos). **Each organization publishes its own public repos from its own twin, with a login that can list that owner's private repos.** A listing that cannot be made (another person's account, or an org listing that fails) refuses the publish, naming the owner and the gh login: run it as a login that can list that owner's private repos, from that owner's own twin. `workstream_owners` (another owner's workstream this repo's seats join) adds no owner to this list.

   Under a directory of the roster's top-level `vendored` (byte-exact upstream copies), a file's content is not checked for private repos, private names, closed-row words or roster `scrub` patterns; local paths, `BEAST-` lines, records paths and path names are still checked there. Binary files (a NUL byte in the first 8000 bytes) are not read for content; each one is named on stderr, and its path name is still checked. Fix the content or the message, then prepare again. To check a branch or a body by hand, run `publish.sh scrub <slug> [--body-file <f>]`.

3. Request. Write the PR description for outside readers:
```
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh request <slug> --seat <YOUR SEAT> --body-file <body.md> [--milestone "<title>"]
```
`--milestone` names the twin's open milestone the approval row is filed under; it is required when the twin has one, and checked before anything is pushed. It re-scrubs the branch and the body, pushes, opens the PR on the public repo and files the approval row in the twin (approve with `publish <slug>`). Beast writes nothing else on the PR: no comment, no label, no assignee. The decider answers on the twin's row.

4. Amend, when the decider changes the scope after the PR is open (the row must still be open):
```
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh prepare <slug> --amend --paths <path>... --message-file <msg.txt>
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh request <slug> --amend --seat <YOUR SEAT> [--body-file <body.md>]
```
prepare rebuilds the one commit on the current public base and reruns both gates; it refuses a slug never requested, a closed row, and no change. request re-gates, force-pushes the PR branch with `--force-with-lease` on the PR's head (the only force-push Beast makes; refused if someone else pushed to the branch), retitles the PR (body when given) and posts one line on the row: `Amended at <UTC>: <n> files; added …; removed …; changed …`. An approval from before that line no longer counts: the decider approves again on the row, and merge takes it only from the row (no `--record`).

5. On the word:
```
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh merge <slug> --words "<verbatim>" --by <YOUR SEAT> [--record <commit — path>]
```
The words `publish <slug>` (or a bare `approve`) re-scrub, squash-merge the PR, delete the public branch and record the merge in the twin's main. The recording commit has the same tree, so the next pull brings only outside changes. Then it closes the row; push the twin's main afterwards. With `reject: …` it closes the PR unmerged and the row rejected. `revise: …` is not a close. The record defaults to the decider's answer comment on the row. For words typed to a session, record them first and pass `--record`. If the public main carries outside work the twin lacks, merge refuses and tells you to pull first.

Under your seat's standing latitude (the decider's recorded word letting you merge your own publishes), merge with no words of theirs:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh merge <slug> --latitude '<owner/repo> <commit> — <path>' --by <YOUR SEAT>
```

The record is a file at that commit in your seat's own repo, which must be private and not public-intended. GitHub is checked for the repo, the commit and the file before anything is written. `--latitude` excludes `--words` and `--record`. It is refused while the decider's `revise:` on the row has no amend after it, and on an amended row the decider has not approved since the amend. The merge itself is the same. The row closes as `Merged under standing latitude <link> by <your seat id>` and quotes no words. The board, the relay and the decider's digest show it as kind `latitude` with the record linked, for the decider to audit. Whether a publish falls inside your latitude is your own repo's rule, never the plugin's: check it before you run this.

6. Pull back outside contributions merged on the public repo. Run it where the twin's main branch is checked out with a clean tree:
```
${CLAUDE_PLUGIN_ROOT}/scripts/publish.sh pull
```
On a conflict it aborts, leaves main unchanged and names the files; merge them by hand.

For another tool or a test, the stable interface to the scrub is `publish.sh scan` (protocol, Publishing): `--base <ref>` or `--tree <dir>`, one `<file>:<line> <class> <match>` line per hit, exit 1 on a hit, 0 clean, 2 on an error; `--dump-patterns > f` then `--patterns-file f` runs it offline. Never source `lib.sh` or slice its functions: they are internal.
