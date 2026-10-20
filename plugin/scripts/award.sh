#!/usr/bin/env bash
# award.sh — record an award on a pull request or issue, as the owner's own comment.
#   award.sh <owner/repo#N | url> --amount <int> --token <TOKEN> --to <login> --for "<what>" [--ref <url>]
# Writes ONE comment of the fixed shape the ledger parses, and adds the label `awarded`:
#   BEAST-AWARD amount=<n> token=<TOKEN> to=@<login> for="accepted logo (PR #12)" ref=<url>
# Refuses unless the checkout carries a filled .beast/award-policy.md for that repo whose token is the one awarded,
# unless the policy's community repo lists the repo in its .beast/awarders.json (award_authority_check: the community
# decides which repos may award its token), and unless the caller is an admin or maintainer of that repo (GitHub roles
# gate who may award).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

ref="${1:-}"; shift || true
amount=""; token=""; to=""; what=""; link=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --amount) amount="$2"; shift 2 ;;
    --token) token="$2"; shift 2 ;;
    --to) to="$2"; shift 2 ;;
    --for) what="$2"; shift 2 ;;
    --ref) link="$2"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$ref" && -n "$amount" && -n "$token" && -n "$to" && -n "$what" ]] || die "usage: award.sh <issue|pr> --amount N --token TOKEN --to login --for \"what\" [--ref url]"
[[ "$amount" =~ ^[0-9]+$ ]] || die "amount must be a whole number of tokens"
[[ "$token" =~ ^[A-Z0-9]{2,12}$ ]] || die "token must be a symbol such as ACME"
to="${to#@}"
[[ "$what" != *'"'* ]] || die "--for may not contain double quotes"
read -r repo number < <(parse_issue_ref "$ref")
policy="$(award_policy "$repo" "$token")" || exit 1
award_authority_check "$repo" "$token" "${policy#* }"

me="$(user_login)"
role="$(repo_permission "$repo" "$me")"
case "$role" in admin|maintain) ;; *) die "refused: $me has role '$role' on $repo; only admin or maintain may award" ;; esac

user_exists "$to" || die "recipient '$to' is not a GitHub login"
label_ensure_template "$repo" awarded

line="BEAST-AWARD amount=$amount token=$token to=@$to for=\"$what\""
[[ -n "$link" ]] && line="$line ref=$link"
url="$(issue_comment "$repo" "$number" "$line")"
issue_add_labels "$repo" "$number" awarded
echo "$url"
