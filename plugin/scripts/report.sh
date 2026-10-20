#!/usr/bin/env bash
# report.sh — activity for a period, computed from GitHub, as JSON (the reporter agent renders it); and the
# participant report of a milestone (report.sh milestone, below).
#   report.sh --repos <a,b> --since <YYYY-MM-DD> [--until <YYYY-MM-DD>] [--community <TOKEN> --month <YYYY-MM>]
# Per login: merged PRs authored, reviews given, issues closed (by closer when GitHub tells us).
# Per seat id: decisions executed (close comments "Closed by seat <id>"), BEAST-STATUS reports; a bare label in
# either is resolved through this repo's roster (seat_resolve), and one that does not resolve is named and dropped.
# Plus open bounties, and (with --community/--month) the ledger's awards.
#
#   report.sh milestone "<title>" [--repo <owner/repo>] [--post --by <SEAT> | --outside-notes]
# The participant report of one milestone (default repo: the roster "repo"): ONE report addressed per participant, every
# seat of the roster plus every outside contributor (a login holding no seat) awarded on the milestone's items. Each
# section says what the participant earned this milestone (the BEAST-AWARD comments on the issues and PRs filed under
# it, read through ledger.sh for every month the milestone spans, in the token of this checkout's award policy; a repo
# with no policy awards nothing, and says so) and the state of each thing it waits on (deps_declared + dep_state, the
# measure deps.sh prints). An award goes to a login; it counts for a seat of that login when the item carries the seat's
# label, and is named as unattributed otherwise. Without --post it prints every section and writes nothing. With --post
# (every seat must have a desk, checked before any write): each seat's section is a desk message to it from --by
# (desk.sh msg), and the milestone's description keeps the summary as its one Report line (the latest only). An outside
# contributor has no desk: their section is printed for the seat to deliver, and --outside-notes prints only the outside
# contributors' sections for the public release notes (wrapup.sh run): markdown for outside readers, no private link.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq
here="$(dirname "${BASH_SOURCE[0]}")"

