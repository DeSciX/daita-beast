---
name: board-ui
description: Publish the decisions board as a claude.ai artifact for one decider — a page that lists their open decisions across repos and posts their answers through their own GitHub connector. Use for "set up my decisions board", "publish the board page", "the board shows nothing / misses a repo", "republish the board after a spec change". Runs only in a claude.ai or Cowork session that has the `github` connector and the Artifact tool.
---

# board-ui — the decider's board in claude.ai

The page is `${CLAUDE_PLUGIN_ROOT}/templates/board.html`; its spec is `docs/board-ui.md`. The template on main is the page's only source: a fix is made in the template and then published, never edited on the live page alone. Publish the template as it is, except its first line, the stamp (step 4). Never rewrite it from the spec, and never edit it in the session: a change to the page is a commit to the template and the spec together.

Each decider gets their own private copy. The page embeds no data; it reads and writes GitHub as whoever opens it.

## 1. Check the surface

Stop and say so if any of these is missing; do not work around it.

- The Artifact tool and the `artifact-capabilities` skill (a claude.ai or Cowork session). A terminal Claude Code session cannot publish this page.
- The `github` connector (tools named `mcp__github__*`). "GitHub Integration" in the connector list is a different grant: it gives cloud sessions clone access and has no effect on this page.

## 2. Prove the connector can see private repos

1. `get_me` → the decider's login.
2. `get_file_contents` on a file in a **private** repo that holds decisions (for example `docs/protocol.md` of the coordinating repo).

A `404 Not Found` on a repo that exists means the connector cannot see it. The fix is the decider's act, on GitHub, per `docs/connector-access.md` (the app is installed per account: each organization and the personal account, with a repository list). Then repeat step 2. Do not publish until it passes: a board that silently misses a repo is worse than no board.

Changing the connector's tool permissions in claude.ai (always allow / needs approval) does not change which repos it can see.

## 3. Confirm the tool shapes the template was built against

Load `artifact-capabilities`. Read this session's definitions of the six tools and compare with what the template calls. If a name or a required argument differs, stop and report the difference to seat BEAST; do not patch the template in the session.

| Tool | Input the page sends | What the page reads from the result |
|---|---|---|
| `get_me` | `{}` | `login` |
| `search_issues` | `{query: "is:open assignee:<login> label:decision,desk", perPage: 100, sort: "updated", order: "desc", fields: [...]}` (scoped to is:issue: it never returns a PR) | `items[]`: `number`, `title`, `body`, `html_url`, `labels` (strings), `comments`, `updated_at`, `repository_url` |
| `search_pull_requests` | `{query: "is:open assignee:<login> label:needs-review", perPage: 100, sort: "updated", order: "desc", fields: [...]}` | the same `items[]` fields, for the PRs |
| `issue_read` | `{method: "get_comments", owner, repo, issue_number, perPage: 20, page}` | a bare comment array (the shape inside a page) or `comments[]`: `body`, `created_at`, `html_url`, `user.login` |
| `add_issue_comment` | `{owner, repo, issue_number, body}` | `html_url` and `created_at` when present; otherwise the issue URL |
| `get_file_contents` | `{owner, repo, path}` plus `sha` or `ref` | the content block of type `resource`, field `resource.text` |

The shapes of `get_me`, `search_issues`, `issue_read`, `add_issue_comment` and `get_file_contents` were observed on 2026-10-10 and 2026-10-11 against the connector at `api.githubcopilot.com/mcp`; `search_pull_requests` is called with `search_issues`'s arguments and read the same way, and was not yet observed from a page. A search the connector refuses fails the whole list in the banner, naming the tool.

## 4. Publish

The template's first line is the stamp, `<!-- board.html @ @@COMMIT@@ -->`. Fill it before publishing: `list_commits` `{owner: "DeSciX", repo: "daita-beast", path: "plugin/templates/board.html", perPage: 1, fields: ["sha"]}` gives the template's newest commit on main; the line becomes `<!-- board.html @ <that sha> -->`. That is the only edit made to the template at publish; a template whose first line is not the stamp is reported to seat BEAST, not patched. The `cowork-tick` skill reads the stamp off the published page and republishes when main moved.

Publish `${CLAUDE_PLUGIN_ROOT}/templates/board.html` with:

```
capabilities: {mcp: {servers: [{server: "github", tools: ["get_me", "search_issues", "search_pull_requests", "issue_read", "add_issue_comment", "get_file_contents"]}]}, user: {}}
icon: "checklist"
```

`server` is the connector's display name as claude.ai shows it. If the decider's connector is named differently, the template's `SERVER` constant and this declaration must both carry that name: report it to seat BEAST as a template parameter, do not fork the page.

To update an existing board (a republish):

1. Fetch `plugin/templates/board.html` at a named commit of main: `get_file_contents` with `owner`, `repo`, `path` and `sha: <commit>`. Name that commit in the hand-over; it is the stamp's value.
2. Find the board with the Artifact tool's list action and read it.
3. Publish the fetched file, byte-exact but for the filled stamp, to that same URL, so the decider's link does not change, with the `capabilities` above: they are the template's tool list, and a page whose grant lacks a tool it calls (a page published before the template called `search_pull_requests`) fails its board list naming that tool.

## 5. Hand over and test

Tell the decider:

- The first time the page calls GitHub, claude.ai asks them to allow the connector for this page. Posting an answer is a write and asks for approval unless they set it to always allow.
- `#<owner>.<repo>.<number>` after the artifact link opens on that card.

An agent cannot operate the page: browser automation does not reach the artifact's frame (measured 2026-10-11, clicks, scroll and keys all dropped). Answering from the page is the decider's own click. The agent's check is reading GitHub afterwards.

Write-path test, once per install, as `docs/board-ui.md` describes: a seat files a throwaway decision (`decision.sh new … --by <SEAT> --seat <SEAT> --title "FIXTURE board write <UTC>" --record fixture`), the decider approves it on the page, the agent confirms the comment with `issue_read` (`get_comments`), and the hearing seat closes it on the relay's `UPDATED`. A board session does not file or close decisions; those are seat acts.

## What the page does not do

It never closes an issue, never labels, never edits a body. Its Context view shows the issue's thread and any file the body links by full GitHub URL (`https://github.com/<owner>/<repo>/blob/<ref>/<path>`); a record cited as free text cannot be fetched.
