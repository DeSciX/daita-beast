#!/usr/bin/env bash
# board.sh — render the pending-decisions board from GitHub issues and pull requests.
#   board.sh [--assignee <login>] [--owner <org-or-user>]... [--publish --repo <owner/repo>] [--web]
# A row is open, assigned to <login> (default: the gh user), and labelled `decision` (an issue: an act
# without code) or `needs-review` (a pull request for the decider's review; pr.sh request). A decision row is
# parsed by SHAPE from the issue body (## Decision / Unblocks / Waits / Recommendation / Approve with /
# Record); a body missing a section fails this script, naming the issue. A PR row is its title, the
# PR_ROW_SECTIONS of its body (## Unblocks / Recommendation, written by pr.sh request; missing fails the same way)
# and its phrase (row_phrase). Desks (label `desk`) carry neither label and are never rows.
# Between the open table and the decided table: the roster's home repos' milestones due within 3 days or overdue.
# --publish rewrites the body of the issue titled "Pending decisions (generated)" in --repo (created
# and pinned when absent). --web prints the saved-search URL that IS the board.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

assignee=""; owners=(); publish=0; repo=""; web=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --assignee) assignee="$2"; shift 2 ;;
    --owner) owners+=("$2"); shift 2 ;;
    --publish) publish=1; shift ;;
    --repo) repo="$2"; shift 2 ;;
    --web) web=1; shift ;;
    *) die "unknown argument $1" ;;
  esac
done
viewer="$(user_login)"
[[ -n "$assignee" ]] || assignee="$viewer"

q="is:open label:$BOARD_ROW_LABELS assignee:$assignee"
for o in "${owners[@]:-}"; do [[ -n "$o" ]] && q="$q user:$o"; done
url="https://github.com/issues?q=$(printf '%s' "$q sort:updated-desc" | jq -sRr @uri)"
if [[ $web -eq 1 ]]; then echo "$url"; exit 0; fi

issues="$(search_issues "$q")" || die "GitHub search failed for: $q"

# The search index lags a close by seconds; the live issue is the owner of its state, so every
# candidate is re-read and a closed one is dropped here. The count is of rendered rows.
errors=0; count=0
# seat_cells <row> <labels-json> <event_at>: "SEAT ✓state · SEAT —" per seat of the row (a row_read), from its
# newest ack vs the latest event; a seat shows as LABEL when it is the viewer's own, else as its id.
seat_cells() {
  local rd="$1" labels="$2" ev="$3" acks out="" seat line shown
  acks="$(seat_acks "$rd" 2>/dev/null || true)"
  while read -r seat; do
    [[ -n "$seat" ]] || continue
    shown="$(seat_display "$seat" "$viewer")"
    line="$(printf '%s\n' "$acks" | awk -F'\t' -v s="$seat" '$1==s')"
    if [[ -n "$line" && ! "$(cut -f2 <<< "$line")" < "$ev" ]]; then out="$out$shown ✓$(cut -f3 <<< "$line") · "; else out="$out$shown — · "; fi
  done < <(row_seat_ids "$labels")
  printf '%s' "${out% · }"
}
table="| Kind | # | Decision | Unblocks | Waits | Recommendation | Approve with | Record | Seats |
|---|---|---|---|---|---|---|---|---|"
while IFS=$'\t' read -r num url_ full; do
  [[ -n "$num" ]] || continue
  rd="$(row_read "$full" "$num")"
  live="$(jq '.issue' <<< "$rd")"
  [[ "$(jq -r .state <<< "$live")" == "open" ]] || continue
  body="$(jq -r '.body // ""' <<< "$live")"
  count=$((count+1))
  who="$full#$num"
  if jq -e '.pull_request != null' <<< "$live" >/dev/null; then
    # A PR row: its title, the PR_ROW_SECTIONS of its body (pr.sh request writes them; one missing fails like a
    # decision row's) in the Unblocks and Recommendation columns, its phrase; it has no Waits and no Record.
    for h in "${PR_ROW_SECTIONS[@]}"; do
      if text="$(section_required "$h" "$body" "$who (rerun pr.sh request with --unblocks and --recommendation)" 2>/tmp/board.err)"; then
        text="$(printf '%s' "$text" | cell)"
      else
        cat /tmp/board.err >&2; errors=$((errors+1)); text="(missing: $h)"
      fi
      case "$h" in Unblocks) pu="$text" ;; Recommendation) pr_="$text" ;; *) die "board.sh has no column for the PR section '$h'" ;; esac
    done
    row="| PR | [$who]($url_) | $(jq -r .title <<< "$live" | cell) | $pu | — | $pr_ | $(row_phrase "$who" "$live" | cell) | —"
  else
    row="| decision | [$who]($url_)"
    for h in "${ROW_SECTIONS[@]}"; do
      if text="$(section_required "$h" "$body" "$who" 2>/tmp/board.err)"; then
        row="$row | $(printf '%s' "$text" | cell)"
      else
        cat /tmp/board.err >&2; errors=$((errors+1)); row="$row | (missing: $h)"
      fi
    done
  fi
  IFS=$'\t' read -r ev_at ev_kind < <(row_events "$rd")
  row="$row | $(seat_cells "$rd" "$(jq -c .labels <<< "$live")" "$ev_at")"
  table="$table