if [[ "${1:-}" == milestone ]]; then
  shift; title="${1:-}"; shift || true
  milestone_title_check "$title"
  repo=""; post=0; by=""; onotes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --post) post=1; shift ;;
      --outside-notes) onotes=1; shift ;;
      --by) by="$2"; shift 2 ;;
      *) die "unknown argument $1" ;;
    esac
  done
  [[ -n "$repo" ]] || repo="$(roster_repo)" || exit 1
  [[ $post -eq 0 || -n "$by" ]] || die "--post needs --by <SEAT> (the sender of the desk messages)"
  [[ $post -eq 0 || $onotes -eq 0 ]] || die "--outside-notes prints and posts nothing: drop --post"
  [[ -z "$by" ]] || by="$(seat_rostered "$by")" || exit 1
  m="$(milestone_get "$repo" "$title")" || exit 1
  items="$(issues_list "$repo" -f milestone="$(jq -r .number <<< "$m")" -f state=all | jq -c '[.[] | {url: .html_url, labels: [.labels[].name]}]')" || die "cannot list the items of milestone \"$title\" in $repo"
  # Awards on the milestone's items, from the ledger (the one parser of BEAST-AWARD), for every month the milestone spans.
  awards='[]'; awnote=""
  if [[ -f "$(repo_root)/.beast/award-policy.md" ]]; then
    tok="$(award_policy_token "$repo")" || exit 1
    from="$(jq -r '.created_at[:7]' <<< "$m")"; to="$(jq -r '(.closed_at // (now | todate))[:7]' <<< "$m")"
    tmp="$(mktemp -d)"; mo="$from"
    while :; do
      rc=0; "$here/ledger.sh" --community "$tok" --repos "$repo" --month "$mo" --out "$tmp" >/dev/null 2>"$tmp/err" || rc=$?
      [[ $rc -eq 0 ]] || { cat "$tmp/err" >&2; rm -rf "$tmp"; die "ledger.sh $mo for $repo exited $rc (named above): a report with holes is never sent"; }
      awards="$(jq -s --argjson a "$awards" --argjson items "$items" '$a + [.[] | select(.item as $i | $items | any(.url == $i))]' "$tmp/$mo.jsonl")" || { rm -rf "$tmp"; die "cannot read the ledger rows of $mo"; }
      [[ "$mo" != "$to" ]] || break
      y="${mo%-*}"; mm="${mo#*-}"; mm=$((10#$mm + 1)); if (( mm > 12 )); then mm=1; y=$((y + 1)); fi; mo="$(printf '%04d-%02d' "$y" "$mm")"
    done
    rm -rf "$tmp"
  else
    awnote="no award policy for $repo in $(repo_root) (.beast/award-policy.md): it awards nothing"
  fi
  seats="$(roster_seat_ids)" || exit 1
  seat_logins="$(sed 's#/.*##' <<< "$seats" | sort -u)"
  outside=(); while IFS= read -r l; do [[ -n "$l" ]] && outside+=("$l"); done < <(jq -r '.[].to' <<< "$awards" | sort -u | grep -vxF -f <(printf '%s\n' "$seat_logins") || true)
  if [[ $onotes -eq 1 ]]; then
    # The outside contributors' sections for outside readers: who, what they earned, for what; never an item's link
    # (items live in the private twin). Nothing at all when there is none.
    [[ ${#outside[@]} -gt 0 ]] || exit 0
    echo "## Outside contributors"; echo
    for l in "${outside[@]}"; do
      jq -r --arg l "$l" '[.[] | select(.to == $l)] | "- @\($l): \(group_by(.token) | map("\(map(.amount) | add) \(.[0].token)") | join(", ")) for " + (map("\"\(.for)\"") | join("; "))' <<< "$awards" || die "cannot read the awards of @$l"
    done
    exit 0
  fi
  stamp="$(utc_now)"
  head_line="Milestone \"$title\" of $repo ($(jq -r '"\(.state), due \(.due_on // "none" | .[:10])"' <<< "$m"), delivers: $(milestone_field "$m" Delivers)) $(jq -r .html_url <<< "$m")"
  # earned <login> <seat id | ""> : the section's earnings lines. With a seat: awards to its login on items carrying its label.
  earned() {
    local login="$1" id="$2" got
    got="$(jq -c --arg l "$login" --arg s "seat:$id" --arg id "$id" --argjson items "$items" '[.[] | select(.to == $l) | . as $a
      | select($id == "" or ($items | any(.url == $a.item and (.labels | index($s)))))]' <<< "$awards")" || die "cannot read the awards of @$login"
    if [[ -n "$awnote" ]]; then echo "Earned this milestone: nothing ($awnote)."
    elif [[ "$(jq length <<< "$got")" -eq 0 ]]; then echo "Earned this milestone: nothing awarded to @$login${id:+ for $id} on its items."
    else
      echo "Earned this milestone: $(jq -r 'group_by(.token) | map("\(map(.amount) | add) \(.[0].token)") | join(", ")' <<< "$got") — $(jq length <<< "$got") award(s):"
      jq -r '.[] | "  - \(.amount) \(.token) for \"\(.for)\" on \(.item) (by @\(.by), \(.at[:10]))"' <<< "$got"
    fi
  }
  n_rel=0; n_del=0; n_chg=0; n_wait=0; sections=(); targets=()
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    home="$(seat_repo "$id")" || exit 1
    decl="$(deps_declared "$id")" || exit 1
    e="$(earned "$(seat_login "$id")" "$id")" || exit 1
    sec="$head_line — report for $id, $stamp
$e
What you wait on:"
    if [[ -z "$decl" ]]; then sec="$sec
  (nothing declared: a \"Waits on:\" line on your open rows, open desk asks or open milestones)"
    else
      while IFS=$'\t' read -r ref at; do
        st="$(dep_state "$ref" "$home")" || exit 1
        IFS=$'\t' read -r s_ d_ <<< "$st"
        case "$s_" in released) n_rel=$((n_rel+1)) ;; delayed) n_del=$((n_del+1)) ;; "changed direction") n_chg=$((n_chg+1)) ;; *) n_wait=$((n_wait+1)) ;; esac
        sec="$sec
  - $ref: $s_ — $d_ (declared on $at)"
      done <<< "$decl"
    fi
    sections+=("$sec"); targets+=("$id")
  done <<< "$seats"
  unattr="$(jq -r --argjson items "$items" --arg ls "$(tr '\n' ' ' <<< "$seat_logins")" '.[] | select(.to as $t | ($ls | split(" ") | index($t))) | . as $a
    | select(($items | map(select(.url == $a.item)) | .[0].labels // []) | map(select(startswith("seat:" + $a.to + "/"))) | length == 0)
    | "  - \(.amount) \(.token) to @\(.to) on \(.item): the item carries no seat label of @\(.to)"' <<< "$awards")" || die "cannot read the unattributed awards"
  total="$(jq -r 'if length == 0 then "nothing" else (group_by(.token) | map("\(map(.amount) | add) \(.[0].token)") | join(", ")) end' <<< "$awards")" || die "cannot total the awards"
  summary="$stamp: $(( ${#targets[@]} + ${#outside[@]} )) participant(s) (${#targets[@]} seat(s), ${#outside[@]} outside); earned $total; dependencies: $n_rel released, $n_del delayed, $n_chg changed direction, $n_wait waiting"
  echo "$head_line"
  echo "Summary: $summary"
  [[ -z "$unattr" ]] || { echo "Awards to a seat's login on an item without that seat's label (counted in the total, in no seat's section):"; echo "$unattr"; }
  for i in "${!targets[@]}"; do echo; echo "=== ${targets[$i]} ($([[ $post -eq 1 ]] && echo "posted to its desk" || echo "its desk message")) ==="; echo "${sections[$i]}"; done
  for l in "${outside[@]:-}"; do
    [[ -n "$l" ]] || continue
    echo; echo "=== @$l (outside contributor: no seat, no desk — deliver this section yourself; the release notes carry it, wrapup.sh run) ==="
    echo "$head_line — report for @$l, $stamp"; earned "$l" ""
  done
  [[ $post -eq 1 ]] || { echo; echo "(printed only: --post --by <SEAT> sends each seat its section on its desk and keeps the summary on the milestone)"; exit 0; }
  miss=""; for id in "${targets[@]}"; do f="$(desk_find "$id" "$(seat_repo "$id")")" || exit 1; [[ -n "$f" ]] || miss="$miss $id"; done
  [[ -z "$miss" ]] || die "nothing posted: seat(s) without a desk:$miss — desk.sh open <SEAT> for each, then rerun"
  coord_write_guard "$repo" "$by"
  for i in "${!targets[@]}"; do "$here/desk.sh" msg "${targets[$i]}" --from "$by" --text "${sections[$i]}" >/dev/null || die "the report to ${targets[$i]} was not posted (named above)"; echo "posted to the desk of ${targets[$i]}"; done
  refs="$(waits_on_parse "$(jq -r .html_url <<< "$m")" "$(jq -r '.description // ""' <<< "$m")")" || exit 1
  desc="$(milestone_desc "$(milestone_field "$m" Delivers)" "$(milestone_field "$m" Moved)" "$summary" $refs)" || exit 1
  [[ -n "$(jq -r '.due_on // empty' <<< "$m")" ]] || die "milestone \"$title\" has no due date"
  milestone_write "$repo" "$(jq -r .number <<< "$m")" "$(jq -r '.due_on[:10]' <<< "$m")" "$desc" >/dev/null
  echo "summary kept on the milestone: $(jq -r .html_url <<< "$m")"
  exit 0
fi

repos=""; since=""; until_="$(date -u +%Y-%m-%d)"; community=""; month=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos) repos="$2"; shift 2 ;;
    --since) since="$2"; shift 2 ;;
    --until) until_="$2"; shift 2 ;;
    --community) community="$2"; shift 2 ;;
    --month) month="$2"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$repos" && -n "$since" ]] || die "usage: report.sh --repos a,b --since YYYY-MM-DD [--until YYYY-MM-DD] [--community TOKEN --month YYYY-MM]"

