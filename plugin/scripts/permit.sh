#!/usr/bin/env bash
# permit.sh — PreToolUse hook: allows a Bash call whose whole command is ONE of this plugin's own
# scripts with plain arguments, and says nothing about anything else (the normal prompt applies).
# A plugin cannot ship permission rules; this hook is the one in-plugin route. It allows only when:
#   the command's first word is $CLAUDE_PLUGIN_ROOT/scripts/<name>.sh (no "..", no other path), and
#   the command carries no shell metacharacter (; & | ` $( ) < > newline), so nothing rides along.
set -u
root="${CLAUDE_PLUGIN_ROOT:-}"
[[ -n "$root" ]] || exit 0
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$cmd" ]] || exit 0
case "$cmd" in *[';&|`<>']*|*'$('*|*$'\n'*) exit 0 ;; esac
first="${cmd%% *}"
[[ "$first" =~ ^"$root"/scripts/[a-z-]+\.sh$ ]] || exit 0
[[ -f "$first" ]] || exit 0
jq -n --arg r "daita-beast: $first is this plugin's own script" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
