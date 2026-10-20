---
name: workstream
description: Open a workstream as one GitHub Project plus its tracking issue in the coordinating repo. Use for "open a workstream for X", "start the airdrop workstream", "new project board for this".
---

# workstream — one GitHub Project, one tracking issue

A workstream is coordinated from one repo and may touch many. Its Project (under the owner that coordinates it, private by default) holds the items: issues and PRs from any repo, including other owners. A workstream has a slug, its id. Its tracking issue, labelled `workstream` and `ws:<slug>` in the master repo (the issue's repo: the master is derived, never stored), holds the northstar verbatim, the repos and their roles, the acceptance, the `## Seats` table (the one owner of which seats are in the workstream: `| Seat | Repo | Home | Agent | Account | Address | Seen |`), and every status report as a comment. Exactly one open issue carries both labels among the roster's owners (`workstream_issue <slug>`, lib.sh); 0 or 2+ is refused naming them.

```
printf '%s\n' "<the definer's words, verbatim>" > /tmp/northstar.md
${CLAUDE_PLUGIN_ROOT}/scripts/workstream.sh new --slug widgets --owner acme --title "WS: <name>" --repo acme/widgets-dev \
  --northstar-file /tmp/northstar.md \
  --milestone "M1 <name>|2026-11-01|<what it delivers>" --milestone "M2 <name>|2026-11-15|<what it delivers>" \
  --repos "acme/widgets-dev — coordination, acme/widgets — the build" \
  --acceptance "<what done is, measurable>"
```
The seat map: `workstream.sh seat-add <slug> <login/LABEL> --repo <owner/repo> --home "<checkout | worktree <branch> | wrapper | subdir <dir>>" --agent <name>` (a private repo; an agent file that exists; `seat.sh new` runs it for a new seat), `seat-remove <slug> <login/LABEL>`, `seats <slug>` (prints the table), and `render <slug> [--pr]` writes the master repo's CLAUDE.md block for this workstream (between `<!-- beast:workstream begin <slug> -->` and its end marker; several workstreams, several blocks): into the local checkout of the master when this machine has one (it prints the commit command), else through the contents API (a file that changed meanwhile is a 409 and nothing is written; `--pr` opens a pull request instead), then re-renders the Beast block of every home on this machine of a seat in the table. `seat-add` and `seat-remove` end with the same render.
At least one `--milestone "<title>|<YYYY-MM-DD>|<what it delivers>"` is required: set out the milestones at the start, so the seat schedules its own work (`/daita-beast:milestone`). They are GitHub milestones on `--repo`, created first, so a bad one writes nothing. Pass `--project <number>` to attach the tracking issue to a Project that already exists.

Then: file decisions with `/daita-beast:decision` (adding `--project <owner>/<number>`), add the issues and PRs the work produces with `source ${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh && project_cmd item-add <number> --owner <owner> --url <issue or PR url>`, and report with `/daita-beast:status`. GitHub Projects exist only behind GraphQL: on a surface that blocks it (Claude Code cloud sessions) `workstream.sh` and `project_cmd` die naming that, and the Project step is done from a surface that has it. A dependency on another repo is an issue filed there and added to this Project. Close the workstream with a final `done` status carrying the acceptance evidence.

A seat's skill opens its workstream when absent: `/daita-beast:seat <LABEL>` asks for these fields and runs `workstream.sh new` itself.

Without a shell (Cowork, claude.ai), use the `connector` skill: its recipe of the same name, or its list of the acts it cannot do.
