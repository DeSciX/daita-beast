---
name: census
description: Before a seat files a build or deploy ask, compare what was reviewed with what is served for every target its roster row lists, and put each unshipped finding, or the clean line, into the row. Use for "run the census", "is anything reviewed but not shipped", "what is built but not deployed", before any decision.sh new for a build, deploy or release.
---

# census — reviewed vs served, before you ask for more

Built-but-unshipped work is found before new work is asked for. Before you file a build, deploy or release row, run:
```
${CLAUDE_PLUGIN_ROOT}/scripts/census.sh <YOUR SEAT>
```
It reads the targets of your roster row's `census` field (the shape is in `docs/protocol.md`, Roster) and, for each, the reviewed commit and the served commit, each a full 40-hex sha:

| Reader | Reads |
|---|---|
| `{"git": "<ref>"}` (optional `"dir"`, relative to the main checkout) | the commit the ref names there; nothing is fetched, so fetch first when the ref is a remote one |
| `{"cmd": "<shell command>"}` | run from the main checkout; its whole output, trimmed, must be one 40-hex sha |

It prints `unshipped: <target> reviewed=<sha> served=<sha>` for each target whose two differ, then `census: clean, <N> targets checked` or `census: <k> unshipped of <N> targets checked`. Put every line it printed into the row you file (in `## Decision`, or `## Unblocks` when shipping them is what the row unblocks).

It exits 1, with no summary line, when any target cannot be read (a ref that names no commit, a command that fails or prints anything but one sha), naming each, and when your row lists no `census`. An unread target is never counted clean: fix the reader in the roster (a roster change is a commit on the main checkout) or run it after the fetch it needs, then run the census again.
