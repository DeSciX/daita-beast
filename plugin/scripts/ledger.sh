#!/usr/bin/env bash
# ledger.sh — regenerate a community's award ledger for one month from GitHub.
#   ledger.sh --community <TOKEN> --repos <a,b,...> --month <YYYY-MM> [--out <dir>]
#             [--sheet <out.csv> --emails <map.csv> [--batch <name>]]
# Walks every issue and pull request labelled `awarded` in the repos, parses each BEAST-AWARD comment
# by shape, and keeps a row only when: the shape parses, the token equals --community, the comment was
# made in --month, and its author is an admin or maintainer of that repo (checked live). Every dropped
# comment is named on stderr with the reason; the run exits 2 when anything was dropped so a roll-up
# with silent holes cannot be published by accident. An author whose role cannot be read (a 403: the gh login
# lacks push access) stops the run, naming the repo, the login and the answer; no award is dropped for it.
# A ledger bound for a public repo lists only public repos: when --out is in a checkout of a public or
# public-intended repo (repo_public_why_at), a private repo in --repos is refused before anything is read, since its
# item urls, award reasons and logins would publish; and that public repo is the token's community repo, so every repo in
# --repos must be listed in its .beast/awarders.json for the token (award_authority_check), else the run is refused before
# anything is read. An --out in no checkout is scratch (report.sh reads it there).
# Each row's ref is the award's ref= or, when the comment has none, the awarded item's URL: no row has an empty ref. A
# ref= present but empty or not an https URL (AWARD_REF_RE) stops the run with exit 1 before any file is written.
# Outputs <out>/<month>.jsonl (one row per award) and <out>/<month>.md (totals per login).
# --sheet writes the same rows as the CSV the DeSciX platform's Offers import reads: header
# `contactemail,token,new_amount,batch,wallet_address`, one row per award, new_amount the award's plain decimal, batch
# `awards-<month>` unless --batch, wallet_address always blank (the wallet binds when the offer is accepted in Powch);
# RFC 4180 quoting, LF line ends. The login->email map is the platform's data, a file the caller owns (--emails): a CSV
# with the header `login,email` and one `<login>,<email>` per line, no quoting. A malformed map (no such header, a bad
# line, a malformed email, a login listed twice, no mapping at all) dies; an awarded login the map lacks refuses the
# whole run, naming every unmapped login, before any file is written. The sheet carries email addresses, so its path
# must be outside every git checkout, ignored or not: a path inside one is refused before anything is read.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

community=""; repos=""; month=""; out="."; sheet=""; emails=""; batch=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --community) community="$2"; shift 2 ;;
    --repos) repos="$2"; shift 2 ;;
    --month) month="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --sheet) sheet="$2"; shift 2 ;;
    --emails) emails="$2"; shift 2 ;;
    --batch) batch="$2"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$community" && -n "$repos" && -n "$month" ]] || die "usage: ledger.sh --community TOKEN --repos a,b --month YYYY-MM [--out dir] [--sheet out.csv --emails map.csv [--batch name]]"
[[ "$month" =~ ^[0-9]{4}-[0-9]{2}$ ]] || die "month must be YYYY-MM"

