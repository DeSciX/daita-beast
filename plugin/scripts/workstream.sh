#!/usr/bin/env bash
# workstream.sh — a workstream: one GitHub Project, one tracking issue in its master repo, and the seat map on it.
#   workstream.sh new --slug <slug> --owner <org-or-user> --title "WS: <name>" --repo <owner/repo>
#       --northstar-file <f> --milestone "<title>|<YYYY-MM-DD>|<what it delivers>" [--milestone …]... [--repos "owner/a — role,owner/b — role"]
#       [--acceptance "<text>"] [--project <number>]
#       The tracking issue carries the labels `workstream` and `ws:<slug>` (the slug is the workstream's id, found by
#       those labels, never stored by number: workstream_issue, lib.sh); its repo is the master; its `## Seats` table
#       starts empty. Refused when an open issue of that slug exists.
#   workstream.sh seat-add <slug> <login/LABEL> --repo <owner/repo> --home "<checkout | worktree <branch> | wrapper | subdir <dir>>" --agent <name>
#       adds the seat to the `## Seats` table (the one owner of which seats are in the workstream). The repo must be
#       private and not public-intended; the agent must exist (<repo>/.claude/agents/<name>.md, or daita-beast:seat).
#   workstream.sh seat-remove <slug> <login/LABEL>
#   workstream.sh seats <slug>                 prints the table
#   workstream.sh render <slug> [--pr]         the master repo's CLAUDE.md block for this workstream (one per slug,
#       between <!-- beast:workstream begin <slug> --> and end markers): into the local checkout of the master when this
#       machine has one (then prints the commit command), else through the contents API on the default branch (a stale
#       sha is a 409, exit 1, nothing written), or with --pr on a branch with a pull request.
# At least one milestone is required: the seat sets out its milestones at the start, so it schedules its own work. Each
# is a GitHub milestone on --repo, made by milestone_create (lib.sh, the one owner of the shape; milestone.sh new is the
# same call). They are created before the Project and the tracking issue, so a bad one writes nothing else.
# The Project holds the items (issues and PRs from any repo); the tracking issue holds the details, the seat map and
# the status reports. The project is created private.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

