#!/usr/bin/env bash
# workstream.sh — open a workstream: one GitHub Project plus its tracking issue.
#   workstream.sh new --owner <org-or-user> --title "WS: <name>" --repo <owner/repo>
#       --northstar-file <f> --milestone "<title>|<YYYY-MM-DD>|<what it delivers>" [--milestone …]... [--repos "owner/a — role,owner/b — role"] [--acceptance "<text>"] [--seats "<label — role — login,...>"]
#       [--project <number>]   reuse an existing project instead of creating one
# At least one milestone is required: the seat sets out its milestones at the start, so it schedules its own work. Each
# is a GitHub milestone on --repo, made by milestone_create (lib.sh, the one owner of the shape; milestone.sh new is the
# same call). They are created before the Project and the tracking issue, so a bad one writes nothing else.
# The Project holds the items (issues and PRs from any repo); the tracking issue in the coordinating
# repo holds the details and the status reports. The project is created private.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

cmd="${1:-}"; shift || true
[[ "$cmd" == "new" ]] || die "usage: workstream.sh new ..."
owner=""; title=""; repo=""; ns_file=""; repos=""; acceptance="<to be stated>"; seats=""; project=""; mss=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) owner="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --northstar-file) ns_file="$2"; shift 2 ;;
    --repos) repos="$2"; shift 2 ;;
    --acceptance) acceptance="$2"; shift 2 ;;
    --seats) seats="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --milestone) mss+=("$2"); shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$owner" && -n "$title" && -n "$repo" && -n "$ns_file" ]] || die "new needs --owner --title --repo --northstar-file"
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
for i in "${!ms_t[@]}"; do u="$(milestone_create "$repo" "${ms_t[$i]}" "${ms_d[$i]}" "${ms_w[$i]}")" || exit 1; echo "milestone: $u"; done

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
  echo "## Coordinating repo"; echo "$repo"; echo
  echo "## Repos involved"; if [[ -n "$repos" ]]; then tr ',' '\n' <<< "$repos" | sed 's/^ *//'; else echo "$repo"; fi; echo
  echo "## Acceptance"; echo "$acceptance"; echo
  echo "## Milestones"; echo "https://github.com/$repo/milestones"; echo
  echo "## Seats"; if [[ -n "$seats" ]]; then tr ',' '\n' <<< "$seats" | sed 's/^ *//'; else echo "<label — role — login>"; fi
} > "$tmp"
iurl="$(issue_create "$repo" --title "$title" --label workstream --body-file "$tmp")"
rm -f "$tmp"
project_cmd item-add "$project" --owner "$owner" --url "$iurl" >/dev/null
echo "project:  $purl"
echo "tracking: $iurl"
