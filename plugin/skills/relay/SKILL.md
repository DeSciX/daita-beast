---
name: relay
description: Install, check or remove the machine's two Beast jobs — the decision relay (a launchd job that polls GitHub once per tick for every roster seat and, only when a decision for a seat changed, starts a disposable Haiku session to send that seat the event line) and the watchdog (a 15-minute checklist that re-points a mispointed relay, files measured defects on the plugin twin, re-stamps a live seat's stale address and reminds a live seat of an unacked row). Use for "install the relay", "is the relay running", "stop the relay", "install the watchdog", "what did the watchdog do", or to run one poll or one tick by hand.
---

# relay — scheduled poll, disposable messenger; and the watchdog

No seat holds a monitor and GitHub is hit once per tick for every seat together. When nothing changed, nothing runs but the poll.

Install (every 120 s by default; the repo is the coordinating checkout whose roster names the seats):
```
${CLAUDE_PLUGIN_ROOT}/scripts/install-relay.sh --repo <path to the coordinating checkout> [--interval 120] [--model haiku] [--permission-mode bypassPermissions]
```
Status and last log lines, or remove:
```
${CLAUDE_PLUGIN_ROOT}/scripts/install-relay.sh --status
${CLAUDE_PLUGIN_ROOT}/scripts/install-relay.sh --uninstall
```
One poll by hand, without sending (prints the event lines, logs them):
```
${CLAUDE_PLUGIN_ROOT}/scripts/relay.sh --repo <path to the coordinating checkout> --dry-run
```
The watchdog, the second job (every 900 s, the same checkout and mode; `--job` names it on every verb, and `--describe` prints either job as `key=value` fields):
```
${CLAUDE_PLUGIN_ROOT}/scripts/install-relay.sh --job watchdog --repo <path to the coordinating checkout> --permission-mode <the roster's relay.permissionMode>
${CLAUDE_PLUGIN_ROOT}/scripts/install-relay.sh --job watchdog --status
${CLAUDE_PLUGIN_ROOT}/scripts/watchdog.sh --repo <path to the coordinating checkout> --dry-run
```
The dry run prints the findings and the agent's prompt and writes only `~/.beast/watchdog.log`.

What a seat receives, one line per change to a decision labelled `seat:<login>/<LABEL>`: `BEAST-EVENT kind=DECIDED seat=… close=<closed|rejected|latitude|none> <title> <url> :: <the close comment's first line>` (the word came; `close=latitude`: a seat merged it under its standing latitude, no words, the record linked in the line), `BEAST-EVENT kind=NEW … state=open …` (a decision waiting on it was filed), `BEAST-EVENT kind=UPDATED …` (a comment or edit, possibly the decider answering in the GitHub UI). The relay is an optimization on machines that have it, never the contract: a seat on any machine or surface gets the same inbox (`decision.sh inbox <SEAT>`, computed from acks on GitHub). A seat whose address is not recorded on this machine (it has not run `/daita-beast:seats` since its last reload) is not sent and loses nothing: the log says `no direct address from this machine: <seat>`, and a tick in which no event's seat has an address starts no messenger and spends no tokens. The log at `~/.beast/relay.log` says per tick what changed, each addressed seat's address, and per line queued. Queued is not delivered: a receiver holds a message from a sender in another permission mode and never tells a one-shot sender, so the messenger runs in the seats' mode: `--permission-mode`, or the roster's `relay.permissionMode` (the install skill records it there); when a seat says it heard nothing, compare its mode with the relay's first (`relay (haiku, <mode>)` in the log).

The relay session decides nothing and sends nothing but the line; relay.sh resolves the addresses, and the messenger's only tool is SendMessage.

A seat is never sent its own act: every seat posts as one login, so the watcher reads who acted from the tags (the filer's ack, the closer, a `BEAST-ACK`, `BEAST-ASK`, `BEAST-MSG` or own-desk `BEAST-WITHDRAW` line) and logs an event whose every actor is the seat itself as `own act, not sent`. The decider's comments and answers, and every other seat's acts, are sent. A seat's own comment on a row goes through `ack.sh` (`--text` for a reply or evidence), so it is read as the seat's. A seat whose ListAgents name changed (a renamed session) must re-record with `seats.sh record`; the log's `not reachable` names it, and after two such replies the relay stops sending to that address (`not sending to <seat> at <address>: not reachable on 2 messenger replies`) until the seat records a new one. A GitHub rate limit is named once in the log (`GitHub rate limit at …; backing off <n> s`) and polls are `skipped` until the backoff ends; a workstream whose `## Seats` table does not parse is named once and skipped, the others still relayed.

The watchdog's log is `~/.beast/watchdog.log`: one `tick:` line per tick (`quiet` with its GitHub call counts, or the signals handed to its agent, the prompt and the replies). It repairs only local, mechanical things (the plugin record, the relay job, a corrupt mark, retired seats' relay caches), files bugs labelled `watchdog` on the plugin twin, re-stamps a live seat's stale address with `seats.sh touch` after `ListAgents` lists it, and sends a seat `BEAST-WATCHDOG to=<identity> check=<id> at=<UTC>` reminders (at most once per seat, check and object every 2 hours). Its learnings are one `BEAST-WATCHDOG-NOTES machine=<host>` comment on the Beast tracking issue; its catalogue is `plugin/watchdog/gotchas.md`.
