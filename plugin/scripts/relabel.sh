#!/usr/bin/env bash
# relabel.sh — move rows from bare seat:<LABEL> labels to qualified seat:<login>/<LABEL> labels. Dry run by default.
#   relabel.sh [--apply]
# Run from the checkout whose roster names every seat (the ecosystem index repo): every bare label is
# resolved through this roster (seat_id). Over the repos of the roster's owners it finds the `decision`
# and `workstream` issues, open or closed in the last 30 days, that carry a bare seat label, and prints
#   owner/repo#N  seat:X -> seat:<login>/X
# --apply creates the qualified label in that repo, adds it, and removes the bare one. Then it reports the
# bare label definitions left per repo, and (--apply) deletes a definition only when no issue or pull
# request at all, open or closed, of any age, still carries it (measured by the list API). Exits 2 naming every row it could not relabel.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

apply=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) apply=1; shift ;;
    *) die "unknown argument $1" ;;
  esac
done
roster="$(roster_path)"
roster_check_unique "$roster"
scope="$(roster_user_terms)"
since="$(date -u -v-30d +%Y-%m-%d 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%d)"
bare_re="^seat:${SEAT_LABEL_PART}\$"

# The search API cannot match a label prefix: fetch the decision and workstream issues, filter labels here.
found='[]'
for kind in decision workstream; do
  for q in "is:issue label:$kind is:open $scope" "is:issue label:$kind is:closed updated:>=$since $scope"; do
    got="$(search_issues "$q")" || die "search failed: $q"
    found="$(jq -s 'add | unique_by(.html_url)' <(printf '%s\n' "$found") <(printf '%s\n' "$got"))"
  done
done
rows="$(jq -r --arg re "$bare_re" '.[] | (.repository_url | sub(".*/repos/"; "")) as $r | .number as $n | .labels[].name | select(test($re)) | [$r, $n, .] | @tsv' <<< "$found" | sort -t$'\t' -k1,1 -k2,2n)"

echo "== rows carrying a bare seat label ($([[ $apply -eq 1 ]] && echo apply || echo 'dry run; --apply to relabel'))"
failed=""; n=0; repos_seen=""
while IFS=$'\t' read -r repo num bare; do
  [[ -n "$repo" ]] || continue
  n=$((n+1)); repos_seen="$repos_seen$repo"$'\n'
  if ! id="$(seat_id "${bare#seat:}" 2>&1)"; then
    echo "$repo#$num  $bare -> UNRESOLVED ($id)"
    failed="$failed  $repo#$num $bare: does not resolve through $roster"$'\n'; continue
  fi
  echo "$repo#$num  $bare -> seat:$id"
  [[ $apply -eq 1 ]] || continue
  if seat_label_ensure "$repo" "$id" && issue_add_labels "$repo" "$num" "seat:$id" && issue_remove_label "$repo" "$num" "$bare"; then
    echo "  relabeled"
  else
    failed="$failed  $repo#$num $bare: the label calls failed (403 = no write access)"$'\n'
  fi
done <<< "$rows"
echo
echo "rows per repo:"
if [[ $n -eq 0 ]]; then echo "  (none)"; else printf '%s' "$repos_seen" | sort | uniq -c | awk '{ printf "  %s  %d\n", $2, $1 }'; fi

# Bare label definitions: in every repo the roster names and every repo a row was found in.
echo
echo "== bare seat label definitions left"
repos="$( { jq -r '[.repo, .board, (.seats[].repo)] | map(select(. != null)) | .[]' "$roster"; printf '%s' "$repos_seen"; } | sed '/^$/d' | sort -u)"
while IFS= read -r repo; do
  [[ -n "$repo" ]] || continue
  if ! defs="$(repo_labels "$repo" 2>/dev/null)"; then echo "$repo  (labels unreadable: 403 = no access)"; continue; fi
  defs="$(printf '%s\n' "$defs" | grep -E "$bare_re" || true)"
  if [[ -z "$defs" ]]; then echo "$repo  none"; continue; fi
  while IFS= read -r d; do
    # The list API, not search: no index lag, no 30/min search budget, and it returns pull requests too.
    c="$(issues_list "$repo" -f labels="$d" -f state=all | jq length)" || die "cannot list the issues carrying $d in $repo"
    if [[ "$c" -eq 0 ]]; then
      if [[ $apply -eq 1 ]]; then label_delete "$repo" "$d" && echo "$repo  $d  carried by nothing: definition deleted"
      else echo "$repo  $d  carried by nothing: deleted by --apply"; fi
    else
      echo "$repo  $d  kept: $c issue(s) or pull request(s), open or closed, still carry it"
    fi
  done <<< "$defs"
done <<< "$repos"

echo
echo "$n row(s) with a bare seat label"
if [[ -n "$failed" ]]; then echo "NOT relabeled:" >&2; printf '%s' "$failed" >&2; exit 2; fi