$row |"
done < <(jq -r '.[] | [.number, .html_url, (.repository_url | sub(".*/repos/"; ""))] | @tsv' <<< "$issues")

# Decided: rows closed in the last 7 days, with the first line of the close comment (the words).
since="$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)"
qd="is:closed label:$BOARD_ROW_LABELS assignee:$assignee closed:>=$since"
for o in "${owners[@]:-}"; do [[ -n "$o" ]] && qd="$qd user:$o"; done
decided="$(search_issues "$qd")" || die "GitHub search failed for: $qd"
dcount=0; dunacked=0
dtable="| closed | Kind | # | Decision | The words | Acks |
|---|---|---|---|---|---|"
drows_unacked=""; acked=()
while IFS=$'\t' read -r num url_ full closed_at kind title labels; do
  [[ -n "$num" ]] || continue
  rd="$(row_read "$full" "$num")"
  last="$(jq -r '[.comments[] | select((.body // "") | test("^(Closed|Rejected) on the (decider.s )?word"))] | if length == 0 then "(closed without the words: no close comment of the protocol shape)" else (.[-1].body | split("\n")[0] | sub("^(Closed|Rejected) on the word, verbatim: "; "")) end' <<< "$rd")"
  cells="$(seat_cells "$rd" "$labels" "$closed_at")"
  dcount=$((dcount+1))
  drow="| $closed_at | $kind | [$full#$num]($url_) | $(printf '%s' "$title" | sed 's/^Decision: //' | cell) | $(printf '%s' "$last" | cell) | $cells |"
  if [[ "$cells" == *"—"* ]]; then dunacked=$((dunacked+1)); drows_unacked="$drows_unacked
$drow"; else acked+=("$drow"); fi
done < <(jq -r 'sort_by(.closed_at) | reverse | .[] | [.number, .html_url, (.repository_url | sub(".*/repos/"; "")), .closed_at, (if .pull_request then (if .pull_request.merged_at then "PR merged" else "PR" end) else "decision" end), .title, (.labels | tojson)] | @tsv' <<< "$decided")
# Milestones due within 3 days or overdue, per home repo of the roster (the roster repo and each seat's repo), naming
# the seats homed there (milestone_due_flags, lib.sh). Nothing is rendered when none is due; a board read outside a
# checkout with a roster says it cannot show them.
mdue=""
if rp="$(roster_path 2>/dev/null)" && [[ -f "$rp" ]]; then
  while IFS= read -r hr; do
    [[ -n "$hr" ]] || continue
    fl="$(milestone_due_flags "$hr")" || die "cannot read the milestones of $hr (named above)"
    [[ -n "$fl" ]] || continue
    who="$(jq -r --arg r "$hr" '[.seats[]? | select((.repo // "" | ascii_downcase) == ($r | ascii_downcase)) | "\(.github)/\(.label)"] | join(", ")' "$rp")"
    while IFS= read -r l; do mdue="$mdue
