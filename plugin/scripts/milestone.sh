#!/usr/bin/env bash
# milestone.sh — a seat's milestones: GitHub milestones on its home repo (the roster "repo", or --repo).
#   milestone.sh new "<title>" --due <YYYY-MM-DD> --delivers "<one line>" [--waits-on <seat | owner/repo#N>]... [--repo <owner/repo>]
#   milestone.sh list [--state open|closed|all] [--repo <owner/repo>]
#   milestone.sh move "<title>" --due <YYYY-MM-DD> --why "<one line>" [--repo <owner/repo>]
#       sets the new due date and the description's one Moved line ("later|earlier — <why>"): the latest move only, no history
#   milestone.sh close "<title>" [--carry "<next title>"] [--repo <owner/repo>]
#       refuses while open rows, PRs (issues or PRs filed under it) or open desk asks (header milestone="<title>") are
#       attached, naming each; --carry moves every one of them to the next open milestone first, then closes.
# The shape (title, GitHub's due_on, the description lines) has one owner: the milestone_* functions in lib.sh.
# Every write passes coord_write_guard. After a close: report.sh milestone "<title>" --post --by <SEAT>.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq
here="$(dirname "${BASH_SOURCE[0]}")"

cmd="${1:-}"; shift || true
title=""
case "$cmd" in new|move|close) title="${1:-}"; shift || true; milestone_title_check "$title" ;; list) ;; *) die "usage: milestone.sh new|list|move|close (see the header of $0)" ;; esac
repo=""; due=""; delivers=""; why=""; carry=""; state=open; waits=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --due) due="$2"; shift 2 ;;
    --delivers) delivers="$2"; shift 2 ;;
    --why) why="$2"; shift 2 ;;
    --carry) carry="$2"; shift 2 ;;
    --state) state="$2"; shift 2 ;;
    --waits-on) w="$(waits_on_ref "$2")" || exit 1; waits+=("$w"); shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$repo" ]] || repo="$(roster_repo)" || exit 1

# attached <repo> <ms-json>: "<kind>\t<ref>\t<url>" of every open item filed under the milestone: issues and PRs (by
# GitHub's milestone field) and open desk asks of the repo's desks whose header names it.
attached() {
  local repo="$1" ms="$2" num t d seat parsed
  num="$(jq -r .number <<< "$ms")"; t="$(jq -r .title <<< "$ms")"
  issues_list "$repo" -f milestone="$num" -f state=open | jq -r '.[] | [(if .pull_request then "PR" else "issue" end), "#\(.number)", .html_url] | @tsv' \
    || die "cannot list the items of milestone \"$t\" in $repo"
  while IFS=$'\t' read -r d seat; do
    [[ -n "$d" ]] || continue
    [[ -n "$seat" && "$seat" != *' '* ]] || die "$repo#$d is a desk without exactly one seat: label"
    parsed="$(desk_parse "$seat" "$(row_read "$repo" "$d")")" || exit 1
    jq -r --arg t "$t" --arg s "$seat" '.asks[] | select(.state == "open" and .milestone == $t) | ["ask", "\($s) n=\(.n)", .url] | @tsv' <<< "$parsed"
  done < <(issues_list "$repo" -f labels=desk -f state=open | jq -r '.[] | select(.pull_request == null) | [.number, ([.labels[].name | select(startswith("seat:")) | ltrimstr("seat:")] | join(" "))] | @tsv')
}

