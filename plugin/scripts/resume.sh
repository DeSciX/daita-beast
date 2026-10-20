#!/usr/bin/env bash
# resume.sh — everything a seat needs after a compaction or reload, from GitHub and the roster.
#   resume.sh <LABEL | login/LABEL>
# Prints: the seat map of every open workstream with the seats' addresses (seats.sh list); the seat's last handoff (its newest
# BEAST-STATUS seat=<id> comment on any workstream tracking issue of the workstream owners (workstream_user_terms)); decisions for the
# seat closed since its last inbox sweep; open decisions that wait on it. A seat's working state
# lives in those comments, never in a session's context, so this is the whole resume. Then the seat's
# BEAST-NOTES seat=<id> comment (notes.sh show).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq
here="$(dirname "${BASH_SOURCE[0]}")"

seat="${1:-}"; shift || true
[[ -n "$seat" ]] || die "usage: resume.sh <LABEL | login/LABEL>"
seat="$(seat_rostered "$seat")" || exit 1
# The seat as a BEAST-STATUS header writes it: its id, or its bare label while that resolves to it.
names="$(seat_comment_tokens "$seat" | jq -R . | jq -sc .)" || exit 1
scope="$(workstream_user_terms)" || exit 1

echo "== seats (verify an address by a reply before relying on it)"
"$here/seats.sh" list

echo; echo "== last handoff by $seat (newest BEAST-STATUS comment on a workstream tracking issue)"
best=""
while IFS=$'\t' read -r url repo number; do
  [[ -n "$url" ]] || continue
  c="$(issue_comments "$repo" "$number" | jq -c --argjson s "$names" '[.[] | select(((.body // "") | split("\n") | .[0] // "") | capture("^BEAST-STATUS seat=(?<t>[^ ]+) ") // {t:""} | .t as $t | $s | index($t))] | last | select(. != null) | {at: .created_at, url: .html_url, body}')" || die "cannot read the comments of $repo#$number (403 = repo not attached to this session or no access)"
  [[ -n "$c" ]] || continue
  if [[ -z "$best" ]] || [[ "$(jq -r .at <<< "$c")" > "$(jq -r .at <<< "$best")" ]]; then best="$c"; fi
done < <(search_issues "is:issue label:workstream $scope" | jq -r '.[] | [.html_url, (.repository_url | sub(".*/repos/"; "")), .number] | @tsv')
if [[ -n "$best" ]]; then
  jq -r '"\(.at)  \(.url)\n" + .body' <<< "$best"
else
  echo "(none: this seat has posted no BEAST-STATUS on any workstream tracking issue of $scope)"
fi

echo; echo "== notes of $seat (BEAST-NOTES on its tracking issue; notes.sh $seat set|append)"
"$here/notes.sh" "$seat" show

echo; echo "== inbox: rows naming $seat whose latest event is newer than its ack (ack each once acted on)"
"$here/decision.sh" inbox "$seat"
