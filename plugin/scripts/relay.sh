#!/usr/bin/env bash
# relay.sh — the scheduler's entry point: one poll over the roster, and when a decision changed for a
# seat, one disposable Claude session (haiku by default) that sends each seat its event line.
#   relay.sh --repo <coordinating checkout> [--model haiku|sonnet] [--permission-mode <mode>] [--dry-run]
# Nothing runs when nothing changed. A seat is never sent its own act: watch.sh drops an event whose every actor is
# that seat (event_actors, lib.sh: the filer's ack, the closer, the tagged writer of each new comment) and logs it here
# as "own act, not sent"; the decider's comments and other seats' acts are sent. Every run appends to ~/.beast/relay.log. relay.sh resolves each
# seat's recorded address itself, by the seat id the event line carries (seat=<login>/<LABEL>); the messenger session decides nothing and has one tool, SendMessage:
# it sends each seat its line verbatim and reports queued / no-address per line. A receiver HOLDS a
# message from a sender in another permission mode (measured 2026-10-12: 23 lines "sent" to a
# bypassPermissions seat from a default-mode messenger, none delivered), so the messenger runs in the
# seats' mode, bypassPermissions by default. Delivery is the receiver's: a held message never reports
# back to a one-shot sender, so the log says queued, never delivered. An event whose seat has no direct address from this
# machine (seats.sh address: its BEAST-ADDRESS comment names another account, another machine, or is stale) is logged
# "no direct address from this machine: <seat>" and never reaches the messenger; when no event's seat has one, no
# messenger starts and the tick spends no tokens. An address the messenger answered "not reachable" for twice in a row is
# not sent to again until the seat records a new one (the unreachable ledger, below). A poll watch.sh skips while it
# backs off a GitHub rate limit is logged "poll: skipped"; any other watch failure is logged "watch failed".
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"   # checkout_require_root; the run cache it makes is shared with the watch and the address reads
repo=""; model="haiku"; pmode="bypassPermissions"; dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --permission-mode) pmode="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "relay.sh: unknown argument $1" >&2; exit 1 ;;
  esac
done
[[ -n "$repo" ]] || { echo "relay.sh: --repo must be a git checkout holding .beast/roster.json" >&2; exit 1; }; checkout_require_root "$repo"
log="$HOME/.beast/relay.log"; mkdir -p "$HOME/.beast"
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

rc=0; events="$(cd "$repo" && "$here/watch.sh" --roster --once 2>>"$log")" || rc=$?
# 75: watch.sh backs off a GitHub rate limit (it named the limit and the backoff when it started): a skipped poll, not a failure.
if [[ $rc -eq 75 ]]; then echo "$(stamp) poll: skipped (watch.sh backs off a GitHub rate limit, named when it started)" >> "$log"; exit 0; fi
[[ $rc -eq 0 ]] || { echo "$(stamp) watch failed (exit $rc, named above)" >> "$log"; exit 1; }
# Only event lines reach the messenger; anything else the watcher printed is logged, never relayed.
events="$(printf '%s\n' "$events" | grep '^BEAST-EVENT ' || true)"
if [[ -z "$events" ]]; then
  echo "$(stamp) poll: no change" >> "$log"
  exit 0
fi
echo "$(stamp) poll: $(printf '%s\n' "$events" | grep -c .) event(s)" >> "$log"
printf '%s\n' "$events" | sed 's/^/  /' >> "$log"
[[ $dry -eq 1 ]] && { printf '%s\n' "$events"; exit 0; }

