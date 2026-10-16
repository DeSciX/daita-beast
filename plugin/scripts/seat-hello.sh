#!/usr/bin/env bash
# seat-hello.sh — SessionStart hook. In a seat's home (a $PWD/.beast/seat.json naming a roster seat whose derived
# home, seat_home_path, is $PWD) it adds context naming the seat, its first act and its tracking issue (from the
# roster, the one owner). Anywhere else inside a checkout with a roster, it names the homes of the roster's seats
# of the gh login that work in this checkout's repo, so the session is reopened there; with none, it prints nothing.
# After a compaction (input "source": "compact") it leads with the handoff, because PreCompact cannot add
# context (the hooks reference: "Claude Code discards a PreCompact hook's `systemMessage` and `continue` fields").
# A hook never fails the session: a fault is put into the context, named, and the hook exits 0.
set -u
input="$(cat)"
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"

# hello: the context line, or nothing. Runs in a subshell that sources lib.sh, whose die exits that subshell.
hello() {
  source "$scripts/lib.sh"
  local root roster here sid home tracking login slug homes="" id
  root="$(repo_root 2>/dev/null)" || return 0
  roster="$(roster_path)"
  [[ -f "$roster" ]] || return 0
  here="$(pwd -P)"
  sid="$(seat_json_id "$PWD")"
  if [[ -n "$sid" && $'\n'"$(roster_seat_ids "$roster")"$'\n' == *$'\n'"$sid"$'\n'* ]] \
     && home="$(seat_home_path "$sid" 2>/dev/null)" && [[ "$(cd "$home" 2>/dev/null && pwd -P)" == "$here" ]]; then
    tracking="$(jq -r --arg g "$(seat_login "$sid")" --arg l "$(seat_label "$sid")" '.seats[] | select(.github == $g and .label == $l) | .tracking // empty' "$roster")"
    local label; label="$(seat_label "$sid")"
    if [[ -z "$tracking" ]]; then
      echo "This session is the Beast seat $sid, which has no tracking issue in $roster. First act: run $scripts/join.sh $label --tracking <owner/repo#N> --address \"<your ListAgents name [ref]>\"."
      return 0
    fi
    local ctx="This session is the Beast seat $sid. First act: run $scripts/join.sh $label --address \"<your ListAgents name [ref]>\", then work the inbox it prints. Before any compaction or shutdown: $scripts/status.sh $tracking --seat $label --state handoff."
    [[ "$src" != compact ]] || ctx="This session was just compacted. Post the handoff on $tracking now, from the summary: $scripts/status.sh $tracking --seat $label --state handoff --next \"<next act>\" --text \"<state, waiting on, branches, gotchas>\". $ctx"
    echo "$ctx"; return 0
  fi
  login="$(gh_login)"
  slug="$(repo_slug "$root")"
  while IFS= read -r id; do
    [[ -n "$id" && "$(seat_login "$id")" == "$login" ]] || continue
    [[ "$(jq -r --arg g "$login" --arg l "$(seat_label "$id")" '.seats[] | select(.github == $g and .label == $l) | .repo' "$roster")" == "$slug" ]] || continue
    homes="$homes $(seat_label "$id") -> $(seat_home_path "$id");"
  done < <(roster_seat_ids "$roster")
  [[ -n "$homes" ]] || return 0
  echo "This session runs in $PWD, which is not the home of a Beast seat${sid:+ (its .beast/seat.json names $sid, whose home is elsewhere)}. The seats of $login in $slug, and their homes:${homes%;}. To work as a seat, open the session in its home and run $scripts/join.sh <LABEL> there; one seat per directory."
}

err="$(mktemp)"
ctx="$( (hello) 2>"$err" )" || true
if [[ -s "$err" && -z "$ctx" ]]; then
  ctx="The Beast SessionStart hook could not name this directory's seat or home: $(tr '\n' ' ' < "$err"). Tell the user."
fi
rm -f "$err"
[[ -n "$ctx" ]] || exit 0
jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
