#!/usr/bin/env bash
# bounty.sh — open a bounty: an issue labelled `bounty` whose ## Bounty section states the floor.
#   bounty.sh --repo <owner/repo> --title "<what>" --amount <int> --token <TOKEN> --what "<the work and what accepted means>" [--project <owner>/<number>]
# Requires the checkout's filled .beast/award-policy.md for that repo (the bounty text cites it).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

repo=""; title=""; amount=""; token=""; what=""; projects=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    --amount) amount="$2"; shift 2 ;;
    --token) token="$2"; shift 2 ;;
    --what) what="$2"; shift 2 ;;
    --project) projects+=("$2"); shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$repo" && -n "$title" && -n "$amount" && -n "$token" && -n "$what" ]] || die "usage: bounty.sh --repo r --title t --amount N --token TOKEN --what \"…\""
[[ "$amount" =~ ^[0-9]+$ ]] || die "amount must be a whole number of tokens"
[[ "$token" =~ ^[A-Z0-9]{2,12}$ ]] || die "token must be a symbol such as ACME"
award_policy_token "$repo" "$token" >/dev/null
me="$(user_login)"
label_ensure_template "$repo" bounty
[[ "$title" == Bounty:* ]] || title="Bounty: $title"
tmp="$(mktemp)"
cat > "$tmp" <<EOF
## Bounty
$amount $token for the accepted submission; effort awards at the owner's discretion (see .beast/award-policy.md).

## What
$what

## How to submit
Open a pull request that references this issue (\`Closes #<n>\` or \`Bounty #<n>\`). One submission per PR.

## Decides
@$me
EOF
url="$(issue_create "$repo" --title "$title" --label bounty --body-file "$tmp")"
rm -f "$tmp"
echo "$url"
for p in "${projects[@]:-}"; do
  [[ -n "$p" ]] || continue
  project_cmd item-add "${p##*/}" --owner "${p%%/*}" --url "$url" >/dev/null && echo "added to project $p"
done
