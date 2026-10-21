---
name: license
description: Render the roster's license from its canonical source and check that a tree, a publish, or every public repo of the roster's owners carries it — the file present, its body equal to the render, a clean neutral header, every package.json and plugin.json pointing at it. Read-only. Use for "which public repos lack our license", "is the license in place", "render the license file", "audit the licenses".
---

# license — the license every public repo carries

The roster's `license` (`.beast/roster.json`; shape in `docs/protocol.md`, License) names the license: its display `name`, the `file` it lives in (`LICENSE.md`), the `manifest` value (`SEE LICENSE IN LICENSE.md`) and its one canonical `source` (a repo and path, an optional `render` command, an optional local `checkout`). `license.sh` is the one owner of license checks. It reads; it never writes to GitHub. The scripts read the roster from the repo's main checkout, never a worktree; try a roster change in a clone of the repo.

1. Render the expected file, from the twin:
```
${CLAUDE_PLUGIN_ROOT}/scripts/license.sh render -o LICENSE.md
```
It reads the source (the local checkout's HEAD when the roster names one, else GitHub), renders it (a LaTeX source through `pandoc/latex-crossrefs.lua`, which numbers headings and prints every `\ref` as the PDF does, from the source's own class and `\the<counter>` formats, and fails naming any numbering command it does not follow), and puts one neutral header line above it: `<!-- <name>. Rendered from its canonical source; do not edit by hand. -->`. The header names no repo. Commit the file; never edit it by hand.

2. Check a tree: a directory, or a commit or branch of the repo you stand in:
```
${CLAUDE_PLUGIN_ROOT}/scripts/license.sh check <dir | tree-ish>
```
Each item prints `ok` or `MISS`: the file is present; its body after the header equals the render byte for byte; the header is the neutral line and the publish scrub gate finds nothing in it (a private repo, a local path, …); `package.json` and every `.claude-plugin/plugin.json` say `"license": "<manifest>"`. It exits 1 on any miss. A directory in a git work tree is read through its tracked files only, so untracked copies (a stale worktree, `node_modules`) are never checked; a directory outside git is walked whole, said on stderr.

3. Audit every public repo of every owner the roster names, at its default branch, through the API (no clone):
```
${CLAUDE_PLUGIN_ROOT}/scripts/license.sh audit
```
It prints one table (repo | license file | body matches | header clean | manifests | twin seat) and exits 1 when any row misses. The twin seat is the rostered seat whose private twin publishes to that repo; `-` means no rostered twin publishes it. A repo the roster's license `exempt` lists (under its own license, e.g. a fork of an upstream project) shows `exempt` and is never a miss; an exempt entry that names no public repo of the owners fails the audit.

When the roster has `license`, `publish.sh prepare` and `request` run the same check on the publish commit and refuse a public tree that misses. A twin fixes a miss in itself: render the file, set the manifests, commit on main, then `publish.sh prepare <slug> --paths LICENSE.md package.json <plugin manifests> --message-file <f>` and the publish steps (`/daita-beast:publish`). For a review across all public repos, hire the `license-reviewer` agent.
