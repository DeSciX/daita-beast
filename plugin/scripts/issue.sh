#!/usr/bin/env bash
# issue.sh — file a plain issue (a bug, a defect, a follow-up: not a decision row, not a desk ask) after a duplicate check.
#   issue.sh new --repo <owner/repo> --title "<title>" --body-file <f> [--label <name>]... [--force]
# The duplicate check runs inside the same act as the create, so a seat never chains a search and a create by hand:
#   1. it LISTS the repo's open issues (issues_list, lib.sh: the list API, never search, whose index lags a create by
#      seconds to minutes and once hid a duplicate filed minutes earlier);
#   2. it compares each open issue's title with --title (title_dupes): both normalised (lower case; every run of
#      characters other than a-z and 0-9 is one space; trimmed). A candidate is an exact match of the normalised titles,
#      or a high token overlap: of the content tokens (3+ characters, not a stop word) at least TITLE_DUP_MIN_SHARED
#      (4) are shared AND the shared count is at least TITLE_DUP_MIN_OVERLAP (0.5) of the smaller title's tokens (the
#      overlap coefficient). Measured 2026-10-22 on the two duplicates seats filed within an hour: 7 shared tokens at
#      0.54, and 12 at 0.80; two unrelated Beast titles sharing 3 words at 0.50 are not candidates;
#   3. it prints every candidate ("#N <reason>: <title> <url>") and refuses, filing nothing, unless --force: the seat
#      reads them and comments on the one it duplicates, or reruns with --force when its issue is a different one.
# Refused before anything is written: a public or public-intended repo (coord_write_guard, lib.sh: a seat files its
# issues in a private repo; a public repo receives only publishes), a title or body that points elsewhere for its
# substance (ask_inline_check, lib.sh ASK_INLINE_RULE), and a coordination label (decision, desk, needs-review, workstream,
# …, seat:…, ws:…: those rows have their own writers: decision.sh new, desk.sh, pr.sh request, workstream.sh).
# Prints the new issue's URL, and returns once the issues list shows it, so a rerun's duplicate check finds it.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq python3

TITLE_DUP_MIN_SHARED=4; TITLE_DUP_MIN_OVERLAP=0.5

# title_dupes "<title>" <issues-json>: one line per open issue whose title is a duplicate candidate,
# "<number>\t<reason>\t<title>\t<url>" (reason: "same title" or "<shared> shared words, overlap <x>").
title_dupes() {
  jq -c '[.[] | select(.pull_request == null and .state == "open") | {number, title, html_url}]' <<< "$2" \
  | python3 -I -c '
import json, re, sys
title, shared_min, overlap_min = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
STOP = set("the and for are was were with from into onto over under that this these those its not but nor yet "
           "when while then than which who whom what where why how all any each every one two per via has have had "
           "does did done can will would should could may might must shall".split())
def norm(t): return re.sub(r"[^a-z0-9]+", " ", t.lower()).strip()
def toks(t): return {w for w in norm(t).split() if len(w) >= 3 and w not in STOP}
mine, mt = norm(title), toks(title)
for it in json.load(sys.stdin):
    t = it["title"] or ""
    if norm(t) == mine:
        why = "same title"
    else:
        ot = toks(t); sh = len(mt & ot)
        if not mt or not ot: continue
        ov = sh / min(len(mt), len(ot))
        if sh < shared_min or ov < overlap_min: continue
        why = "%d shared words, overlap %.2f" % (sh, ov)
    print("%s\t%s\t%s\t%s" % (it["number"], why, t.replace("\t", " "), it["html_url"]))
' "$1" "$TITLE_DUP_MIN_SHARED" "$TITLE_DUP_MIN_OVERLAP"
}

usage='usage: issue.sh new --repo <owner/repo> --title "<title>" --body-file <f> [--label <name>]... [--force]'
cmd="${1:-}"; shift || true
case "$cmd" in
  new)
    repo=""; title=""; bf=""; labels=(); force=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo) repo="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --body-file) bf="$2"; shift 2 ;;
        --label) labels+=("$2"); shift 2 ;;
        --force) force=1; shift ;;
        *) die "unknown argument $1; $usage" ;;
      esac
    done
    [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && -n "${title//[[:space:]]/}" && -n "$bf" ]] || die "$usage"
    [[ "$title" != *$'\n'* ]] || die "--title is one line"
    [[ -f "$bf" ]] || die "no body file $bf"
    [[ -n "$(tr -d '[:space:]' < "$bf")" ]] || die "the body file $bf is empty: an issue carries its substance"
    for l in "${labels[@]:-}"; do
      [[ -n "$l" ]] || continue
      ! label_is_coordination "$l" || die "refused: '$l' is a coordination label; issue.sh files plain issues. A decision row is decision.sh new, a desk ask desk.sh ask, a review request pr.sh request, a workstream workstream.sh new"
    done
    ask_inline_check "issue.sh new '$title'" "$title
$(cat "$bf")"
    coord_write_guard "$repo"
    open_="$(issues_list "$repo" -f state=open)" || die "cannot list the open issues of $repo (named above): nothing was filed"
    dupes="$(title_dupes "$title" "$open_")" || die "the duplicate check failed (named above): nothing was filed"
    if [[ -n "$dupes" ]]; then
      echo "open issues in $repo whose titles match \"$title\":" >&2
      while IFS=$'\t' read -r dn dwhy dt du; do echo "  #$dn ($dwhy): $dt $du" >&2; done <<< "$dupes"
      if [[ $force -eq 0 ]]; then
        die "refused: $(grep -c . <<< "$dupes") open issue(s) in $repo match the title (listed above); nothing was filed. Comment on the one it duplicates, or rerun with --force when yours is a different issue"
      fi
      echo "--force: filing it anyway" >&2
    fi
    largs=(); for l in "${labels[@]:-}"; do [[ -z "$l" ]] || largs+=(--label "$l"); done
    url="$(issue_create "$repo" --title "$title" --body-file "$bf" ${largs[@]+"${largs[@]}"})" || die "cannot create the issue in $repo (named above)"
    echo "$url"
    issues_list_shows "$repo" "${url##*/}" -f state=open
    ;;
  -h|--help|help) sed -n '2,/^source /p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; echo; echo "A title and body carry: $ASK_INLINE_RULE."; exit 0 ;;
  *) die "$usage" ;;
esac
