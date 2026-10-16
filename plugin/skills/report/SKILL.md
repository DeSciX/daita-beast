---
name: report
description: The participant report of a milestone (one section per participant, on their desks), and activity and awards for a period, computed from GitHub (merged PRs, reviews, issues and decisions closed per login and per seat, awards, open bounties), rendered by the reporter agent and posted as a BEAST-REPORT comment on the workstream tracking issue. Use for "monthly report", "who was most active in October", "report on egpt-frqtl since the 1st".
---

# report — numbers from GitHub, rendered once

## A milestone's participant report

At each milestone close, one report addressed per participant, so nobody searches the traffic to learn that what they wait on has released or changed direction:
```
${CLAUDE_PLUGIN_ROOT}/scripts/report.sh milestone "<title>" [--repo <owner/repo>]                 prints every section, writes nothing
${CLAUDE_PLUGIN_ROOT}/scripts/report.sh milestone "<title>" [--repo <owner/repo>] --post --by <SEAT>
```
Participants are every seat of the roster plus every outside contributor (a login with no seat) awarded on the milestone's items. Each section says what they earned this milestone (the BEAST-AWARD comments on the issues and PRs filed under it, through the ledger, in the token of the checkout's `.beast/award-policy.md`; no policy, nothing earned, and it says so; an award counts for a seat when the item carries that seat's label) and the state of each thing they wait on (the `/daita-beast:deps` measure). With `--post`, each seat's section is a desk message to it, and the milestone's description keeps the summary as its one `Report:` line. Every seat must have a desk; it refuses before writing anything when one does not. An outside contributor has no desk: their section is printed for you to deliver (release notes come with wrap-up).

## Activity for a period

Compute:
```
${CLAUDE_PLUGIN_ROOT}/scripts/report.sh --repos acme/ACME,acme/widgets --since 2026-10-01 [--until 2026-10-31] [--community ACME --month 2026-10]
```
It prints JSON: `per_login` (merged PRs, reviews), `per_seat` (decisions executed, status reports), `decisions_executed`, `awards` and `awards_dropped`, `bounties_open`.

Render and post: hire the `reporter` agent with the same arguments and `--post <owner/repo#N>` (the workstream tracking issue). It writes the report (headline, activity per login, per seat, awards, bounties open, decisions pending) and posts it with the status skill, first line `BEAST-REPORT <since>..<until>`. From claude.ai with a Google Drive connector it can also write the same report as a Doc and link it.

The owner decides monthly awards from the report with `/daita-beast:award`; the report never awards.
