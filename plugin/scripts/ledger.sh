#!/usr/bin/env bash
# ledger.sh — regenerate a community's award ledger for one month from GitHub.
#   ledger.sh --community <TOKEN> --repos <a,b,...> --month <YYYY-MM> [--out <dir>]
# Walks every issue and pull request labelled `awarded` in the repos, parses each BEAST-AWARD comment
# by shape, and keeps a row only when: the shape parses, the token equals --community, the comment was
# made in --month, and its author is an admin or maintainer of that repo (checked live). Every dropped
# comment is named on stderr with the reason; the run exits 2 when anything was dropped so a roll-up
# with silent holes cannot be published by accident. An author whose role cannot be read (a 403: the gh login
# lacks push access) stops the run, naming the repo, the login and the answer; no award is dropped for it.
# A ledger bound for a public repo lists only public repos: when --out is in a checkout of a public or
# public-intended repo (repo_public_why_at), a private repo in --repos is refused before anything is read, since its
# item urls, award reasons and logins would publish. An --out in no checkout is scratch (report.sh reads it there).
# Outputs <out>/<month>.jsonl (one row per award) and <out>/<month>.md (totals per login).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

community=""; repos=""; month=""; out="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --community) community="$2"; shift 2 ;;
    --repos) repos="$2"; shift 2 ;;
    --month) month="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$community" && -n "$repos" && -n "$month" ]] || die "usage: ledger.sh --community TOKEN --repos a,b --month YYYY-MM [--out dir]"
[[ "$month" =~ ^[0-9]{4}-[0-9]{2}$ ]] || die "month must be YYYY-MM"
mkdir -p "$out"
if root="$(checkout_root "$out" 2>/dev/null)"; then
  dest="$(repo_slug "$root")" || exit 1
  dwhy="$(repo_public_why_at "$dest" "$root")" || exit 1
  if [[ -n "$dwhy" ]]; then
    priv=""
    for r in ${repos//,/ }; do
      rwhy="$(repo_public_why_at "$r" "$root")" || exit 1
      [[ -n "$rwhy" ]] || priv="$priv $r"
    done
    [[ -z "$priv" ]] || die "refused: --out $out is in a checkout of $dest, which is $dwhy, and --repos names private repos:$priv. Their item urls, award reasons and logins would publish: a public ledger lists only public repos' awards"
  fi
fi
rows="$(mktemp)"; dropped=0
declare -a role_cache=()
role_of() { # repo login -> admin|maintain|write|read|none
  local key="$1/$2" r
  for e in "${role_cache[@]:-}"; do [[ "${e%%=*}" == "$key" ]] && { echo "${e#*=}"; return; }; done
  r="$(repo_permission "$1" "$2")" || exit 1
  role_cache+=("$key=$r"); echo "$r"
}

for repo in ${repos//,/ }; do
  # One list: the issues endpoint returns issues and pull requests alike.
  items="$(issues_list "$repo" -f labels=awarded -f state=all)" || die "cannot list the awarded items of $repo (403 = repo not attached to this session or no access)"
  for n in $(jq -r '.[].number' <<< "$items"); do
    item_url="$(jq -r --argjson n "$n" '.[] | select(.number == $n) | .html_url' <<< "$items")"
    issue_comments "$repo" "$n" \
    | jq -c --arg u "$item_url" --argjson n "$n" '.[] | select(.body | startswith("BEAST-AWARD ")) | {number: $n, url: $u, author: .user.login, at: .created_at, body}' \
    | while IFS= read -r c; do
      body="$(jq -r .body <<< "$c")"; author="$(jq -r .author <<< "$c")"; at="$(jq -r .at <<< "$c")"; url="$(jq -r .url <<< "$c")"
      if [[ ! "$body" =~ ^BEAST-AWARD\ amount=([0-9]+)\ token=([A-Z0-9]+)\ to=@([A-Za-z0-9-]+)\ for=\"([^\"]*)\"(\ ref=([^[:space:]]+))?[[:space:]]*$ ]]; then
        echo "DROPPED $url: malformed BEAST-AWARD comment by $author at $at" >&2; echo drop >> "$rows.d"; continue
      fi
      amount="${BASH_REMATCH[1]}"; token="${BASH_REMATCH[2]}"; to="${BASH_REMATCH[3]}"; what="${BASH_REMATCH[4]}"; link="${BASH_REMATCH[6]:-}"
      [[ "${at:0:7}" == "$month" ]] || continue
      if [[ "$token" != "$community" ]]; then echo "DROPPED $url: token $token is not $community" >&2; echo drop >> "$rows.d"; continue; fi
      role="$(role_of "$repo" "$author")" || exit 1   # an unread role stops the run (repo_permission named it)
      case "$role" in admin|maintain) ;; *) echo "DROPPED $url: author $author has role '$role' on $repo (admin or maintain required)" >&2; echo drop >> "$rows.d"; continue ;; esac
      jq -nc --arg repo "$repo" --arg url "$url" --arg to "$to" --arg token "$token" --argjson amount "$amount" --arg what "$what" --arg ref "$link" --arg by "$author" --arg at "$at" \
        '{repo:$repo, item:$url, to:$to, token:$token, amount:$amount, for:$what, ref:$ref, by:$by, at:$at}' >> "$rows"
    done
  done
done
[[ -f "$rows.d" ]] && dropped=$(wc -l < "$rows.d" | tr -d ' ')

sort -t'"' -k1 "$rows" 2>/dev/null | jq -c . > "$out/$month.jsonl" || : > "$out/$month.jsonl"
n="$(wc -l < "$out/$month.jsonl" | tr -d ' ')"
{
  echo "# Awards — $community — $month"
  echo
  echo "Generated $(utc_now) by daita-beast ledger.sh from GitHub (repos: $repos). $n award(s); $dropped comment(s) dropped (named in the run's stderr). Do not edit: award with award.sh and regenerate."
  echo
  echo "| Login | $community | Awards |"; echo "|---|---|---|"
  jq -rs 'group_by(.to) | map({to: .[0].to, total: (map(.amount)|add), n: length}) | sort_by(-.total) | .[] | "| @\(.to) | \(.total) | \(.n) |"' "$out/$month.jsonl"
  echo
  echo "| At | To | Amount | For | By | Item |"; echo "|---|---|---|---|---|---|"
  jq -r '"| \(.at[:10]) | @\(.to) | \(.amount) \(.token) | \(.for) | @\(.by) | \(.item) |"' "$out/$month.jsonl"
} > "$out/$month.md"
rm -f "$rows" "$rows.d"
echo "wrote $out/$month.jsonl ($n rows) and $out/$month.md; dropped $dropped"
[[ "$dropped" -eq 0 ]] || exit 2
