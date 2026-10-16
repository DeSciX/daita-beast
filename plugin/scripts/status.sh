#!/usr/bin/env bash
# status.sh — post a status report on a workstream's tracking issue.
#   status.sh <owner/repo#N | url> --seat <LABEL | login/LABEL> --state working|blocked|done|handoff --next "<next act>" [--text "<body>" | --text-file <f>]
# A report is posted at a blocker, a completion or a seam, never as a tick. The header line is fixed
# so the board, humans and other seats can read it by shape.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

ref="${1:-}"; shift || true
seat=""; state=""; next=""; text=""; text_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --seat) seat="$2"; shift 2 ;;
    --state) state="$2"; shift 2 ;;
    --next) next="$2"; shift 2 ;;
    --text) text="$2"; shift 2 ;;
    --text-file) text_file="$2"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$ref" && -n "$seat" && -n "$state" && -n "$next" ]] || die "usage: status.sh <issue> --seat --state --next [--text|--text-file]"
case "$state" in working|blocked|done|handoff) ;; *) die "state must be working, blocked, done or handoff" ;; esac
seat="$(seat_id "$seat")" || exit 1
rn="$(parse_issue_ref "$ref")" || exit 1; read -r repo number <<< "$rn"
coord_write_guard "$repo" "$seat"
[[ -n "$text_file" ]] && text="$(cat "$text_file")"

body="BEAST-STATUS seat=$seat at=$(utc_now) state=$state next=$next

$text"
issue_comment "$repo" "$number" "$body"