- $hr${who:+ ($who)}: $l"; done <<< "$fl"
  done < <(jq -r '[.repo, (.seats[]?.repo)] | map(select(. != null)) | unique | .[]' "$rp")
  [[ -z "$mdue" ]] || mdue="## Milestones due within 3 days or overdue
$mdue"
else
  mdue="(milestone due flags are read through a roster; none at $(pwd))"
fi
stamp="$(utc_now)"
header="Pending decisions for @$assignee — $count open (decision issues and PRs for review), $dcount decided in the last 7 days ($dunacked not yet acked by every seat) — generated $stamp by daita-beast board.sh. Live list: $url
Do not edit this issue: file a decision issue (an act without code) or request review on a PR (pr.sh request) to add a row, close it (quoting the word and its record id; a PR merged or rejected by pr.sh close) to remove one. Questions across the desk live on each seat's desk issue, never here. A decision given in a session before a row existed is filed and closed in one act (decision.sh record), so it appears below. Seats: ✓ and the ack state when the seat's newest BEAST-ACK is newer than the row's latest event, — when it is not."
# GitHub refuses an issue body over 65536 characters. The published body keeps every open row and every
# decided row some seat has not acked; acked decided rows (newest first) fill the rest of BOARD_BUDGET, and
# a line says how many older acked rows are left out. Nothing open or unacked is ever dropped: if those
# alone do not fit, the publish fails loud.
BOARD_BUDGET=60000
render() {
  local k="$1" i rows="" more=""
  for ((i = 0; i < k; i++)); do rows="$rows
${acked[$i]}"; done
  (( k < ${#acked[@]} )) && more="

$(( ${#acked[@]} - k )) older decided rows, acked by every seat, are not shown here: the board page and the live search list them."
  printf '%s\n\n%s\n\n%s## Decided (last 7 days)\n\n%s%s%s%s' "$header" "$table" "${mdue:+$mdue

}" "$dtable" "$drows_unacked" "$rows" "$more"
}
k=${#acked[@]}
out="$(render "$k")"
while (( ${#out} > BOARD_BUDGET && k > 0 )); do k=$((k - 1)); out="$(render "$k")"; done
(( ${#out} <= BOARD_BUDGET )) || die "the board body is ${#out} characters with no acked decided row left, over the $BOARD_BUDGET budget (GitHub refuses over 65536): open and unacked rows alone exceed it; ack or wrap up rows"
printf '%s\n' "$out"

if [[ $errors -gt 0 ]]; then die "$errors decision issue(s) have a malformed body (named above); board not published"; fi

if [[ $publish -eq 1 ]]; then
  [[ -n "$repo" ]] || die "--publish needs --repo <owner/repo>"
  coord_write_guard "$repo"
  title="Pending decisions (generated)"
  # The list API, not search (search lags a create by seconds). The list API lags a create too (measured 2026-10-15), so a create here is followed by a re-read before a second publish can run.
  existing="$(issues_list "$repo" -f state=open | jq -r --arg t "$title" '[.[] | select(.pull_request == null and .title == $t)] | sort_by(.number) | .[0].number // empty')"
  tmp="$(mktemp)"; printf '%s\n' "$out" > "$tmp"
  if [[ -z "$existing" ]]; then
    newurl="$(issue_create "$repo" --title "$title" --body-file "$tmp")"
    existing="${newurl##*/}"
    pin_issue "$repo" "$existing"
  else
    issue_edit_body "$repo" "$existing" "$tmp"
  fi
  rm -f "$tmp"
  echo
  echo "published: https://github.com/$repo/issues/$existing"
fi