merged="[]"; reviews="[]"; closed="[]"; seats="[]"; bounties="[]"
for repo in ${repos//,/ }; do
  m="$(search_issues "repo:$repo is:pr is:merged merged:$since..$until_" | jq --arg r "$repo" '[.[] | {repo:$r, number, url: .html_url, title, author: .user.login, mergedAt: .pull_request.merged_at}]')" || die "cannot list merged PRs of $repo"
  merged="$(jq -s 'add' <(echo "$merged") <(echo "$m"))"
  for n in $(jq -r '.[].number' <<< "$m"); do
    rv="$(pr_reviews "$repo" "$n" | jq --arg r "$repo" --argjson n "$n" '[.[] | {reviewer: .user.login, state, at: .submitted_at, repo:$r, pr:$n}]')" || die "cannot read the reviews of $repo#$n"
    reviews="$(jq -s 'add' <(echo "$reviews") <(echo "$rv"))"
  done
  # Issues closed in the window: the list is filtered server-side by updated-since (a close updates the
  # issue), then by closed_at here; pull requests are dropped (the endpoint returns both).
  c="$(issues_list "$repo" -f state=closed -f since="${since}T00:00:00Z" | jq --arg s "$since" --arg u "$until_" '[.[] | select(.pull_request == null and .closed_at[:10] >= $s and .closed_at[:10] <= $u)]')" || die "cannot list closed issues of $repo"
  for n in $(jq -r '.[].number' <<< "$c"); do
    cm="$(issue_comments "$repo" "$n")" || die "cannot read the comments of $repo#$n"
    c="$(jq --argjson n "$n" --argjson cm "$cm" 'map(if .number == $n then . + {comments: $cm} else . end)' <<< "$c")"
  done
  closed="$(jq -s 'add' <(echo "$closed") <(jq --arg r "$repo" '[.[] | {repo:$r, number, url: .html_url, title, closedAt: .closed_at, labels: [.labels[].name], closer_comment: ([.comments[] | select(.body | startswith("Closed on the word"))] | last | .body // "")}]' <<< "$c"))"
  s="$(jq --arg r "$repo" '[.[] | .comments[] | select(.body | test("^BEAST-STATUS seat=|Closed by seat ")) | {repo:$r, at: .created_at, body: (.body | split("\n") | .[0])}]' <<< "$c")"
  seats="$(jq -s 'add' <(echo "$seats") <(echo "$s"))"
  b="$(issues_list "$repo" -f labels=bounty -f state=open | jq --arg r "$repo" '[.[] | select(.pull_request == null) | {repo:$r, number, url: .html_url, title}]')" || die "cannot list the open bounties of $repo"
  bounties="$(jq -s 'add' <(echo "$bounties") <(echo "$b"))"
done

# Every seat named by a status header or a close comment, resolved to its id.
seat_ids="$(jq -r --argjson closed "$closed" --arg re "$SEAT_TOKEN_RE" '
  [.[] | .body | capture("^BEAST-STATUS seat=(?<seat>" + $re + ") ") | .seat] + [$closed[] | .closer_comment | capture("Closed by seat (?<seat>" + $re + ") at ") | .seat] | .[]' <<< "$seats" \
  | while IFS= read -r t; do seat_resolve "$t" || true; done | jq -R . | jq -s .)"

awards="[]"
if [[ -n "$community" && -n "$month" ]]; then
  tmp="$(mktemp -d)"
  rc=0; "$here/ledger.sh" --community "$community" --repos "$repos" --month "$month" --out "$tmp" >/dev/null 2>"$tmp/err" || rc=$?
  # 2 is a ledger with named drops (counted below); any other failure is a ledger that was not read.
  [[ $rc -eq 0 || $rc -eq 2 ]] || { cat "$tmp/err" >&2; rm -rf "$tmp"; die "ledger.sh $month exited $rc (named above): the awards could not be read"; }
  awards="$(jq -s '.' "$tmp/$month.jsonl")" || { rm -rf "$tmp"; die "cannot read the ledger rows of $month"; }
  awards_dropped="$(grep -c '^DROPPED' "$tmp/err" || true)"
  rm -rf "$tmp"
else awards_dropped=0; fi

jq -n --arg since "$since" --arg until "$until_" --argjson merged "$merged" --argjson reviews "$reviews" --argjson closed "$closed" --argjson seat_ids "$seat_ids" --argjson bounties "$bounties" --argjson awards "$awards" --argjson dropped "${awards_dropped:-0}" '
{
  period: {since:$since, until:$until},
  per_login: (
    ([$merged[] | {login: .author, k:"merged_prs"}] + [$reviews[] | {login: .reviewer, k:"reviews"}])
    | group_by(.login) | map({login: .[0].login, merged_prs: ([.[] | select(.k=="merged_prs")] | length), reviews: ([.[] | select(.k=="reviews")] | length)}) | sort_by(-.merged_prs)
  ),
  per_seat: (
    $seat_ids | group_by(.) | map({seat: .[0], events: length}) | sort_by(-.events)
  ),
  decisions_executed: [$closed[] | select(.labels | index("decision")) | {repo, number, url, title, closedAt}],
  merged_prs: $merged, reviews: $reviews, issues_closed: ($closed | length),
  awards: $awards, awards_dropped: $dropped, bounties_open: $bounties
}'