# email_map_read <file>: the login->email map as one JSON object, keys the logins lowercased (GitHub compares logins
# case-insensitively). Dies naming the file and the line for anything but the documented shape.
email_map_read() {
  local f="$1" n=0 line login email seen="" rows=0 acc
  [[ -f "$f" && -r "$f" ]] || die "--emails $f: no such readable file (a CSV: header login,email, then <login>,<email> per line)"
  acc="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n+1)); line="${line%$'\r'}"
    if [[ $n -eq 1 ]]; then
      line="${line#$'\xef\xbb\xbf'}"
      [[ "$(tr '[:upper:]' '[:lower:]' <<< "$line")" == "login,email" ]] || { rm -f "$acc"; die "--emails $f: line 1 must be the header login,email, got '$line'"; }
      continue
    fi
    [[ -n "$line" ]] || continue
    [[ "$line" =~ ^([^,]*),([^,]*)$ ]] || { rm -f "$acc"; die "--emails $f line $n: not <login>,<email> (exactly one comma, no quoting): '$line'"; }
    login="${BASH_REMATCH[1]}"; email="${BASH_REMATCH[2]}"
    [[ "$login" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || { rm -f "$acc"; die "--emails $f line $n: '$login' is not a GitHub login (no @, no spaces)"; }
    [[ "$email" =~ $SHEET_EMAIL_RE ]] || { rm -f "$acc"; die "--emails $f line $n: '$email' is not an email address"; }
    login="$(tr '[:upper:]' '[:lower:]' <<< "$login")"
    [[ " $seen " != *" $login "* ]] || { rm -f "$acc"; die "--emails $f line $n: login $login is listed twice (logins compare case-insensitively)"; }
    seen="$seen $login"; rows=$((rows+1))
    jq -nc --arg l "$login" --arg e "$email" '{($l): $e}' >> "$acc"
  done < "$f"
  [[ $rows -gt 0 ]] || { rm -f "$acc"; die "--emails $f maps no login: it has the header and no <login>,<email> line"; }
  jq -sc 'add' "$acc"; rm -f "$acc"
}
SHEET_EMAIL_RE='^[A-Za-z0-9.!#$%&*+/=?^_{|}~-]+@[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'

emap=""
if [[ -n "$sheet$emails$batch" ]]; then
  [[ -n "$sheet" && -n "$emails" ]] || die "--sheet and --emails go together (--batch only with them)"
  batch="${batch:-awards-$month}"
  [[ "$batch" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || die "--batch '$batch' is not a batch name (letters, digits, . _ -; at most 64)"
  [[ ! -d "$sheet" ]] || die "--sheet $sheet is a directory; name the CSV file to write"
  [[ ! -L "$sheet" ]] || die "--sheet $sheet is a symbolic link; name a plain file path"
  sdir="$(cd "$(dirname "$sheet")" 2>/dev/null && pwd -P)" || die "--sheet $sheet: its directory does not exist"
  if sroot="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$sdir" rev-parse --show-toplevel 2>/dev/null)"; then
    die "refused: --sheet $sheet is inside the git checkout $sroot. The sheet carries email addresses: write it outside every git checkout (ignored or not), e.g. a scratch directory"
  fi
  emap="$(email_map_read "$emails")" || exit 1
fi
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
    for r in ${repos//,/ }; do award_authority_check "$r" "$community" "$dest"; done
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
      if [[ ! "$body" =~ ^BEAST-AWARD\ amount=([0-9.]+)\ token=([A-Z0-9]+)\ to=@([A-Za-z0-9-]+)\ for=\"([^\"]*)\"(\ ref=([^[:space:]]*))?[[:space:]]*$ ]]; then
        echo "DROPPED $url: malformed BEAST-AWARD comment by $author at $at" >&2; echo drop >> "$rows.d"; continue
      fi
      amount="${BASH_REMATCH[1]}"; token="${BASH_REMATCH[2]}"; to="${BASH_REMATCH[3]}"; what="${BASH_REMATCH[4]}"; link="${BASH_REMATCH[6]:-}"
      # The row's ref: the award's own ref=, else the awarded item's URL; never empty. A ref= that is present but empty or
      # not AWARD_REF_RE stops the run before anything is written (the platform's Offers import refuses an empty ref).
      if [[ -n "${BASH_REMATCH[5]:-}" ]]; then
        [[ "$link" =~ $AWARD_REF_RE ]] || { rm -f "$rows" "$rows.d"; die "refused: the BEAST-AWARD comment by $author at $at on $url has ref='$link', which is not an https URL (AWARD_REF_RE); nothing written. Edit the comment to a full ref=<https url>, or remove ref= so the ledger cites the item, and rerun"; }
      else
        link="$url"
      fi
      if [[ ! "$amount" =~ $AWARD_AMOUNT_RE ]]; then echo "DROPPED $url: amount '$amount' by $author at $at is not $AWARD_AMOUNT_HINT" >&2; echo drop >> "$rows.d"; continue; fi
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

sort -t'"' -k1 "$rows" 2>/dev/null | jq -c . > "$rows.s" || : > "$rows.s"
if [[ -n "$sheet" ]]; then
  # The sheet is rendered from the same rows as the .jsonl. Every check runs before any file is written.
  unmapped="$(jq -rs --argjson m "$emap" '[.[].to | ascii_downcase | select($m[.] == null)] | unique | map("@" + .) | join(" ")' "$rows.s")" || die "cannot read the award rows"
  [[ -z "$unmapped" ]] || { rm -f "$rows" "$rows.d" "$rows.s"; die "refused: --emails $emails maps no email for the awarded login(s) $unmapped; nothing written. Add a <login>,<email> line for each (the mapping is the platform's data) and rerun"; }
  jq -rs --argjson m "$emap" --arg b "$batch" --arg re "$AWARD_AMOUNT_RE" '
    def field: tostring | if test("[\",\r\n]") then "\"" + gsub("\""; "\"\"") + "\"" else . end;
    "contactemail,token,new_amount,batch,wallet_address",
    (.[] | (.amount | tostring) as $a
      | if ($a | test($re)) then . else error("amount \($a) of the award \(.item) is not a plain decimal") end
      | [$m[.to | ascii_downcase], .token, $a, $b, ""] | map(field) | join(","))' "$rows.s" > "$rows.csv" \
    || { rm -f "$rows" "$rows.d" "$rows.s" "$rows.csv"; die "cannot render the sheet (named above); nothing written"; }
fi
cat "$rows.s" > "$out/$month.jsonl"; rm -f "$rows.s"
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
if [[ -n "$sheet" ]]; then mv "$rows.csv" "$sheet"; echo "wrote $sheet ($n rows, batch $batch)"; fi
rm -f "$rows" "$rows.d"
echo "wrote $out/$month.jsonl ($n rows) and $out/$month.md; dropped $dropped"
[[ "$dropped" -eq 0 ]] || exit 2
