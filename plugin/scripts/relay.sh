#!/usr/bin/env bash
# relay.sh — the scheduler's entry point: one poll over the roster, and when a decision changed for a
# seat, one disposable Claude session (haiku by default) that sends each seat its event line.
#   relay.sh --repo <coordinating checkout> [--model haiku|sonnet] [--permission-mode <mode>] [--dry-run]
# Nothing runs when nothing changed. Every run appends to ~/.beast/relay.log. relay.sh resolves each
# seat's recorded address itself, by the seat id the event line carries (seat=<login>/<LABEL>); the messenger session decides nothing and has one tool, SendMessage:
# it sends each seat its line verbatim and reports queued / no-address per line. A receiver HOLDS a
# message from a sender in another permission mode (measured 2026-10-12: 23 lines "sent" to a
# bypassPermissions seat from a default-mode messenger, none delivered), so the messenger runs in the
# seats' mode, bypassPermissions by default. Delivery is the receiver's: a held message never reports
# back to a one-shot sender, so the log says queued, never delivered.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
[[ -n "$repo" && -d "$repo/.git" ]] || { echo "relay.sh: --repo must be a git checkout holding .beast/roster.json" >&2; exit 1; }
log="$HOME/.beast/relay.log"; mkdir -p "$HOME/.beast"
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

events="$(cd "$repo" && "$here/watch.sh" --roster --once 2>>"$log")" || { echo "$(stamp) watch failed" >> "$log"; exit 1; }
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
addresses=""
while IFS= read -r seat; do
  [[ -n "$seat" ]] || continue
  if addr="$(cd "$repo" && "$here/seats.sh" address "$seat" 2>/dev/null)" && [[ -n "$addr" ]]; then
    addresses+="ADDRESS $seat = $addr"$'\n'
  else
    addresses+="ADDRESS $seat = none"$'\n'
  fi
done < <(printf '%s\n' "$events" | sed -n 's/^BEAST-EVENT kind=[A-Z]* seat=\([^ ]*\).*/\1/p' | sort -u)
prompt="$addresses$events"
out="$(cd "$repo" && claude -p "$prompt" --plugin-dir "$plugin" --agent "daita-beast:relay-messenger" \
        --model "$model" --permission-mode "$pmode" --max-turns 12 \
        --allowedTools "SendMessage" --disallowedTools "Bash" "Read" "Write" "Edit" "Agent" "WebFetch" "WebSearch" 2>&1)" || true
echo "$(stamp) relay ($model, $pmode):" >> "$log"
printf '%s\n' "$addresses" | sed '/^$/d; s/^/  /' >> "$log"
printf '%s\n' "$out" | sed 's/^/  /' >> "$log"
printf '%s\n' "$out"