cmd="${1:-}"; shift || true
case "$cmd" in
  new)
    slug=""; owner=""; title=""; repo=""; ns_file=""; repos=""; acceptance="<to be stated>"; project=""; mss=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --slug) slug="$2"; shift 2 ;;
        --owner) owner="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --repo) repo="$2"; shift 2 ;;
        --northstar-file) ns_file="$2"; shift 2 ;;
        --repos) repos="$2"; shift 2 ;;
        --acceptance) acceptance="$2"; shift 2 ;;
        --project) project="$2"; shift 2 ;;
        --milestone) mss+=("$2"); shift 2 ;;
        --seats) die "--seats is gone: the seats of a workstream are its tracking issue's \`## Seats\` table, written by workstream.sh seat-add (seat.sh new runs it)" ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "$slug" && -n "$owner" && -n "$title" && -n "$repo" && -n "$ns_file" ]] || die "new needs --slug --owner --title --repo --northstar-file"
    [[ "$slug" =~ $WS_SLUG_RE ]] || die "--slug '$slug' is not a slug (a-z, 0-9, -; starts with a letter or digit)"
    [[ -f "$ns_file" ]] || die "northstar file not found: $ns_file"
    [[ "$title" == WS:* ]] || title="WS: $title"
    [[ ${#mss[@]} -gt 0 ]] || die "new needs at least one --milestone \"<title>|<YYYY-MM-DD>|<what it delivers>\": set out the workstream's milestones at its start"
    ms_t=(); ms_d=(); ms_w=()
    for m in "${mss[@]}"; do
      [[ "$m" == *'|'*'|'* ]] || die "--milestone '$m' is not \"<title>|<YYYY-MM-DD>|<what it delivers>\""
      t="${m%%|*}"; rest="${m#*|}"; d="${rest%%|*}"; w="${rest#*|}"
      milestone_title_check "$t"; milestone_date_check "$d"
      [[ -n "${w//[[:space:]]/}" ]] || die "--milestone '$m': what it delivers is empty"
      ms_t+=("$t"); ms_d+=("$d"); ms_w+=("$w")
    done
    coord_write_guard "$repo"
    have="$(workstream_candidates "$slug")" || exit 1
    [[ -z "$have" ]] || die "workstream $slug exists: $(cut -f5 <<< "$have" | tr '\n' ' ')— one open tracking issue per slug"
    for i in "${!ms_t[@]}"; do u="$(milestone_create "$repo" "${ms_t[$i]}" "${ms_d[$i]}" "${ms_w[$i]}")" || exit 1; echo "milestone: $u"; done
    label_ensure_template "$repo" workstream
    workstream_label_ensure "$repo" "$slug"

    # The Project first, then the tracking issue that cites its URL.
    created=0
    if [[ -z "$project" ]]; then
      pj="$(project_cmd create --owner "$owner" --title "$title" --format json)"
      project="$(jq -r .number <<< "$pj")"; created=1
    fi
    purl="$(project_cmd view "$project" --owner "$owner" --format json -q .url)"
    if [[ $created -eq 1 && "${repo%%/*}" == "$owner" ]]; then
      project_cmd link "$project" --owner "$owner" --repo "$repo" >/dev/null
    fi

    tmp="$(mktemp)"
    {
      echo "## Northstar"; cat "$ns_file"; echo
      echo "## Project"; echo "$purl"; echo
      echo "## Master repo"; echo "$repo"; echo
      echo "## Repos involved"; if [[ -n "$repos" ]]; then tr ',' '\n' <<< "$repos" | sed 's/^ *//'; else echo "$repo"; fi; echo
      echo "## Acceptance"; echo "$acceptance"; echo
      echo "## Milestones"; echo "https://github.com/$repo/milestones"; echo
      echo "## Seats"; printf '%s\n%s\n' "$WS_SEATS_HEADER" "$WS_SEATS_SEP"
    } > "$tmp"
    iurl="$(issue_create "$repo" --title "$title" --label workstream --label "ws:$slug" --body-file "$tmp")"
    rm -f "$tmp"
    project_cmd item-add "$project" --owner "$owner" --url "$iurl" >/dev/null
    echo "workstream: $slug (labels workstream, ws:$slug; master $repo)"
    echo "project:  $purl"
    echo "tracking: $iurl"
    echo "seats: workstream.sh seat-add $slug <login/LABEL> --repo <owner/repo> --home \"<kind [arg]>\" --agent <name> (seat.sh new runs it), then workstream.sh render $slug"
    ;;
  seat-add)
    slug="${1:-}"; seat="${2:-}"; shift 2 || true
    repo=""; home=""; agent=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) repo="$2"; shift 2 ;;
        --home) home="$2"; shift 2 ;;
        --agent) agent="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "$slug" && -n "$seat" && -n "$repo" && -n "$home" && -n "$agent" ]] || die "usage: workstream.sh seat-add <slug> <login/LABEL> --repo <owner/repo> --home \"<checkout | worktree <branch> | wrapper | subdir <dir>>\" --agent <name>"
    [[ "$slug" =~ $WS_SLUG_RE ]] || die "'$slug' is not a workstream slug (a-z, 0-9, -)"
    [[ "$seat" =~ $SEAT_ID_RE ]] || die "seat '$seat' is not <login>/<LABEL> (the slug is the workstream's)"
    [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--repo '$repo' is not owner/repo"
    home="$(ws_home_word $(ws_home_parse "$home" | tr '\t' ' '))" || exit 1
    why="$(repo_public_why "$repo")" || exit 1
    [[ -z "$why" ]] || die "refused: $repo is $why. A seat's repo is private: its rows, desk and status are coordination writes, which never go to a public repo (the twin's roster names the public one in \"publishes_to\")"
    seat_agent_check "$repo" "$agent" || exit 1
    rows="$(ws_seats_parse "$slug")" || exit 1
    ! grep -q "^$seat	" <<< "$rows" || die "seat $seat is already in the \`## Seats\` table of workstream $slug: $(awk -F'\t' -v s="$seat" '$1 == s {print "repo " $2 ", home " $3 ", agent " $4}' <<< "$rows"); remove it first to change it (workstream.sh seat-remove)"
    rows="$(printf '%s\n%s\t%s\t%s\t%s\n' "$rows" "$seat" "$repo" "$home" "$agent" | sed '/^$/d')"
    ref="$(ws_seats_write "$slug" "$rows")" || exit 1
    echo "seat $slug/${seat#*/}/${seat%%/*} added to the \`## Seats\` table of $ref (repo $repo, home $home, agent $agent)"
    echo "then: workstream.sh render $slug (the master's CLAUDE.md block)"
    ;;
  seat-remove)
    slug="${1:-}"; seat="${2:-}"
    [[ -n "$slug" && -n "$seat" ]] || die "usage: workstream.sh seat-remove <slug> <login/LABEL>"
    [[ "$slug" =~ $WS_SLUG_RE ]] || die "'$slug' is not a workstream slug (a-z, 0-9, -)"
    seat="$(seat_short "$seat")" || exit 1
    rows="$(ws_seats_parse "$slug")" || exit 1
    grep -q "^$seat	" <<< "$rows" || die "seat $seat is not in the \`## Seats\` table of workstream $slug (its seats: $(cut -f1 <<< "$rows" | tr '\n' ' '))"
    ref="$(ws_seats_write "$slug" "$(awk -F'\t' -v s="$seat" '$1 != s' <<< "$rows")")" || exit 1
    echo "seat $seat removed from the \`## Seats\` table of $ref"
    echo "then: workstream.sh render $slug (the master's CLAUDE.md block)"
    ;;
  seats)
    slug="${1:-}"; [[ -n "$slug" ]] || die "usage: workstream.sh seats <slug>"
    ws_seats_render "$slug" "$(ws_seats_parse "$slug")"
    ;;
  render)
    slug="${1:-}"; shift || true
    pr=0
    while [[ $# -gt 0 ]]; do case "$1" in --pr) pr=1; shift ;; *) die "unknown argument $1" ;; esac; done
    [[ -n "$slug" ]] || die "usage: workstream.sh render <slug> [--pr]"
    master="$(workstream_master "$slug")" || exit 1
    coord_write_guard "$master"
    co=""
    while IFS= read -r c; do
      [[ -n "$c" ]] || continue
      [[ "$(repo_slug "$c" 2>/dev/null | tr 'A-Z' 'a-z')" == "$(tr 'A-Z' 'a-z' <<< "$master")" ]] || continue
      co="$c"; break
    done < <(beast_checkouts "$PWD")
    if [[ -n "$co" && $pr -eq 0 ]]; then
      [[ -f "$co/CLAUDE.md" ]] || : > "$co/CLAUDE.md"
      ws_block_write_local "$co/CLAUDE.md" "$slug" || exit 1
      if [[ -z "$(git -C "$co" status --porcelain -- CLAUDE.md)" ]]; then echo "nothing to commit in $co"
      else echo "commit it: git -C $co add CLAUDE.md && git -C $co commit -m \"CLAUDE.md: workstream $slug block (workstream.sh render)\""; fi
    else
      [[ -z "$co" ]] || echo "(--pr: written through GitHub, not the local checkout $co)"
      out="$(ws_block_write_remote "$master" "$slug" "$([[ $pr -eq 1 ]] && echo pr)")" || exit 1
      echo "master $master CLAUDE.md: $out"
    fi
    ;;
  *) die "usage: workstream.sh new --slug <slug> … | seat-add <slug> <login/LABEL> --repo --home --agent | seat-remove <slug> <login/LABEL> | seats <slug> | render <slug> [--pr]" ;;
esac
