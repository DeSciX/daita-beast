---
name: realign
description: Garbage collection for truth. Brings a repo, a personal agent system or a workstream back into agreement with what is built, DELETING stale, superseded or contradictory content instead of annotating it. Two scopes: (a) the personal system (CLAUDE.md files, agents, skills, docs, memory, org/records, KB corpora) after a significant milestone; (b) a workstream's wrap-up, where it folds the milestone's closed decisions into the docs and writes the fold-in manifest that wrapup.sh run checks. Use for "realign", "clean up the drift", "fold the decisions into the docs", "purge the records", "this CLAUDE.md is stale", "the docs are a frankenstein", "before we compact", "wrap up the milestone".
---

# realign — garbage collection for truth

## The thesis

Keep exactly one representation of current reality, and remove every stale or contradictory copy instead of tagging it. This applies to every artifact that can drift: source, docs, agent-instruction files (`CLAUDE.md`, `AGENTS.md`, `SKILL.md`, `.claude/`), memory, dated records and the KB corpora built from them.

**Delete, don't annotate.** A model reading a file weighs the concrete detail of an old design (a signature, an architecture, a plan) far more than a "superseded" label next to it. A clean absence is unambiguous. A labelled contradiction is noise that compounds with every read. So delete the stale content; do not decorate it.

**A decision is spent once it is built.** A ruling recorded against a past release can be active drift against the current one. Once the as-built system and its docs carry a decision, the decision's own record is a second copy of the same fact. Fold its live rule (one line) into the instruction surface or the docs, then delete the record. A red-team or investigation result survives only if the fold-in judges it useful and writes that content into the docs. Its record file is deleted either way.

**Compaction is the same problem.** Stale state carried across a compaction seeds the next window with drift. A pass run just before compaction leaves a clean seed.

This is a judgment skill, and a destructive one. The steps below give a safe procedure. Knowing why drift is harmful is what lets you decide well what counts as superseded.

## The drift you are hunting

1. Fallbacks and legacy code paths left "just in case", which the next agent treats as live.
2. Old docs left in place, patched with "superseded" markers among the as-built content.
3. Wrong-base branches: cut from a stale tip (light touch, see step 5).
4. Instruction files (`CLAUDE.md`, `AGENTS.md`, `SKILL.md`, `.claude/`) carrying the same cruft.
5. Memory accumulating divergent past designs.
6. Compaction drift: stale state surviving into the next window.
7. Durable docs citing transient ones: a canonical file pointing at a WIP design or a handoff. Anything worth a pointer belongs in canonical docs.
8. Canonical docs that did not move with the behaviour: the contract changed and its doc did not.
9. Spent decisions: dated records, close comments and desk answers whose rule the as-built docs now carry, or whose release has passed.

## Step 0: pick the scope and the safety net

- **(a) Personal system:** your own agentic system on your private repos: every `CLAUDE.md`, the agents and skills, `docs/`, memory, `org/records` and the DeSciX KB corpora built from them. Run it after any significant milestone. Git is the undo, so stage the pass for one approval, then commit.
- **(b) Workstream:** one repo's milestone, as part of its wrap-up (`/daita-beast:wrapup`). Its input is the plan's fold-in list (`wrapup.sh brief "<milestone>"`). Its output is one fold-in commit plus its manifest, which `wrapup.sh run` checks before it deletes anything.
- **A live thread or planning doc without git:** quarantine first. Copy what you remove to `.realign-quarantine/<ISO date>/<path>`, then delete it from the live artifact. For the thread itself, write a short note saying what was superseded and why, then stop restating it.

## Step 1: name the anchor

You cannot align to reality without naming it, and you never invent a new anchor doc (that would be a second source of truth).

- **What is:** the working, verified code is the truth for how things behave. Where a doc and the code disagree, the code wins, unless the code is what is being corrected toward a newer explicit decision.
- **What should be:** the repo's declared anchors: the root `CLAUDE.md` (sub-files extend it, never contradict it), a named architecture or contract doc, a living audit.
- **De-canonicalized files stay so:** when an anchor says a file is not the source of truth, never reconcile toward it, and flag it if it has drifted back into use.

Write the one line: *what am I aligning everything to?* Everything you delete, you delete because it contradicts or duplicates that anchor.

## Step 2: surface the candidates (delete nothing yet)

```
${CLAUDE_PLUGIN_ROOT}/scripts/realign/surface_candidates.sh <repo-root>
```

It sweeps the tracked files for tombstone markers, dead-fallback patterns, "do not use" and "old approach" prose, versioned sibling docs, relative links and protected trees, grouped by kind. It only reports. Judge each candidate against the anchor: delete it if it contradicts or duplicates the anchor. Leave it if it is old but still true, or protected.

## Step 3: protected paths (never auto-delete)

