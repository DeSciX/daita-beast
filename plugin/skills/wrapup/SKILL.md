---
name: wrapup
description: Wrap up a milestone in a private repo. Publish release notes for outside readers, fold the milestone's closed decisions into the docs, then delete its coordination traffic (closed rows, spent desk asks and messages, old status and acks, dated records) so the board starts the next milestone clean. Use for "wrap up M4", "close out the milestone", "clean the board", "release notes for the milestone", "purge the decisions".
---

# wrapup — a milestone's release notes, fold-in and clean-out

A decision recorded against a past release can be active drift against the current one, and a board with hundreds of spent comments hides the open ones. At a milestone's end, the wrap-up turns what the milestone decided into current truth in the docs. Then it deletes the traffic. Deleting an issue needs admin rights and cannot be undone, so the plan is approved on a row first, and the run deletes nothing the approved plan does not list.

Run every step in a checkout of the repo (the twin). The default repo is the roster `repo`.

1. **Plan.** It posts nothing:
```
${CLAUDE_PLUGIN_ROOT}/scripts/wrapup.sh plan "<milestone>" [--carry "<next milestone>"]
```
It writes `.beast/wrapup/<slug>/plan.json` and prints three lists:
   - **DELETE:**
     - the closed decision rows under the milestone;
     - the closed PR rows' coordination comments (a PR itself cannot be deleted);
     - on the desks: the asks answered or withdrawn (with their answers) and the messages older than the plan;
     - on the seats' tracking issues: the `BEAST-STATUS` and `BEAST-ACK` comments older than the plan, except each seat's newest handoff;
     - the dated record files the closed rows name;
     - the plan's own directory.
   - **KEEP:** the open items, carried to the next milestone, and every seat's `BEAST-NOTES`.
   - **FOLD IN:** each closed row's title, words and record, and the milestone's `Report:` line.

2. **Request.** It files one row:
```
${CLAUDE_PLUGIN_ROOT}/scripts/wrapup.sh request "<milestone>" --seat <YOUR SEAT>
```
It commits the plan file to the default branch (that one path, through the API) and files a decision row that links the plan at that commit with its digest, approved with `wrap up <milestone>`. Run `git pull` afterwards.

3. **Fold in.** Use the realign skill, scope b:
```
${CLAUDE_PLUGIN_ROOT}/scripts/wrapup.sh brief "<milestone>"
```
   - Fold each row into the as-built docs and instruction surfaces as current truth.
   - Commit the doc changes in ONE commit whose message cites the url of every row you folded.
   - A row with nothing to fold goes in the same commit, as `dropped: <row url> — <why>` in `.beast/wrapup/<slug>/fold-in.md`.
   - A red-team or investigation record survives only if you write its useful content into the docs.
   - Push the commit.

4. **Release notes.** `wrapup.sh notes "<milestone>"` prints the draft: the merged PRs' titles, the approved decisions' titles and the outside contributors (`report.sh milestone --outside-notes`). Edit it for outside readers if needed. The scrub gate refuses a private repo's name or slug, a local path, a `BEAST-` line, a record path or the decider's words.

5. **Run.** It only runs after the decider's word on the row:
```
${CLAUDE_PLUGIN_ROOT}/scripts/wrapup.sh run "<milestone>" --words "<verbatim>" --by <YOUR SEAT> --fold-in <sha> [--notes <file>] [--tag <tag>]
```
   - **It refuses, writing nothing, when:**
     - the decider's standing answer on the row is not the approve;
     - the plan's digest differs from the one the row names;
     - any closed row is neither cited in the fold-in commit nor dropped in its manifest (each such row is named);
     - the notes fail the scrub.
   - **Then, in order:**
     - the GitHub Release on the public repo (`publish.sh release`), or the notes printed when the roster has no `publishes_to`;
     - the deletes, each logged;
     - the desks republished;
     - the milestone closed, with its open items carried;
     - one comment on your tracking issue: `milestone <M> closed: <release link>, <n> rows folded`;
     - the row closed on the words, with the board republished;
     - the DeSciX KB manifests that cover a changed file, with the `npx -y -p @descix/cli@3.0.0 descix kb corpus sync …` command for you to run after you pull and push.

A rerun after an interruption finishes the work: an item already deleted is logged as gone, and the release is reused when its tag, title and notes match.
