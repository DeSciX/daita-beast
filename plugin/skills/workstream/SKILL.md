---
name: workstream
description: Open a workstream as one GitHub Project plus its tracking issue in the coordinating repo. Use for "open a workstream for X", "start the airdrop workstream", "new project board for this".
---

# workstream — one GitHub Project, one tracking issue

A workstream is coordinated from one repo and may touch many. Its Project (under the owner that coordinates it, private by default) holds the items: issues and PRs from any repo, including other owners. Its tracking issue, labelled `workstream` in the coordinating repo, holds the northstar verbatim, the repos and their roles, the acceptance, the seats, and every status report as a comment.

```
printf '%s\n' "<the definer's words, verbatim>" > /tmp/northstar.md
${CLAUDE_PLUGIN_ROOT}/scripts/workstream.sh new --owner acme --title "WS: <name>" --repo acme/widgets-dev \
  --northstar-file /tmp/northstar.md \
  --milestone "M1 <name>|2026-11-01|<what it delivers>" --milestone "M2 <name>|2026-11-15|<what it delivers>" \
  --repos "acme/widgets-dev — coordination, acme/widgets — the build" \
  --acceptance "<what done is, measurable>" --seats "BUILDER — build — <login>"
```
At least one `--milestone "<title>|<YYYY-MM-DD>|<what it delivers>"` is required: set out the milestones at the start, so the seat schedules its own work (`/daita-beast:milestone`). They are GitHub milestones on `--repo`, created first, so a bad one writes nothing. Pass `--project <number>` to attach the tracking issue to a Project that already exists.

Then: file decisions with `/daita-beast:decision` (adding `--project <owner>/<number>`), add the issues and PRs the work produces with `source ${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh && project_cmd item-add <number> --owner <owner> --url <issue or PR url>`, and report with `/daita-beast:status`. GitHub Projects exist only behind GraphQL: on a surface that blocks it (Claude Code cloud sessions) `workstream.sh` and `project_cmd` die naming that, and the Project step is done from a surface that has it. A dependency on another repo is an issue filed there and added to this Project. Close the workstream with a final `done` status carrying the acceptance evidence.
