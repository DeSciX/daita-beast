---
name: install
description: Set Beast up on the surface you are running on — Claude Code local, Claude Code in the cloud, or Cowork / Claude.ai chat — detecting the surface from evidence, then doing only that surface's install (tools, permissions, roster, relay, or the GitHub connector) and proving it with a fixture. Use for "install beast", "set up beast here", "set up beast for this repo", "beast doesn't work in cowork/cloud".
---

# install — one entry point, three surfaces

Beast is a protocol on GitHub objects (`docs/protocol.md`). What differs per surface is only HOW GitHub is reached and what can run. Detect the surface first, from evidence, and say which one and why before acting. Never guess, never run two branches.

## 0. Detect the surface

| Evidence | Surface |
|---|---|
| You have a Bash tool and `command -v claude` prints a path | **A. Claude Code, local** |
| You have a Bash tool; `gh api user -q .login` works; `gh api graphql -f query='{viewer{login}}'` is refused, or `printenv GH_TOKEN` prints `proxy-injected` | **B. Claude Code, cloud** (GitHub through the sandbox proxy: REST only, attached repos only) |
| You have no Bash tool and your tool list has GitHub connector tools (search/list issues, get issue, create comment) | **C. Cowork or Claude.ai chat** (no shell; the GitHub MCP connector is the only GitHub) |

Anything else (a Bash tool but no `gh`; no Bash and no GitHub connector): stop and say what is missing; the fixes are below under the surface the person wants.

## A. Claude Code, local

