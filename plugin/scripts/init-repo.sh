#!/usr/bin/env bash
# init-repo.sh — make a repo a Beast coordinating repo: labels, issue templates, roster skeleton.
#   init-repo.sh <owner/repo> [--path <local checkout>] [--token <SYMBOL> --community <owner/repo>]
# Idempotent: labels are created or updated in place; files are written only when absent. The award
# policy is written only with --token (the community token) and --community (the repo that holds the token's
# community and its .beast/awarders.json), filled; no file ever carries a placeholder.
# A public or public-intended repo (repo_public_why_at: the checkout's roster when it has one, then GitHub) gets the
# public set only (labels_public: bounty, awarded; the bounty template; the award policy): every coordination label,
# template and the roster are refused on stderr, and a coordination label it already carries is named and exits 1.
# Nothing is deleted.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq
here="$(dirname "${BASH_SOURCE[0]}")"; templates="$here/../templates"

repo="${1:-}"; shift || true
[[ -n "$repo" ]] || die "usage: init-repo.sh <owner/repo> [--path <dir>] [--token <SYMBOL> --community <owner/repo>]"
path=""; token=""; community=""
while [[ $# -gt 0 ]]; do
  case "$1" in --path) path="$2"; shift 2 ;; --token) token="$2"; shift 2 ;; --community) community="$2"; shift 2 ;; *) die "unknown argument $1" ;; esac
done
[[ -z "$token" && -z "$community" ]] || [[ -n "$token" && -n "$community" ]] || die "--token and --community go together: the award policy names the token and the community repo that holds its .beast/awarders.json"
[[ -z "$community" || "$community" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--community '$community' is not owner/repo"
[[ -z "$path" ]] || checkout_require_root "$path"   # a plain checkout or a submodule's (its .git is a file): lib.sh is the one owner of the test

why="$(repo_public_why_at "$repo" "${path:-.}")" || exit 1
if [[ -n "$why" ]]; then
  names="$(labels_public)"
  echo "refused: $repo is $why. A public repo carries only the public labels ($(paste -sd, - <<< "$names")); the coordination labels ($(labels_coordination | paste -sd, -)), every seat:* and ws:* label, the decision and workstream templates and the roster live only in its private twin" >&2
else
  names="$(jq -r '.[].name' "$templates/labels.json")"
fi
while IFS= read -r name; do
  label_ensure_template "$repo" "$name"
  echo "label $name ok"
done <<< "$names"

if [[ -n "$path" ]]; then
  mkdir -p "$path/.github/ISSUE_TEMPLATE"
  # A label's issue template is templates/<label>.md when there is one, so the label set decides the templates too.
  while IFS= read -r name; do
    t="$name.md"; [[ -f "$templates/$t" ]] || continue
    if [[ -f "$path/.github/ISSUE_TEMPLATE/$t" ]]; then echo "template $t present"; else cp "$templates/$t" "$path/.github/ISSUE_TEMPLATE/$t"; echo "template $t written"; fi
  done <<< "$names"
  if [[ -n "$token" ]]; then
    [[ "$token" =~ ^[A-Z0-9]{2,12}$ ]] || die "--token must be a symbol such as ACME"
    mkdir -p "$path/.beast"
    if [[ -f "$path/.beast/award-policy.md" ]]; then echo "award policy present"; else sed -e "s|<owner/repo>|$repo|" -e "s|<TOKEN>|$token|g" -e "s|<COMMUNITY>|$community|" "$templates/award-policy.md" > "$path/.beast/award-policy.md"; echo "award policy written at $path/.beast/award-policy.md (token $token, community $community: it awards only once $community lists $repo in its .beast/awarders.json)"; fi
  fi
  if [[ -n "$why" ]]; then
    echo "refused: no roster and no seat labels in $repo ($why)" >&2
  elif [[ -f "$path/.beast/roster.json" ]]; then
    echo "roster present"
    if ids="$(roster_seat_ids "$path/.beast/roster.json" 2>&1)"; then
      while IFS= read -r s; do [[ -n "$s" ]] && seat_label_ensure "$repo" "$s" && echo "label seat:$s ok"; done <<< "$ids"
    else
      echo "seat labels NOT created: $ids — fix the roster's seats, then rerun" >&2
    fi
  else
    mkdir -p "$path/.beast"
    jq --arg r "$repo" '.repo = $r' "$templates/roster.example.json" > "$path/.beast/roster.json"
    echo "roster skeleton written at $path/.beast/roster.json — fill the seats and people, then commit"
  fi
fi

if [[ -n "$why" ]]; then
  stale="$(repo_labels "$repo" | while IFS= read -r l; do ! label_is_coordination "$l" || echo "$l"; done)" || die "cannot list the labels of $repo"
  if [[ -n "$stale" ]]; then
    echo "refused: $repo ($why) carries coordination labels: $(paste -sd, - <<< "$stale"). init-repo deletes nothing; the repo's owner removes each (gh label delete <name> -R $repo) after moving any row that carries it to the private twin" >&2
    exit 1
  fi
fi
echo "done: $repo"
