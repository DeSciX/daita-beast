#!/usr/bin/env bash
# ack.sh — a seat's ack on a decision row: one comment of fixed shape, the queue's consumption state.
#   ack.sh <owner/repo#N | url> --seat <LABEL | login/LABEL> --state seen|executed|blocked --next "<the act and when it is measured>" [--text "<evidence>" | --text-file <f>]
# A seat is current on a row when its newest ack is newer than the row's latest event (created, the
# decider's answer, closed); the inbox lists rows where it is not. A close by a seat is its seen ack, and so is the
# ack decision.sh new and pr.sh request post for the filing seat. A seat's own comment on a row is an ack (--text carries
# the reply or the evidence): the relay reads the tagged line as that seat's act and never sends it back to the seat.
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
[[ -n "$ref" && -n "$seat" && -n "$state" && -n "$next" ]] || die "usage: ack.sh <issue> --seat LABEL|login/LABEL --state seen|executed|blocked --next \"<act>\" [--text|--text-file]"
case "$state" in seen|executed|blocked) ;; *) die "state must be seen, executed or blocked" ;; esac
seat="$(seat_rostered "$seat")" || exit 1
[[ "$next" != *$'\n'* ]] || die "--next is one line"
rn="$(parse_issue_ref "$ref")" || exit 1; read -r repo number <<< "$rn"
coord_write_guard "$repo" "$seat"
[[ -n "$text_file" ]] && text="$(cat "$text_file")"
body="$(ack_line "$seat" "$state" "$next")" || exit 1
[[ -n "$text" ]] && body="$body

$text"
issue_comment "$repo" "$number" "$body"