Build the protected set from what the repo designates, plus:

- load-bearing proofs and correctness artifacts (removing them breaks the build or the argument);
- frozen reference fixtures marked "never distribute";
- `archive/` trees, the intended home of superseded code;
- generated and build artifacts (`dist/`, generated SDKs, machine-generated reports): regenerate them, never hand-edit or hand-delete them;
- security-sensitive code: auth, wallet, keys;
- living audit or inventory docs: update their status in place;
- anything the repo's `CLAUDE.md` or `AGENTS.md` names protected, immutable or canonical.

`archive/` is a one-way sink. Live code may not import, include or read anything inside it. A reference into it from outside is the bug: promote the needed thing back into the canonical surface, or delete the dead caller. `scripts/realign/check_archive_boundary.sh <repo-root> [--strict] [--staged]` finds such references. `scripts/realign/pre-commit` installs the check as a blocking hook.

When unsure whether something is protected, treat it as protected and surface it to the human.

## Step 4: fold, then delete

- **Code (git is the undo):** make the deletions and edits, run the repo's checks, and present `git diff --stat`, the diff and the report for one approval before committing. Commit only the paths you changed, by name.
- **Never soften a deletion into an annotation** to play it safe: that is the disease. If you are not confident enough to delete, surface the candidate; do not tombstone it.

### Scope (a): the personal system

1. **Instruction surfaces** (`CLAUDE.md`, agent stubs, skills): current rules only, a one-line why at most. No history, no "(formerly X)", no supersession banners.
2. **Records** (`org/records` and the like): for each record, either its rule is live and not yet in an instruction surface or the docs (promote it there as one line, then delete the record), or it is spent (delete it). An investigation or red-team record survives only by having its useful content written into `docs/`; the file itself goes.
3. **Docs:** as-built truth only. Delete plans, proposals and dated narrative, or move them to the concepts plane.
4. **Memory:** one canonical statement per topic. Run `scripts/realign/check_memory_drift.sh <dir>` (`--strict` to gate). Fold durable conclusions into the index, delete the memos whose work has landed, collapse version clusters (`…_m2/_m3`, `…_v2`) to the current one, resolve or delete every "not reconciled" entry, and prune the index to match.
5. **KB corpora:** re-sync each KB whose manifest's sources cover a changed doc. The manifests are `.descix/manifests/*.json`; after pushing, run `npx -y -p @descix/cli@3.0.0 descix kb corpus sync -a <app_id> -k <kb> --dry-run`, then again without `--dry-run`.

### Scope (b): a workstream's wrap-up

1. `wrapup.sh brief "<milestone>"` prints each closed row of the milestone (its url, title, words and record) and the milestone's `Report:` line.
2. Fold each row into the as-built docs and the instruction surfaces as current truth, deleting what it supersedes. A row whose content is already there needs only its citation.
3. A row that leaves nothing to fold (rejected, superseded, a one-off act) is dropped explicitly. Add one line to the manifest `.beast/wrapup/<milestone slug>/fold-in.md`, in this shape:
   ```
   dropped: <row url> — <why>
   ```
4. Commit the doc changes and the manifest in ONE commit. Its message cites the url of every row you folded. Push it to the default branch.
5. `wrapup.sh run "<milestone>" … --fold-in <sha>` refuses, naming each row, when a closed row is neither cited in that message nor dropped in the manifest, and when rows are cited but the commit changes no file. Only then does it delete. "Folded into the docs" is checked, not assumed.

## Step 5: branch hygiene (warn only)

`scripts/realign/check_branch_base.sh <repo-root>` reports branches, worktrees and their distance from the canonical base. Check the base before cutting a branch. Report stale or orphaned branches and worktrees, and never delete them in this pass.

## Step 6: leave a clean seed

Every pass leaves a short report:

1. what was removed, from which artifact class, with a one-line reason tied to the anchor;
2. what is now canonical (the step 1 line);
3. what diverged and why, so the next agent does not re-derive it;
4. what was flagged and not touched (protected paths, branches, anything needing a human call).

It goes where the repo already records handoffs, never into a new changelog. For a Beast seat that is its tracking issue: `status.sh <tracking> --seat <SEAT> --state done|handoff --next "…" --text-file <report>`. For a wrap-up, the fold-in commit message carries it. When the pass runs before a compaction, the report is the seed: a fresh window reading only it must know the current state and the drift just removed.

## Do not stop at "we have done a lot"

A stopping point that leaves drift behind (an undeleted branch, an unconsolidated memory, contradictory files, an unrun realign) is debt that lands on the next agent. There are two legitimate ways to stop. Close the work properly (realign, consolidate, merge, delete, retire the handoff), or preserve it cleanly with a handoff that captures the in-flight state without contradictions.
