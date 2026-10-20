#!/usr/bin/env bash
# seat-bye.sh — SessionEnd hook. Marks the seat claims this session holds in ~/.beast/sessions.json as ended
# (sessions_end, lib.sh), so a new session started in the same launch folder rejoins the seat (seat-hello.sh, restart).
# Input: {"session_id", "reason", …}. Prints nothing; a fault is named on stderr and the hook exits 0.
set -u
sid="$(jq -r '.session_id // empty' 2>/dev/null)"
[[ -n "$sid" ]] || exit 0
( source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"; sessions_end "$sid" ) || echo "daita-beast: seat-bye.sh: could not mark the claims of session $sid as ended" >&2
exit 0