# The messenger is the plugin agent `relay-messenger` (plugin/agents/relay-messenger.md): its prompt
# is the address map and the event list; its only tool is SendMessage.
plugin="$(cd "$here/.." && pwd)"
# The unreachable ledger (~/.beast/relay-unreachable.json, {seat: {address, n, first, last}}): the messenger's replies
# "<seat> error … reachable" (no agent named that, no agent reachable) count per seat and address; after
# RELAY_UNREACHABLE_MAX of them the relay stops sending to that address (logged per event, "not sending … not
# reachable"), so a dead or renamed address stops costing a Haiku run per tick. A queued reply, or a new address (the
# seat re-recorded with seats.sh record), clears the count. The machine watchdog reports the stopped seats.
unreach="$HOME/.beast/relay-unreachable.json"; RELAY_UNREACHABLE_MAX=2
if [[ ! -s "$unreach" ]]; then echo '{}' > "$unreach"
elif ! jq -e 'type == "object"' "$unreach" >/dev/null 2>&1; then echo "$(stamp) the unreachable ledger $unreach is not a JSON object; reset (its counts are lost)" >> "$log"; echo '{}' > "$unreach"; fi
unreach_set() { local t; t="$(mktemp "$unreach.XXXXXX")"; jq "${@:2}" "$1" "$unreach" > "$t" && mv -f "$t" "$unreach"; }
addresses=""; send=""
while IFS= read -r seat; do
  [[ -n "$seat" ]] || continue
  # seats.sh address: line 1 the address, then the facts, then "path: direct|desk — <why>"; only a direct path is relayed
  # (same Claude account, same machine, fresh): a SendMessage address reaches a session only from there.
  if out="$(cd "$repo" && "$here/seats.sh" address "$seat" 2>/dev/null)" && [[ -n "$out" ]] && grep -q '^path: direct' <<< "$out"; then
    addr="$(head -1 <<< "$out")"
    u="$(jq -c --arg s "$seat" '.[$s] // empty' "$unreach")"
    if [[ -n "$u" && "$(jq -r .address <<< "$u")" != "$addr" ]]; then unreach_set 'del(.[$s])' --arg s "$seat"; u=""; fi
    if [[ -n "$u" && "$(jq -r .n <<< "$u")" -ge $RELAY_UNREACHABLE_MAX ]]; then
      echo "$(stamp) not sending to $seat at $addr: not reachable on $(jq -r .n <<< "$u") messenger replies since $(jq -r .first <<< "$u") (the seat re-records with seats.sh record; a new address resets this; its inbox still holds every row)" >> "$log"
      continue
    fi
    addresses+="ADDRESS $seat = $addr"$'\n'
    send+="$(printf '%s\n' "$events" | awk -v s="seat=$seat" '$3 == s')"$'\n'
  else
    echo "$(stamp) no direct address from this machine: $seat ($(grep '^path:' <<< "${out:-}" | head -1 || echo "none recorded"))" >> "$log"
  fi
done < <(printf '%s\n' "$events" | sed -n 's/^BEAST-EVENT kind=[A-Z]* seat=\([^ ]*\).*/\1/p' | sort -u)
if [[ -z "$addresses" ]]; then
  echo "$(stamp) relay: no messenger (no event's seat has a direct address from this machine)" >> "$log"
  exit 0
fi
prompt="$addresses$send"
out="$(cd "$repo" && claude -p "$prompt" --plugin-dir "$plugin" --agent "daita-beast:relay-messenger" \
        --model "$model" --permission-mode "$pmode" --max-turns 12 \
        --allowedTools "SendMessage" --disallowedTools "Bash" "Read" "Write" "Edit" "Agent" "WebFetch" "WebSearch" 2>&1)" || true
echo "$(stamp) relay ($model, $pmode):" >> "$log"
printf '%s\n' "$addresses" | sed '/^$/d; s/^/  /' >> "$log"
printf '%s\n' "$out" | sed 's/^/  /' >> "$log"
# Count the replies per addressed seat: an error naming reachability counts against that address, a queued one clears it.
while IFS= read -r line; do
  a_seat="$(sed -n 's/^ADDRESS \([^ ]*\) = .*/\1/p' <<< "$line")"; a_addr="${line#* = }"
  [[ -n "$a_seat" ]] || continue
  reply="$(grep -E "^$a_seat (queued|no-address|error)( |$)" <<< "$out" | tail -1 || true)"
  if grep -qiE "^$a_seat error .*(reachable|no agent named)" <<< "$reply"; then
    unreach_set '.[$s] = (if (.[$s].address // "") == $a then .[$s] + {n: (.[$s].n + 1), last: $t} else {address: $a, n: 1, first: $t, last: $t} end)' --arg s "$a_seat" --arg a "$a_addr" --arg t "$(stamp)"
  elif grep -q "^$a_seat queued" <<< "$reply"; then
    unreach_set 'del(.[$s])' --arg s "$a_seat"
  fi
done <<< "$addresses"
printf '%s\n' "$out"
