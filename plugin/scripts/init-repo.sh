#!/usr/bin/env bash
# init-repo.sh — make a repo a Beast coordinating repo: labels, issue templates, roster skeleton.
#   init-repo.sh <owner/repo> [--path <local checkout>] [--token <SYMBOL>]
# Idempotent: labels are created or updated in place; files are written only when absent. The award
# policy is written only with --token (the community token), filled; no file ever carries a placeholder.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq
here="$(dirname "${BASH_SOURCE[0]}")"; templates="$here/../templates"

repo="${1:-}"; shift || true
[[ -n "$repo" ]] || die "usage: init-repo.sh <owner/repo> [--path <dir>] [--token <SYMBOL>]"
path=""; token=""
while [[ $# -gt 0 ]]; do
  case "$1" in --path) path="$2"; shift 2 ;; --token) token="$2"; shift 2 ;; *) die "unknown argument $1" ;; esac
done

jq -r '.[] | [.name, .color, .description] | @tsv' "$templates/labels.json" | while IFS=$'\t' read -r name color desc; do
  label_ensure "$repo" "$name" "$color" "$desc"
  echo "label $name ok"
done

if [[ -n "$path" ]]; then
  [[ -d "$path/.git" ]] || die "$path is not a git checkout"
  mkdir -p "$path/.github/ISSUE_TEMPLATE" "$path/.beast"
  for t in decision.md workstream.md bounty.md; do
    if [[ -f "$path/.github/ISSUE_TEMPLATE/$t" ]]; then echo "template $t present"; else cp "$templates/$t" "$path/.github/ISSUE_TEMPLATE/$t"; echo "template $t written"; fi
  done
  if [[ -n "$token" ]]; then
    [[ "$token" =~ ^[A-Z0-9]{2,12}$ ]] || die "--token must be a symbol such as ACME"
    if [[ -f "$path/.beast/award-policy.md" ]]; then echo "award policy present"; else sed -e "s|<owner/repo>|$repo|" -e "s|<TOKEN>|$token|" "$templates/award-policy.md" > "$path/.beast/award-policy.md"; echo "award policy written at $path/.beast/award-policy.md (token $token)"; fi
  fi
  if [[ -f "$path/.beast/roster.json" ]]; then
    echo "roster present"
    if ids="$(roster_seat_ids "$path/.beast/roster.json" 2>&1)"; then
      while IFS= read -r s; do [[ -n "$s" ]] && seat_label_ensure "$repo" "$s" && echo "label seat:$s ok"; done <<< "$ids"
    else
      echo "seat labels NOT created: $ids — fix the roster's seats, then rerun" >&2
    fi
  else
    jq --arg r "$repo" '.repo = $r' "$templates/roster.example.json" > "$path/.beast/roster.json"
    echo "roster skeleton written at $path/.beast/roster.json — fill the seats and people, then commit"
  fi
fi
echo "done: $repo"