1. Tools: `gh` logged in (`gh auth status`; the `project` scope only if workstreams will be opened: `gh auth refresh -s project`), `jq`, `git`. Report each as measured.
2. Plugin: if you are running from `--plugin-dir`, offer the marketplace install and run it on the word: `claude plugin marketplace add DeSciX/DAITA` then `claude plugin install daita-beast@daita --scope project`. The DeSciX connector is the `daita` plugin's job (`/daita:descix-setup`); install `daita@daita` too, never re-derive its setup here.
3. Hooks: `hooks/hooks.json` carries two. SessionStart → `scripts/seat-hello.sh`: in a seat's home (`.beast/seat.json`) it tells the session its seat and first act, and after a compaction to post the handoff; elsewhere it is silent. Permissions: a PreToolUse hook (`scripts/permit.sh`) that allows a Bash call whose whole command is one of this plugin's scripts with plain arguments, nothing else; no settings edit is needed and a plugin cannot ship permission rules. Verify once: run `${CLAUDE_PLUGIN_ROOT}/scripts/seats.sh list` (no prompt) and `ls ${CLAUDE_PLUGIN_ROOT}/scripts` (prompts, unless the user's own rules allow it).
4. Repo: `${CLAUDE_PLUGIN_ROOT}/scripts/bootstrap.sh --repo <owner/repo> --path <checkout> --seat <LABEL> [--orchestrator <LABEL>] [--board <owner/repo>] [--token <SYMBOL>]` (labels, templates, roster, the committed cloud pointer skill `.claude/skills/beast/SKILL.md`; `--token` only when the repo takes outside contributions). Fill the roster, commit `.beast/`, `.github/ISSUE_TEMPLATE/`, `.claude/skills/beast/`.
5. Seat: open the workstream (`/daita-beast:workstream`), then `/daita-beast:seat` (it scopes the seat with the person first, then runs `seat.sh new <LABEL> --repo-path <checkout> …`) (`/daita-beast:seat`: the roster row and the seat's home, checkout, worktree, wrapper or subdir). Open a session in the home it prints; the SessionStart hook names the seat there, and its first act is `/daita-beast:join <LABEL>` (address, the CLAUDE.md block, memory audit, resume).
6. Relay (one per machine, for the coordinating checkout whose roster names every seat): the messenger must run in the SEATS' permission mode, because a receiver holds a message from a sender in another mode. Read `relay.permissionMode` from that roster; if absent ask once ("which permission mode do your seat sessions run in: default, acceptEdits, auto, bypassPermissions?"), write the answer into the roster as `"relay": {"permissionMode": "<mode>"}`, then `${CLAUDE_PLUGIN_ROOT}/scripts/install-relay.sh --repo <coordinating checkout> --permission-mode <mode>`.
7. Prove it: file a fixture (`decision.sh new --repo <repo> --assignee <login> --seat <LABEL> --title "FIXTURE install <UTC>" …`), wait two ticks (≤ 4 min), the `BEAST-EVENT kind=NEW` line arrives in this session; close it (`decision.sh close … --by <LABEL>`), the DECIDED line arrives. Report both lines verbatim. No line in 4 min: `install-relay.sh --status`, then compare the mode in `~/.beast/relay.log` ("relay (haiku, <mode>)") with the seats' mode.
8. Hand the decider `docs/connector-access.md` if they answer from the Claude.ai board.

## B. Claude Code, cloud

Plugins are not installed in a cloud session; a committed skill is. The repo must carry `.claude/skills/beast/SKILL.md` (written by step A.4 on a local machine and committed). If you are reading this skill in a cloud session, that pointer brought you here. Then:
1. `git clone --depth 1 https://github.com/DeSciX/daita-beast "$HOME/daita-beast"` (or `git -C "$HOME/daita-beast" pull`), scripts at `$HOME/daita-beast/plugin/scripts`, each verb's text at `$HOME/daita-beast/plugin/skills/<verb>/SKILL.md`.
2. Every wake: `seats.sh record <LABEL> "<ListAgents name>"` (inbound only: nothing on this surface can message out to a local seat), then `decision.sh inbox <LABEL>` (computed from acks on GitHub, identical on every machine), act, `ack.sh` each row, then `resume.sh <LABEL>`.
3. Limits, stated, never worked around: GraphQL is blocked, so GitHub Projects verbs refuse by name and board pinning degrades to a warning; only repositories attached to the session are reachable (`add_repo {owner, repo, access:"push"}` attaches one when the session has that tool; org-level API paths are refused; otherwise a decision for an unattached repo is one line to a local seat, who files it); the proxy appends a `_Generated by Claude Code_` footer to issue bodies it creates, which lands inside the last section (`## Record`): say so in the row rather than editing it out; nothing pushes a decision in, the inbox at each wake is the whole hearing; the relay never runs here. The GraphQL refusal reads `HTTP 403: GitHub GraphQL is not available from Claude Code sessions; use the REST API` and is the evidence for this surface.
4. The repo's cloud environment setup script may carry the clone line so step 1 is automatic; that file is the owner's, offer the line, never write it unasked.

## C. Cowork or Claude.ai chat

No shell: the protocol runs as GitHub connector calls, the recipes are `/daita-beast:connector`. Install: Customize › Plugins › Add marketplace `DeSciX/DAITA` › install `daita-beast` (and `daita` for the DeSciX connector). Then, first, the connector-access test from `docs/connector-access.md`: fetch one known private issue by number through the connector (the repo's workstream tracking issue, or any `decision` issue the roster's board lists); denied or not found means access, not query, and the doc's symptom table names the fix (the GitHub app is installed per account: once per organization and once on the personal account, each with its repository list). Only then run the connector recipes. A Cowork seat hears nothing pushed; its inbox is the connector inbox recipe at each wake (computed from acks, nothing local), and it acks by the connector ack recipe, and the decider's surface is the board artifact: publish it for them with `/daita-beast:board-ui` (the template is in the plugin; the connector's display name `github` is a constant in it, so a differently named connector is reported, never patched in the session).

## Always

Report what was measured, not what should work: the command, the line it printed. A step that was skipped is named as skipped. Nothing here reads DeSciX platform source; the DeSciX side is the `daita` plugin and the published CLI.
