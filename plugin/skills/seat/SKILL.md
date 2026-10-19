---
name: seat
description: Scope and create a seat (always with the person, before anything is written), find where a seat lives, or retire one. A seat's home is the directory the seat works in once seated (the repo checkout, a worktree, a wrapper, or a subdir of the checkout with its own CLAUDE.md), so its CLAUDE.md and working tree never mix with another seat's; seating (join.sh, from any directory) sets it as the session's root. Use for "make a new seat", "add a DOCS seat beside BUILDER", "where does BEAST live", "where is this seat's root", "retire this seat".
---

# seat — a seat's roster row and its home

**New seat: scope it with the person first.** A seat is never created from wherever the current shell happens to be. Before running anything:

1. **Target repo.** If the person did not name the repo the seat will work in, ask (AskUserQuestion, with the repos the workspace's CLAUDE.md lists as options). The answer is a checkout path; it is passed as `--repo-path`, never inferred from the shell's cwd.
2. **Read what the workspace already says.** Read the CLAUDE.md of the session's own directory (the workspace's master instructions), the target repo's CLAUDE.md, and the CLAUDE.md of any repo they name as related (an R&D playground that feeds a public app repo, an app repo that releases another's work). List each repo's `.claude/agents` and `.claude/skills`, and the seats already in each roster.
3. **Discuss, in one message, then wait for the person's answer.** Cover:
   - Where the daily work happens (the home) versus where it ships. An R&D playground is usually the home; the release repo gets PRs and uploads from it.
   - The home kind `seat.sh` would pick, and why; or a subdir of the checkout that already has its own CLAUDE.md and specialists (only ever named explicitly).
   - Which in-repo specialists the seat will hire, and which are missing. A missing specialist is a new agent definition in the HOME repo's `.claude/agents`, so the seat's session loads it. A specialist that must keep what it learns declares `memory: project` in its frontmatter: its memory is `.claude/agent-memory/<name>/` in that repo, committed, so it is the specialist's own (never the seat's) and travels to a cloud session with the repo (Claude Code loads the first 200 lines of its `MEMORY.md` into the specialist; code.claude.com/docs/en/sub-agents).
   - What the master CLAUDE.md implies for this seat: its lane, platform wall and records, and any rule that points the seat elsewhere.
   - The label, the role (an agent file in the HOME repo's `.claude/agents/<name>.md` that specializes the plugin's generic `daita-beast:seat`, or `daita-beast:seat` itself), and the workstream slug (an existing workstream, or `/daita-beast:workstream` to open one). The seat's id is `<slug>/<LABEL>/<login>`.
4. **Only on the person's answer,** create it. The workstream must exist (its tracking issue carries the labels `workstream` and `ws:<slug>`); `/daita-beast:workstream` opens one. The seat's repo must be private:
```
${CLAUDE_PLUGIN_ROOT}/scripts/seat.sh new <LABEL> --repo-path <checkout> --agent <name | daita-beast:seat> --workstream <slug> [--kind checkout|worktree|wrapper | --kind subdir --dir <dir>]
```
One act: it adds the roster row (held by the gh login running it; lane from the repo CLAUDE.md `LANE:` line; a label is unique per login; `agent`, `workstream`, `home: {kind, branch}` or `{kind: "subdir", dir}`), creates the home, adds the seat to the workstream issue's `## Seats` table (`workstream.sh seat-add`, the one owner of the seat map) and renders the master repo's CLAUDE.md block (`workstream.sh render`). Without `--kind` it picks:

| Kind | Home | When |
|---|---|---|
| checkout | the repo's main checkout | no other seat of this login is homed in the checkout |
| worktree | `<repo-parent>/<repo>.seats/<LABEL>`, branch `seat/<LABEL>` | the checkout is taken, and the repo has no submodules or nested git repos |
| wrapper | `~/.beast/homes/<login>/<LABEL>/`: a `CLAUDE.md` that imports the repo's and carries the Beast block, and `claude.sh` | the checkout is taken, and the repo has submodules or nested repos (a worktree would not carry them) |
| subdir | `<checkout>/<dir>`: a directory of the checkout (not a repo root) with its own CLAUDE.md, which gets the Beast block | never picked: only `--kind subdir --dir <dir>`; refused when the dir has no CLAUDE.md, is or is inside another repo, or homes another seat |

Every home gets `.beast/seat.json` (`{id, kind}`, plus `root` for a wrapper; the rest is read from the roster). It is machine-local: for checkout and worktree homes `seat.sh` adds `.beast/seat.json` to the home's `.gitignore`, for a subdir home `<dir>/.beast/seat.json` to the checkout's, and says so. It refuses a home path that exists and is not this seat's, a checkout already homing another seat, and a `seat/<LABEL>` branch checked out elsewhere (with or without uncommitted changes).

Then take the seat: start a session anywhere in the workspace (no new window or folder per seat) and run `/daita-beast:join <LABEL>` (`join.sh <LABEL>`, from any directory). It prints `SEATED <id> at <home>`; from then on the home is the session's root: every shell command starts with `cd <home> &&` or uses `git -C <home>` and absolute paths, every file edit uses an absolute path under the home, and `<home>/CLAUDE.md` is read at seating and after any compaction. Two seats never share a home; any number share a launch folder or a VS Code window. Optional, for terminal users: a wrapper's `<home>/claude.sh` starts a session in the wrapper with `claude --add-dir <repo>`, which loads the repo's agents, skills and the imported CLAUDE.md (`additionalDirectories` in settings loads none of them, measured 2026-10-15). Commit the roster (and the `.gitignore`) in the main checkout.

A roster row written before homes (no `home`) is read as a checkout home, and join says so once; record it with `seat.sh new <LABEL> --repo-path <checkout> --kind checkout` (with `--agent` and `--workstream` when the row has none yet).

**Where:** `${CLAUDE_PLUGIN_ROOT}/scripts/seat.sh where <LABEL | login/LABEL>`, from any directory, prints the home path and kind on this machine (found as join finds it; the path is derived from the kind, never stored in the roster), and says when the home is absent here.

**Retire:** `${CLAUDE_PLUGIN_ROOT}/scripts/seat.sh retire <LABEL | login/LABEL>` removes the seat from its workstream's `## Seats` table, re-renders the master block and sets `"retired": "<date>"` on the roster row. The home, the branch and the GitHub comments are kept; remove a worktree by hand (`git worktree remove`) once its branch is merged or abandoned. Commit the roster.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