case "$cmd" in
  new)
    [[ -n "$due" && -n "$delivers" ]] || die "usage: milestone.sh new \"<title>\" --due <YYYY-MM-DD> --delivers \"<one line>\" [--waits-on <ref>]... [--repo <owner/repo>]"
    coord_write_guard "$repo"
    milestone_create "$repo" "$title" "$due" "$delivers" ${waits[@]+"${waits[@]}"}
    ;;
  list)
    case "$state" in open|closed|all) ;; *) die "--state is open, closed or all" ;; esac
    all="$(milestone_all "$repo" "$state")" || exit 1
    if [[ "$(jq length <<< "$all")" -eq 0 ]]; then echo "$repo: no $state milestone"; exit 0; fi
    while IFS= read -r m; do
      d="$(milestone_days "$m")"; slip="$(milestone_slip "$m")"
      printf '%s  "%s"  due %s%s  %s open / %s closed  delivers: %s%s  %s\n' "$(jq -r .state <<< "$m")" "$(jq -r .title <<< "$m")" \
        "$(jq -r '.due_on // "none" | .[:10]' <<< "$m")" "$( [[ -z "$d" || "$(jq -r .state <<< "$m")" != open ]] || { (( d < 0 )) && echo " (OVERDUE by $(( -d )) day(s))" || echo " (in $d day(s))"; } )" \
        "$(jq -r .open_issues <<< "$m")" "$(jq -r .closed_issues <<< "$m")" "$(milestone_field "$m" Delivers)" "${slip:+  [late: $slip]}" "$(jq -r .html_url <<< "$m")"
      refs="$(waits_on_parse "$(jq -r .html_url <<< "$m")" "$(jq -r '.description // ""' <<< "$m")")" || exit 1
      [[ -z "$refs" ]] || sed 's/^/    waits on: /' <<< "$refs"
    done < <(jq -c '.[]' <<< "$all")
    ;;
  move)
    [[ -n "$due" && -n "${why//[[:space:]]/}" ]] || die "usage: milestone.sh move \"<title>\" --due <YYYY-MM-DD> --why \"<one line>\" [--repo <owner/repo>]: a move carries its why"
    [[ "$why" != *$'\n'* ]] || die "--why is one line"
    milestone_date_check "$due"
    coord_write_guard "$repo"
    m="$(milestone_get "$repo" "$title")" || exit 1
    [[ "$(jq -r .state <<< "$m")" == open ]] || die "milestone \"$title\" of $repo is closed: a closed milestone does not move"
    old="$(jq -r '.due_on // "" | .[:10]' <<< "$m")"
    [[ "$old" != "$due" ]] || die "milestone \"$title\" is already due $due"
    if [[ -z "$old" || "$due" > "$old" ]]; then dir=later; else dir=earlier; fi
    refs="$(waits_on_parse "$(jq -r .html_url <<< "$m")" "$(jq -r '.description // ""' <<< "$m")")" || exit 1
    desc="$(milestone_desc "$(milestone_field "$m" Delivers)" "$dir — $why" "$(milestone_field "$m" Report)" $refs)" || exit 1
    out="$(milestone_write "$repo" "$(jq -r .number <<< "$m")" "$due" "$desc")" || exit 1
    echo "moved \"$title\" $dir: ${old:-no date} -> $due ($why) $(jq -r .html_url <<< "$out")"
    ;;
  close)
    coord_write_guard "$repo"
    m="$(milestone_get "$repo" "$title")" || exit 1
    [[ "$(jq -r .state <<< "$m")" == open ]] || die "milestone \"$title\" of $repo is already closed"
    items="$(attached "$repo" "$m")" || exit 1
    if [[ -n "$items" && -z "$carry" ]]; then
      echo "daita-beast: refused: milestone \"$title\" of $repo has $(wc -l <<< "$items" | tr -d ' ') open item(s) attached; finish them, or close with --carry \"<next open milestone>\":" >&2
      awk -F'\t' '{ print "  " $1 " " $2 "  " $3 }' <<< "$items" >&2
      exit 1
    fi
    if [[ -n "$items" ]]; then
      [[ "$carry" != "$title" ]] || die "--carry names the milestone being closed"
      nn="$(milestone_require "$repo" "$carry")" || exit 1
      while IFS=$'\t' read -r kind ref url; do
        case "$kind" in
          issue|PR) milestone_set "$repo" "${ref#\#}" "$nn"; echo "carried $kind $repo$ref to \"$carry\"" ;;
          ask)
            seat="${ref%% *}"; cid="${url##*#issuecomment-}"
            [[ "$cid" =~ ^[0-9]+$ ]] || die "cannot read the comment id of the ask $url"
            body="$(gh_get "repos/$repo/issues/comments/$cid" | jq -r .body)" || die "cannot read the ask $url"
            first="$(head -1 <<< "$body" | tr -d '\r')"
            hdr="$(jq -rn --arg f "$first" --arg re "$ASK_HEADER_RE" '$f | capture($re) | [.n, .seat, .at] | @tsv')" || die "the ask $url has no header of the ask shape"
            IFS=$'\t' read -r an aseat aat <<< "$hdr"
            tmp="$(mktemp)"; { ask_header "$an" "$aseat" "$aat" "$carry"; tail -n +2 <<< "$body"; } > "$tmp"
            comment_edit "$repo" "$cid" "$tmp" >/dev/null; rm -f "$tmp"
            "$here/desk.sh" publish "$seat" >/dev/null
            echo "carried ask $ref to \"$carry\" ($url)" ;;
        esac
      done <<< "$items"
      # the issues list lags a milestone change by seconds (as it lags a create, issues_list_shows): re-read for up to 60 s
      for _ in $(seq 1 30); do left="$(attached "$repo" "$m")" || exit 1; [[ -n "$left" ]] || break; sleep 2; done
      [[ -z "$left" ]] || die "after the carry, still attached to \"$title\" after 60 s: $(tr '\n' ' ' <<< "$left")"
    fi
    gh_send PATCH "repos/$repo/milestones/$(jq -r .number <<< "$m")" -f state=closed >/dev/null
    echo "closed milestone \"$title\" of $repo $(jq -r .html_url <<< "$m")"
    echo "next: report.sh milestone \"$title\" --repo $repo --post --by <SEAT> (one report per participant, on their desks)"
    ;;
esac
