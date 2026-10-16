# GitHub connector access

The GitHub connector in Claude.ai, Cowork and the Claude desktop app reaches a repository only if the GitHub app `claude-github-mcp-connector` is installed on the account that owns the repository and that installation lists the repository. The app is installed PER ACCOUNT: once on each organization (for `acme/*` repos, on the `acme` org) and once on the personal account (for `<login>/*` repos, on `<login>`), each with "All repositories" or a selected list. Nothing in Claude.ai shows this; the symptom is a board that is missing rows.

Measured 2026-10-12: the decisions board page listed exactly the 4 rows in the organization's repos and none of the 17 rows in two repos of the decider's personal account, while the same search on GitHub listed 21. The app was installed on the organization and not on the personal account. After the personal-account install the page listed every open row.

## Two GitHub apps, not one

- **Claude Github MCP Connector** (`github.com/apps/claude-github-mcp-connector`, by anthropics) backs the claude.ai `github` connector that Cowork, chat and the board artifact use. This is the one that decides what the board sees.
- **Claude** (the "GitHub Integration" app, "Cloud sessions only") gives Claude Code cloud sessions clone and REST access to repositories attached with `add_repo`. It has no effect on the board: measured 2026-10-11, it showed a repository accessible while the connector still returned 404 for the same repository.

## Install or change

- `https://github.com/apps/claude-github-mcp-connector/installations/new` opens the account picker: choose the organization or the personal account, then "All repositories" or "Only select repositories", then Install.
- `https://github.com/apps/claude-github-mcp-connector/installations/select_target` lists accounts; an installed account shows **Configure**, which edits its repository list (a new private repository is invisible until added to a "select repositories" install).
- An organization you do not administer: Install becomes a request; its admins get the email and approve.
- After an install or change that does not take: Claude.ai › Settings › Connectors › GitHub › disconnect, then connect again.

## Symptoms

| Seen | Cause | Fix |
|---|---|---|
| the board lists rows from organization repos and none from personal repos (or the reverse) | the app is installed on one account and not the other | install on the missing account |
| "Claude cannot access that resource" on one repository | that repository is not in the installation's selected list | Configure that account, add the repository |
| a private repository created after the install never appears | "Only select repositories" install | Configure, add it, or switch to all repositories |
| nothing changes after installing | the connector session is stale | disconnect and reconnect GitHub in Connectors |
| a public repository is readable but issues cannot be created or commented | the app installation grants write; read of public repos works without it | install on that repository's owner |

## The test, on any surface

Ask the connector for ONE known private issue by number (the repository's workstream tracking issue, or any row the generated board lists). It comes back: access is fine and a missing row is a query problem (the search must be unscoped: `is:open is:issue label:decision assignee:<login>`, no repo or org filter). Denied or not found: access, per the table. Never "fix" a missing row by adding a repo filter to the query.
