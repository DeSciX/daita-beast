#!/usr/bin/env bash
# permit.sh — PreToolUse hook: allows a Bash call whose whole command is ONE of this plugin's own
# scripts with plain arguments, optionally after `cd <absolute dir> && ` (a seated session runs every command
# from its home, because the shell returns to the launch folder), and says nothing about anything else.
# A plugin cannot ship permission rules; this hook is the one in-plugin route. It allows only when:
#   the command's first word is <plugin>/scripts/<name>.sh (no "..", no other path), where <plugin> is
#   $CLAUDE_PLUGIN_ROOT (the running plugin) or the root ~/.beast/plugin.json records (lib.sh plugin_root_recorded,
#   so a --plugin-dir session may still run the installed plugin's scripts the committed block names), and
#   the command carries no shell metacharacter (; & | ` $( ) < > newline), so nothing rides along.
# An input it cannot read is a fault: it says nothing, and logs one line in ~/.beast/hooks.log (lib.sh hook_log).
set -u
root="${CLAUDE_PLUGIN_ROOT:-}"
rec="$( (source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"; plugin_root_recorded) 2>/dev/null )" || rec=""
[[ -n "$root$rec" ]] || exit 0
input="$(cat)"
if ! cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"; then
  ( source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"; hook_log permit fault - "permit.sh: the PreToolUse input is not JSON with tool_input.command (${#input} bytes); said nothing" ) 2>/dev/null || true
  exit 0
fi
[[ -n "$cmd" ]] || exit 0
# One leading "cd <absolute dir> && ", the dir a plain path (no space, quote or metacharacter), is the seat's home.
if [[ "$cmd" =~ ^cd\ (/[A-Za-z0-9._/+@,=:-]*)\ \&\&\ (.*)$ ]]; then cmd="${BASH_REMATCH[2]}"; fi
case "$cmd" in *[';&|`<>']*|*'$('*|*$'\n'*) exit 0 ;; esac
first="${cmd%% *}"
{ [[ -n "$root" && "$first" =~ ^"$root"/scripts/[a-z-]+\.sh$ ]] || [[ -n "$rec" && "$first" =~ ^"$rec"/scripts/[a-z-]+\.sh$ ]]; } || exit 0
[[ -f "$first" ]] || exit 0
jq -n --arg r "daita-beast: $first is this plugin's own script" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:$r}}'
