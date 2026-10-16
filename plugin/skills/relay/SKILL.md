---
name: relay
description: Install, check or remove the machine's decision relay — a launchd job that polls GitHub once per tick for every roster seat and, only when a decision for a seat changed, starts a disposable Haiku session to send that seat the event line. Use for "install the relay", "is the relay running", "stop the relay", or to run one poll by hand.
---

# relay — scheduled poll, disposable messenger

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

What a seat receives, one line per change to a decision labelled `seat:<login>/<LABEL>`: `BEAST-EVENT kind=DECIDED seat=… <title> <url> :: <the close comment's first line>` (the word came), `BEAST-EVENT kind=NEW … state=open …` (a decision waiting on it was filed), `BEAST-EVENT kind=UPDATED …` (a comment or edit, possibly the decider answering in the GitHub UI). The relay is an optimization on machines that have it, never the contract: a seat on any machine or surface gets the same inbox (`decision.sh inbox <SEAT>`, computed from acks on GitHub). A seat whose address is not recorded (it has not run `/daita-beast:seats` since its last reload) is not sent and loses nothing. The log at `~/.beast/relay.log` says per tick what changed, each seat's address, and per line queued / no-address. Queued is not delivered: a receiver holds a message from a sender in another permission mode and never tells a one-shot sender, so the messenger runs in the seats' mode: `--permission-mode`, or the roster's `relay.permissionMode` (the install skill records it there); when a seat says it heard nothing, compare its mode with the relay's first (`relay (haiku, <mode>)` in the log).

The relay session decides nothing and sends nothing but the line; relay.sh resolves the addresses, and the messenger's only tool is SendMessage.

An `UPDATED` whose last comment is the seat's own (every seat runs under one login today) is the seat's echo: ignore it. A seat whose ListAgents name changed (a renamed session) must re-record with `seats.sh record`; the log's `not reachable` names it.
