#!/usr/bin/env bash
# notes.sh — a seat's durable notes: things it must not relearn, on GitHub so they travel to every surface.
#   notes.sh <LABEL | id> show
#   notes.sh <LABEL | id> set --text-file <f>
#   notes.sh <LABEL | id> append --text "<line>"
# The notes are ONE comment on the seat's tracking issue (roster "tracking") whose first line is
# `BEAST-NOTES seat=<id>`, written by the seat's login. It is created on the first set or append and edited in
# place after that; two such comments are a defect this script names and refuses to choose between.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

seat="${1:-}"; cmd="${2:-}"; shift 2 || true
[[ -n "$seat" && -n "$cmd" ]] || die "usage: notes.sh <seat> show | set --text-file <f> | append --text \"<line>\""
id="$(seat_rostered "$seat")" || exit 1
tracking="$(jq -r --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" '.seats[] | select(.github == $g and .label == $l) | .tracking // empty' "$(roster_path)")"
[[ -n "$tracking" ]] || die "seat $id has no tracking issue in $(roster_path): the notes live on it (join.sh $id --tracking <owner/repo#N>)"
rn="$(parse_issue_ref "$tracking")" || exit 1; read -r repo number <<< "$rn"
[[ "$cmd" == show ]] || coord_write_guard "$repo" "$id"
header="BEAST-NOTES seat=$id"

# The seat's notes comments: first line exactly the header, written by the seat's login.
all="$(issue_comments "$repo" "$number")" || die "cannot read the comments of $tracking"
mine="$(jq -c --arg h "$header" --arg u "$(seat_login "$id")" '[.[] | select(((.body // "") | split("\n")[0] | sub("\\s+$"; "")) == $h and .user.login == $u) | {id, html_url, updated_at, body}]' <<< "$all")"
jq -r --arg h "$header" --arg u "$(seat_login "$id")" '.[] | select(((.body // "") | split("\n")[0] | sub("\\s+$"; "")) == $h and .user.login != $u) | "daita-beast: ignored: \(.html_url) carries the notes header but is by \(.user.login), not the seat'"'"'s login \($u)"' <<< "$all" >&2
n="$(jq length <<< "$mine")"
[[ "$n" -le 1 ]] || die "$tracking has $n notes comments for $id: $(jq -r '[.[].html_url] | join(" and ")' <<< "$mine") — delete all but one by hand"
cid="$(jq -r '.[0].id // empty' <<< "$mine")"
cur="$(jq -r '.[0].body // empty' <<< "$mine")"

write() {  # write <full body>: edit the one comment in place, or create it
  local f; f="$(mktemp)"; printf '%s\n' "$1" > "$f"
  if [[ -n "$cid" ]]; then echo "edited $(comment_edit "$repo" "$cid" "$f") (comment $cid)"
  else echo "created $(gh_send POST "repos/$repo/issues/$number/comments" -F body=@"$f" | jq -r '"\(.html_url) (comment \(.id))"')"; fi
  rm -f "$f"
}

case "$cmd" in
  show)
    if [[ -z "$cid" ]]; then echo "(no notes for $id on $tracking)"
    else jq -r '.[0] | "\(.updated_at)  \(.html_url)  (comment \(.id))"' <<< "$mine"; printf '%s\n' "$cur" | sed '1d'; fi
    ;;
  set)
    [[ "${1:-}" == --text-file && -n "${2:-}" ]] || die "usage: notes.sh <seat> set --text-file <f>"
    [[ -f "$2" ]] || die "no file $2"
    text="$(cat "$2")"; [[ -n "${text//[[:space:]]/}" ]] || die "$2 is empty: notes are not cleared by an empty set"
    write "$header
$text"
    ;;
  append)
    [[ "${1:-}" == --text && -n "${2:-}" ]] || die "usage: notes.sh <seat> append --text \"<line>\""
    if [[ -n "$cid" ]]; then write "$cur
$2"; else write "$header
$2"; fi
    ;;
  *) die "usage: notes.sh <seat> show | set --text-file <f> | append --text \"<line>\"" ;;
esac
