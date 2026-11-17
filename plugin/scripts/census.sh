#!/usr/bin/env bash
# census.sh — before a seat files a build or deploy ask: is anything it already reviewed not yet served?
#   census.sh <LABEL | login/LABEL>
# For each target of the seat's roster row "census" (roster_census, lib.sh, the one parser of its shape), reads the
# reviewed commit and the served commit, each a full 40-hex sha:
#   {"git": "<ref>"[, "dir": "<path>"]}   git rev-parse --verify <ref>^{commit} in the main checkout (or <dir> under it);
#                                         nothing is fetched: fetch first when the ref is a remote one
#   {"cmd": "<shell command>"}            bash -c from the main checkout; its whole output, trimmed, must be one 40-hex sha
# and prints one line per target whose two differ, then a summary:
#   unshipped: <target> reviewed=<sha> served=<sha>
#   census: clean, <N> targets checked              (nothing unshipped)
#   census: <k> unshipped of <N> targets checked
# The seat puts every unshipped line, or the clean line, into the row it files. A target whose reviewed or served side
# cannot be read (a ref that does not resolve, a command that fails or prints anything but one sha) is named on stderr,
# no summary is printed, and census.sh exits 1: an unread target is never counted clean. A seat with no "census" in its
# roster row exits 1 naming the field.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need jq git python3

[[ $# -eq 1 ]] || die "usage: census.sh <LABEL | login/LABEL>"
id="$(seat_rostered "$1")" || exit 1
targets="$(roster_census "$id")" || exit 1
[[ -n "$targets" ]] || die "census: $id lists no targets: add \"census\": [{\"name\", \"reviewed\", \"served\"}] to its row in $(roster_path) (docs/protocol.md, Roster)"
root="$(repo_main_root)" || exit 1

# census_read <target> <side> <reader json>: the 40-hex sha the reader names, or a line on stderr and status 1.
census_read() {
  local t="$1" side="$2" rd="$3" out ref dir
  if jq -e 'has("git")' <<< "$rd" >/dev/null; then
    ref="$(jq -r .git <<< "$rd")"; dir="$root"
    if jq -e 'has("dir")' <<< "$rd" >/dev/null; then dir="$root/$(jq -r .dir <<< "$rd")"; fi
    [[ -d "$dir" ]] || { echo "daita-beast: census: $t $side: no directory $dir" >&2; return 1; }
    out="$(git -C "$dir" rev-parse --verify --quiet "$ref^{commit}")" || { echo "daita-beast: census: $t $side: the ref '$ref' names no commit in $dir" >&2; return 1; }
  else
    out="$(cd "$root" && bash -c "$(jq -r .cmd <<< "$rd")" 2>/dev/null)" || { echo "daita-beast: census: $t $side: the command $(jq -c .cmd <<< "$rd") exited non-zero" >&2; return 1; }
    out="$(printf '%s' "$out" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  fi
  [[ "$out" =~ ^[0-9a-f]{40}$ ]] || { echo "daita-beast: census: $t $side: read '$(printf '%s' "$out" | head -c 80 | tr '\n' ' ')', not one 40-hex sha" >&2; return 1; }
  echo "$out"
}

n=0; k=0; unread=(); lines=""
while IFS= read -r t; do
  [[ -n "$t" ]] || continue
  name="$(jq -r .name <<< "$t")"; n=$((n+1))
  rv="$(census_read "$name" reviewed "$(jq -c .reviewed <<< "$t")")" || { unread+=("$name"); continue; }
  sv="$(census_read "$name" served "$(jq -c .served <<< "$t")")" || { unread+=("$name"); continue; }
  if [[ "$rv" != "$sv" ]]; then k=$((k+1)); lines+="unshipped: $name reviewed=$rv served=$sv"$'\n'; fi
done <<< "$targets"
printf '%s' "$lines"
[[ ${#unread[@]} -eq 0 ]] || die "census: cannot read ${#unread[@]} of $n target(s): ${unread[*]} (named above): no census line is printed until every target reads"
if [[ $k -eq 0 ]]; then echo "census: clean, $n targets checked"; else echo "census: $k unshipped of $n targets checked"; fi
