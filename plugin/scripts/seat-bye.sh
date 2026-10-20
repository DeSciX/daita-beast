#!/usr/bin/env bash
# seat-bye.sh — SessionEnd hook. Marks the seat claims this session holds in ~/.beast/sessions.json as ended
# (sessions_end, lib.sh), so a new session started in the same launch folder rejoins the seat (seat-hello.sh, restart).
# Input: {"session_id", "reason", …}. Prints nothing; a fault is named on stderr and in ~/.beast/hooks.log (lib.sh
# hook_log), and the hook exits 0.
set -u
sid="$(jq -r '.session_id // empty' 2>/dev/null)"
[[ -n "$sid" ]] || exit 0
if ! e="$( (source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"; sessions_end "$sid") 2>&1 )"; then
  m="daita-beast: seat-bye.sh: could not mark the claims of session $sid as ended: ${e#daita-beast: }"
  echo "$m" >&2
  ( source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"; hook_log seat-bye fault "$sid" "$m" ) 2>/dev/null || true
fi
exit 0
