#!/usr/bin/env bash
# publish.sh — publish chosen changes of a private twin to its public repo (the roster's "publishes_to"),
# through a pull request on the public repo approved on a row in the twin. Run in a checkout of the twin.
# --seat / --by name the acting seat by LABEL, login/LABEL or identity, resolved through the workstream tables
# (seat_id): a twin whose roster has no seat rows is worked by a seat rostered in its own home repo.
# "Twin main" is the twin's default branch on GitHub; "public main" the public repo's.
# This script is the ONLY writer to a public repo: its pushes go through public_push and its API writes through
# public_send, both below, both refusing any repo but the roster's publishes_to. public_push never forces, except the one
# sanctioned force-push (request --amend), leased on the PR's head. coord_write_guard (lib.sh) still
# refuses every coordination write (rows, desks, status, notes, acks, review requests, the board) to that repo.
#
#   publish.sh prepare <slug> [--paths <path>... | --commits <sha>...] [--delete <path>]... --message-file <f>
#       cuts publish/<slug> from the public repo's default branch (fetched into the remote `public`, added when
#       absent) and makes ONE new commit on it, its message the file (written for outside readers): --paths takes
#       each path as it is in the public view of twin main (publish_view: a path gone from it is deleted); --commits
#       applies each commit's own change in topological order (oldest first), squashed. Never the twin's history. When
#       the public repo is empty, the branch is an orphan: an empty "Initial commit" root, then the publish commit (request pushes the
#       root as main). The scrub gate runs on the commit before the branch is created: on any hit nothing is created.
#       The overlay: a file .publish/<p> of twin main publishes as <p>, replacing the twin's own <p>; the twin's
#       root CLAUDE.md never publishes (a public CLAUDE.md is .publish/CLAUDE.md). --paths .publish/<p> and --paths <p>
#       name the same public path. --commits refuses a commit that touches the root CLAUDE.md, .publish/ or a path
#       the overlay shadows: publish those with --paths.
#       --delete <path> (repeatable) removes a path from the public repo while the twin keeps its own copy (a twin-only
#       file, such as a coordination pointer). It is refused when the path overlaps a --paths item or is shadowed by a
#       .publish/ overlay file (one source of truth per path), and when the path is not on public main (nothing to
#       delete). The commit message gains a paragraph "Removed from this repository:" listing them, for the PR body.
#   publish.sh prepare <slug> --amend [--paths <path>... | --commits <sha>...] [--delete <path>]... --message-file <f>
#       rebuilds publish/<slug> for a publish already requested (its row open): the same ONE commit, cut from the public
#       default branch as it is now, with the license and scrub gates rerun. Refused when the slug was never requested
#       (no row of its title), when its row is closed, and when nothing changes.
#   publish.sh scrub <slug> [--body-file <f>]
#       the scrub gate (below) on the branch's one commit: its diff and its message (and the body file). A branch that is
#       not exactly one commit on its public base (prepare's shape; for an empty public repo the empty root plus one
#       commit) is refused, naming its commit count, here and in request and merge (publish_base owns the shape).
#   publish.sh request <slug> --seat <SEAT> --body-file <f> [--milestone "<title>"]
#       re-scrubs (branch and body), pushes the branch to the public repo, opens the PR there with the body (an
#       outside-reader description), and files the approval row in the twin (decision.sh new, home repo,
#       --decides <public>, approved with "publish <slug>", under --milestone, which is required when the twin has an
#       open milestone and is checked before anything is pushed). Nothing else is written on the public repo.
#   publish.sh request <slug> --amend --seat <SEAT> [--body-file <f>]
#       after prepare --amend: re-gates, force-pushes publish/<slug> with --force-with-lease on the open PR's head (the one
#       sanctioned force-push), retitles the PR (and replaces its body when given), then posts ONE line on the twin row:
#       "Amended at <UTC>: <n> files; added <list>; removed <list>; changed <list>" (amend_line, lib.sh; lists cut after 8).
#       An approval older than the row's latest amend line no longer counts (row_answer_url, lib.sh).
#   publish.sh merge <slug> --words "<verbatim>" --by <SEAT> [--record <comment url | commit — path>]
#       on "publish <slug>" (or bare approve, or "<phrase> — <comment>"): re-scrubs, squash-merges the PR, deletes the
#       public branch, records public main as merged into twin main (a merge commit with twin main's own tree, so a
#       later pull brings only outside changes), closes the row on the words. On "reject: …": closes the PR unmerged,
#       deletes the branch, closes the row rejected. --record defaults to the decider's answer comment on the row; on an
#       amended row an approval is only the decider's comment newer than the latest amend line (--record is refused).
#       An approval is refused while the decider's revise: on the row has no amend line after it (row_revise_pending):
#       request --amend's line, or decision.sh revise, answers it.
#   publish.sh pull
#       merges the public default branch into twin main (outside contributions), in the twin's main checkout on
#       main with a clean tree; on a conflict it aborts the merge and names the conflicted files.
#   publish.sh release <tag> --title "<title>" --notes-file <f> [--check]
#       scrubs the title and the notes (written for outside readers) and creates a GitHub Release <tag> on the public repo
#       at its default branch, the notes its body; --check scrubs and writes nothing. An existing release of that tag with the same title and body is reused
#       (a rerun); one that differs dies naming it. wrapup.sh run publishes a milestone's release notes through it.
#   publish.sh scan [--roster <file>] [--patterns-file <f>] (--base <ref> | --tree <dir>) [--paths <path>...]
#   publish.sh scan [--roster <file>] --dump-patterns
#       the stable contract for other tools (lib.sh's functions are internal): the scrub gate's classes, through the same
#       scrub_patterns and scrub_scan, on the diff <ref>..HEAD of the repo you stand in (and those commits' messages) or on
#       every file of a directory, optionally only under --paths. Needs no twin checkout. One line per hit on stdout:
#       "<file>:<line> <class> <match>" ("<path>:0 path-name <match>" for a path, "commit-message <class> <match>" for a
#       message); exit 1 on any hit, 0 when clean, 2 on a usage or pattern error. --dump-patterns prints the pattern bag
#       (the JSON scrub_patterns builds, from --roster or the repo's own roster); --patterns-file reads one, so a scan runs
#       with no network.
#
# The license gate: when the roster names a "license", prepare and request refuse a publish whose public tree does not
# carry it (license.sh check, the one owner of license checks, on the publish commit).
# The scrub gate (scrub_patterns + scrub_scan in lib.sh, the one owner of what may not leave the twin; the roster's
# "scrub", "scrub_allow" and "scrub_allow_words" are parsed by roster_scrub, its "vendored" by roster_vendored, lib.sh). The content classes read the added lines of each TEXT file; a
# binary file (a NUL byte in its first 8000 bytes, git's test) is not read and is named on stderr. A hit is any of:
#   private repo   an owner/repo slug (a URL included) of a private repo, any case: every repo the roster names that is
#                  private, and every private repo of every owner the roster names (repo, publishes_to, board, seat
#                  repos, tracking refs), listed in full; a listing that fails dies. The public target and exact
#                  public_intended entries excepted
#   private name   the bare name of each of those private repos as a whole word, in its exact case (a codename, an
#                  ecosystem index's paths); names shorter than 5 characters and the roster's scrub_allow are not
#                  checked bare (their slug form still is)
#   local path     /Users/<name>/ or /home/<name>/ (a checkout path on a machine)
#   BEAST- line    a filled-in coordination line: one starting BEAST-<WORD> with no <placeholder> or $variable
#   record path    a records/ directory under org/ or docs/ (the dated records; RECORD_PATH_RE, lib.sh)
#   words          a stretch of 5 consecutive words with at least 2 outside the common-word list (WORDS_*, lib.sh), case,
#                  whitespace and punctuation folded, of the words on a closed row of the twin (the close comment's verbatim
#                  words, decision rows and PR rows), except a close on the row's own approving phrase. The roster's
#                  scrub_allow_words: a phrase of 5 words or more drops every stretch inside it; a shorter phrase adds its
#                  words to the common-word list (they no longer count toward the 2), and nothing else
#   roster scrub   a regex of the roster's "scrub" list: a string on every text file, message and body; a
#                  {"pattern", "paths"} entry only on text files whose path matches one of its globs
#   vendored       under a directory of the roster's top-level "vendored" (byte-exact upstream copies; roster_vendored,
#                  lib.sh) the private repo, private name, words and roster scrub classes are not applied to file content;
#                  local path, BEAST- line, record path and path name still are
#   path name      every added or changed path: a secret-shaped file name (wallet.json, .env, .env.*, *.pem, *.key,
#                  id_rsa*, id_ed25519*, *.p12, *.pfx, keystore*.json, credentials*.json), and the private repo,
#                  private name and roster scrub classes applied to the path itself
# Each hit is printed as <file>:<line>, "<path>: path name", "commit <sha> message:<line>" or "body:<line>", with its
# class; exit 1.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---- scan: the stable offline contract (no twin checkout needed; no network with --patterns-file) --------------
if [[ "${1:-}" == scan ]]; then
  shift
  scan_usage() {
    echo "daita-beast: publish.sh scan: $*" >&2
    echo "usage: publish.sh scan [--roster <file>] [--patterns-file <f>] (--base <ref> | --tree <dir>) [--paths <path>...]" >&2
    echo "       publish.sh scan [--roster <file>] --dump-patterns" >&2
    exit 2
  }
  command -v jq >/dev/null && command -v git >/dev/null && command -v python3 >/dev/null || scan_usage "needs jq, git and python3"
  s_roster=""; s_pat=""; s_base=""; s_tree=""; s_dump=0; s_paths=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --roster) [[ -n "${2:-}" ]] || scan_usage "--roster takes a file"; s_roster="$2"; shift 2 ;;
      --patterns-file) [[ -n "${2:-}" ]] || scan_usage "--patterns-file takes a file"; s_pat="$2"; shift 2 ;;
      --base) [[ -n "${2:-}" ]] || scan_usage "--base takes a ref"; s_base="$2"; shift 2 ;;
      --tree) [[ -n "${2:-}" ]] || scan_usage "--tree takes a directory"; s_tree="$2"; shift 2 ;;
      --dump-patterns) s_dump=1; shift ;;
      --paths) shift; while [[ $# -gt 0 && "$1" != --* ]]; do s_paths+=("$1"); shift; done
        [[ ${#s_paths[@]} -gt 0 ]] || scan_usage "--paths names nothing" ;;
      *) scan_usage "unknown argument $1" ;;
    esac
  done
  [[ -z "$s_roster" || -f "$s_roster" ]] || scan_usage "no roster file $s_roster"
  if [[ $s_dump -eq 1 ]]; then
    [[ -z "$s_pat$s_base$s_tree" && ${#s_paths[@]} -eq 0 ]] || scan_usage "--dump-patterns takes only --roster"
    ( scrub_patterns "$s_roster" ) || { echo "daita-beast: publish.sh scan: cannot derive the pattern bag (named above)" >&2; exit 2; }
    exit 0
  fi
  [[ -n "$s_base" || -n "$s_tree" ]] || scan_usage "name --base <ref> or --tree <dir>"
  [[ -z "$s_base" || -z "$s_tree" ]] || scan_usage "--base and --tree exclude each other"
  [[ -z "$s_pat" || -z "$s_roster" ]] || scan_usage "--roster derives the patterns, --patterns-file reads them: name one"
  s_tmp="$(mktemp -d)"; on_exit 'rm -rf "$s_tmp"'
  if [[ -z "$s_pat" ]]; then
    s_pat="$s_tmp/patterns.json"
    ( scrub_patterns "$s_roster" ) > "$s_pat" || { echo "daita-beast: publish.sh scan: cannot derive the pattern bag (named above)" >&2; exit 2; }
  fi
  [[ -f "$s_pat" ]] || scan_usage "no patterns file $s_pat"
  s_pf=""
  if [[ ${#s_paths[@]} -gt 0 ]]; then s_pf="$s_tmp/paths"; printf '%s\n' "${s_paths[@]}" > "$s_pf"; fi
  s_rc=0
  if [[ -n "$s_tree" ]]; then
    [[ -d "$s_tree" ]] || scan_usage "no directory $s_tree"
    s_tree="$(cd "$s_tree" && pwd)"
    scrub_scan "$s_tree" "$s_pat" "" "" "" contract "$s_tree" "$s_pf" || s_rc=$?
  else
    s_root="$(git rev-parse --show-toplevel 2>/dev/null)" || scan_usage "--base reads the git repo you stand in; $PWD is not in one"
    s_b="$(git -C "$s_root" rev-parse --verify -q "$s_base^{commit}")" || scan_usage "--base $s_base is not a commit of $s_root"
    git -C "$s_root" rev-parse --verify -q "HEAD^{commit}" >/dev/null || scan_usage "$s_root has no HEAD commit"
    scrub_scan "$s_root" "$s_pat" "$s_b" HEAD "" contract "" "$s_pf" || s_rc=$?
  fi
  [[ $s_rc -le 2 ]] || s_rc=2
  exit "$s_rc"
fi

need gh jq git python3

EMPTY_TREE="$(git hash-object -t tree /dev/null)"

# ---- the twin and its public repo ----------------------------------------------------------------
root="$(repo_root)"
G() { git -C "$root" "$@"; }
TWIN="$(roster_repo)" || exit 1
[[ "$(tr 'A-Z' 'a-z' <<< "$(repo_slug "$root")")" == "$(tr 'A-Z' 'a-z' <<< "$TWIN")" ]] \
  || die "publish.sh runs in a checkout of the twin $TWIN (the roster's repo); $root is $(repo_slug "$root")"
PUB="$(roster_pair_check)" || exit 1
[[ -n "$PUB" ]] || die "the roster $(roster_path) has no \"publishes_to\": $TWIN is not the twin of a public repo"
# the twin's main line: its default branch on GitHub (the one owner of the name), present in this checkout
TWIN_MAIN="$(gh_get "repos/$TWIN" | jq -r '.default_branch // empty')" || die "cannot read the default branch of $TWIN (named above)"
[[ -n "$TWIN_MAIN" ]] || die "GitHub names no default branch for $TWIN"
G rev-parse --verify -q "refs/heads/$TWIN_MAIN" >/dev/null || die "the twin checkout $root has no branch $TWIN_MAIN (the default branch of $TWIN)"

# public_info: the public repo as GitHub serves it; dies when it does not exist under its own name (GitHub
# serves a renamed or transferred repo's old name as the new repo: measured 2026-10-16, a public repo's
# intended name, once the twin's own, answered as the private twin). Creating the public repo is its owner's act, never this script's.
public_info() {
  local info
  info="$(gh_get "repos/$PUB")" || die "the public repo $PUB cannot be read (named above): it must exist before a publish; creating it is the owner's act"
  [[ "$(jq -r .full_name <<< "$info" | tr 'A-Z' 'a-z')" == "$(tr 'A-Z' 'a-z' <<< "$PUB")" ]] \
    || die "GitHub serves $PUB as $(jq -r .full_name <<< "$info") (a rename or transfer): $PUB does not exist under its own name; create it (the owner's act) or fix the roster's publishes_to"
  printf '%s\n' "$info"
}

# public_fetch: the remote `public` names $PUB (added when absent; another URL there is refused) and is fetched.
# Prints the public default branch's name.
public_fetch() {
  local want url have db
  want="https://github.com/$PUB.git"
  if url="$(G remote get-url public 2>/dev/null)"; then
    have="$(sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' <<< "$url")"
    [[ "$(tr 'A-Z' 'a-z' <<< "$have")" == "$(tr 'A-Z' 'a-z' <<< "$PUB")" ]] || die "the remote 'public' of $root is $url, not $PUB (the roster's publishes_to): fix it with git remote set-url public $want"
  else
    G remote add public "$want" || die "cannot add the remote public ($want)"
    echo "remote public added: $want" >&2
  fi
  db="$(public_info | jq -r .default_branch)" || exit 1
  G fetch -q --prune public || die "git fetch public ($PUB) failed"
  echo "$db"
}

# public_push <src> <dst-ref> [<lease sha>]: the one git push to the public repo. Never forced, except the one sanctioned
# force-push, request --amend's: given a lease, it replaces <dst-ref> only while the public repo still has it at <lease sha>
# (--force-with-lease), so a push nobody here saw is never overwritten.
public_push() {
  local u; u="$(G remote get-url public)"
  [[ "$(sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' <<< "$u" | tr 'A-Z' 'a-z')" == "$(tr 'A-Z' 'a-z' <<< "$PUB")" ]] || die "public_push: the remote public is $u, not $PUB"
  if [[ -n "${3:-}" ]]; then
    [[ "$3" =~ ^[0-9a-f]{40}$ ]] || die "public_push: the lease '$3' is not a full sha"
    G push -q --force-with-lease="$2:$3" public "$1:$2" || die "git push --force-with-lease=$2:${3:0:12} public $1:$2 ($PUB) failed (named above): the public branch moved, or the push was refused; nothing was replaced"
  else
    G push -q public "$1:$2" || die "git push public $1:$2 ($PUB) failed"
  fi
}

# public_send <METHOD> <repos/$PUB/...> [gh field args]: the one API write to the public repo (gh_send). Any other
# repo is refused: the public writer writes only to the roster's publishes_to.
public_send() {
  local m="$1" p="$2"
  [[ "$(tr 'A-Z' 'a-z' <<< "$p")" == "repos/$(tr 'A-Z' 'a-z' <<< "$PUB")/"* ]] || die "public_send: $p is not a path of $PUB; publish.sh writes only to the roster's publishes_to"
  gh_send "$@"
}

slug_check() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9._-]{0,62}$ ]] || die "slug '${1:-}' must be lower-case letters, digits, '.', '_' or '-' (the branch is publish/<slug>)"
}

# ---- the publish overlay: the one owner of which twin file publishes at which public path ------------
OVERLAY_DIR=".publish"

# publish_path <path>: the public path a --paths argument names: ./ and a trailing / dropped, .publish/<p> read as <p>.
publish_path() {
  local p="${1#./}"; p="${p%/}"
  [[ -n "$p" ]] || p="."
  [[ "$p" != "$OVERLAY_DIR" ]] || die "--paths $OVERLAY_DIR names no public path: name the paths under it ($OVERLAY_DIR/<p> publishes as <p>)"
  [[ "$p" != "$OVERLAY_DIR/"* ]] || p="${p#"$OVERLAY_DIR"/}"
  echo "$p"
}

# publish_view <ref> <public path>: NUL-terminated `git ls-tree` entries (mode SP type SP sha TAB path) of the files of <ref>
# as they publish, under <public path> ("." for all): .publish/<p> becomes <p> and wins over the twin's own <p>; the root
# CLAUDE.md is never in the view. Feeds `git update-index -z --index-info`.
publish_view() {
  G ls-tree -r -z --full-tree "$1" | python3 -I -c '
import sys
ov, want = sys.argv[1] + "/", sys.argv[2]
own, over = {}, {}
for e in sys.stdin.buffer.read().split(b"\0"):
    if not e: continue
    meta, path = e.split(b"\t", 1); path = path.decode("utf-8", "surrogateescape")
    if path.startswith(ov): over[path[len(ov):]] = meta
    elif path != "CLAUDE.md": own[path] = meta
own.update(over)
for path in sorted(own):
    if want == "." or path == want or path.startswith(want + "/"):
        sys.stdout.buffer.write(own[path] + b"\t" + path.encode("utf-8", "surrogateescape") + b"\0")
' "$OVERLAY_DIR" "$2"
}

# index_drop <path>: removes <path> (a file, or every file under a directory) from the publish commit's temporary index
# ($GIT_INDEX_FILE) only. It never reads the twin's working tree or HEAD. `git rm --cached` would compare the entry
# with them and refuse an overlaid path such as CLAUDE.md, whose twin copy differs from its .publish/ source by design.
# Prints nothing; returns git's status.
index_drop() {
  G ls-files -z --full-name -- ":(top,literal)$1" | G update-index -z --force-remove --stdin
}

# overlay_touch <sha>: the paths a twin commit changes that publish only through the overlay rules (the root CLAUDE.md,
# anything under .publish/, a path .publish/ shadows on twin main), one per line; --commits refuses such a commit.
overlay_touch() {
  local from f
  from="$(G rev-parse -q --verify "$1^" 2>/dev/null || echo "$EMPTY_TREE")"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ "$f" == CLAUDE.md || "$f" == "$OVERLAY_DIR/"* ]] || [[ -n "$(G ls-tree --full-tree "$TWIN_MAIN" -- "$OVERLAY_DIR/$f")" ]]; then echo "$f"; fi
  done < <(G diff --name-only --no-renames "$from" "$1")
}

# publish_base <branch> <default>: the commit the branch's publish is measured from, and the one owner of a publish
# branch's shape, prepare's: exactly ONE commit whose parent is the merge base with the public default branch, or (the
# public repo still empty) the branch's empty root plus one commit. Dies naming any other shape (no shared history,
# N commits past the base, a merge): a scan of a longer branch's net diff passes a phrase one commit adds and the next
# removes, and request would push both commits.
publish_base() {
  local br="$1" db="$2" base n p
  if G rev-parse --verify -q "refs/remotes/public/$db" >/dev/null; then
    base="$(G merge-base "refs/remotes/public/$db" "$br")" || die "$br shares no history with public $PUB $db: a publish branch is cut from it; prepare it again (git branch -D $br)"
    n="$(G rev-list --count "$base..$br")"
  else
    base="$(G rev-list --max-parents=0 "$br")"
    [[ "$base" != *$'\n'* && "$(G rev-parse "$base^{tree}")" == "$EMPTY_TREE" ]] || die "$br has no single empty root and public $PUB has no $db: prepare it again (git branch -D $br)"
    n="$(( $(G rev-list --count "$br") - 1 ))"
  fi
  [[ "$n" -eq 1 ]] || die "$br is $n commits past its public base ${base:0:12}: a publish is exactly one commit on it (prepare's shape), and only that commit is scanned and pushed; prepare it again (git branch -D $br)"
  p="$(G rev-list --parents -n1 "$br" | cut -s -d' ' -f2-)"
  [[ "$p" == "$base" ]] || die "$br's one commit past ${base:0:12} has the parent(s) ${p:-none}, not its public base: a publish is one commit on the base (prepare's shape); prepare it again (git branch -D $br)"
  echo "$base"
}

# ---- the scrub gate (scrub_patterns and scrub_scan, lib.sh: the one owner of what may not leave the twin) ----------

# scrub_run <branch> <default> [<body file>]: prints every hit and returns 1, or prints a one-line pass. The branch must
# have publish_base's shape (one commit on its public base; dies otherwise), so the scan reads exactly that commit's
# diff and its message (and the empty root's, for an orphan). With an empty <branch> and <default>, only the body is
# scanned (release notes).
scrub_run() {
  local br="$1" db="$2" body="${3:-}" base="" pat rc=0
  if [[ -n "$br" ]]; then base="$(publish_base "$br" "$db")" || exit 1; fi
  pat="$(mktemp)"
  scrub_patterns > "$pat" || { rm -f "$pat"; die "cannot derive the scrub patterns (named above)"; }
  scrub_scan "$root" "$pat" "$base" "$br" "$body" || rc=$?
  rm -f "$pat"
  return $rc
}

# ---- the license gate (license.sh check: the one owner of license checks) --------------------------

# license_gate <tree-ish>: when the roster names a "license", the public tree a publish makes must carry it (present,
# its body the render's, its header the neutral one and clean, every manifest pointing at it); license.sh check prints
# each item and fails on a miss. A roster without "license" passes.
license_gate() {
  local lic; lic="$(roster_license)" || exit 1
  [[ -n "$lic" ]] || return 0
  ( cd "$root" && "$BEAST_SCRIPTS/license.sh" check "$1" )
}

# ---- rows and pull requests of a slug ------------------------------------------------------------
row_title() { echo "Decision: Publish $1 to $PUB"; }

# slug_pr <slug> <state>: the PR number on $PUB whose head is publish/<slug> (open or closed), or nothing.
slug_pr() {
  gh_get "repos/$PUB/pulls?state=$2&head=$(uri "${PUB%%/*}:publish/$1")&per_page=100" | jq -r 'sort_by(.number) | last | .number // empty'
}

# slug_row <slug>: the open approval row's number in the twin; dies unless exactly one.
slug_row() {
  local t got; t="$(row_title "$1")"
  got="$(issues_list "$TWIN" -f labels=decision -f state=open | jq -r --arg t "$t" '[.[] | select(.pull_request == null and .title == $t) | .number] | join(" ")')" || die "cannot list the open decision rows of $TWIN"
  [[ -n "$got" ]] || die "no open row \"$t\" in $TWIN (publish.sh request files it)"
  [[ "$got" != *" "* ]] || die "several open rows \"$t\" in $TWIN: #${got// /, #}; close the extra ones"
  echo "$got"
}

# slug_requested <slug>: the open approval row of a slug an amend may change; dies when the slug was never requested (no
# row of that title in the twin, open or closed) or when its row is closed (a decided publish is not amended).
slug_requested() {
  local t all open
  t="$(row_title "$1")"
  all="$(issues_list "$TWIN" -f labels=decision -f state=all | jq -c --arg t "$t" '[.[] | select(.pull_request == null and .title == $t) | {number, state}]')" || die "cannot list the decision rows of $TWIN"
  [[ "$(jq length <<< "$all")" -gt 0 ]] || die "$1 was never requested: no row \"$t\" in $TWIN (publish.sh request files it); an amend changes a requested publish, so prepare and request it instead"
  open="$(jq -r '[.[] | select(.state == "open") | .number] | join(" ")' <<< "$all")"
  [[ -n "$open" ]] || die "the row of $1 is closed ($TWIN#$(jq -r '[.[].number] | join(", #")' <<< "$all")): a decided publish is not amended; prepare a new slug"
  [[ "$open" != *" "* ]] || die "several open rows \"$t\" in $TWIN: #${open// /, #}; close the extra ones"
  echo "$open"
}

# amend_summary <old head> <new head> <default>: the change an amend makes to a publish, as "<n>\t<added>\t<removed>\t<changed>":
# n the files the new publish commit touches; added the paths it touches that the old one did not, removed the reverse,
# changed the paths both touch with a different result. Each list is comma-joined, "none" when empty, cut after 8 with
# "… (+<k> more)".
amend_summary() {
  local ob nb
  ob="$(publish_base "$1" "$3")" || exit 1
  nb="$(publish_base "$2" "$3")" || exit 1
  python3 -I - <(G diff --raw -z --no-abbrev --no-renames "$ob" "$1") <(G diff --raw -z --no-abbrev --no-renames "$nb" "$2") <<'PY'
import sys
def files(fn):
    raw = open(fn, "rb").read().split(b"\0"); out = {}
    for i in range(0, len(raw) - 1, 2):
        _, _, _, sha, st = raw[i].decode().split(" ")
        out[raw[i + 1].decode("utf-8", "surrogateescape")] = (st, sha)
    return out
old, new = files(sys.argv[1]), files(sys.argv[2])
def show(ps):
    ps = sorted(ps)
    if not ps: return "none"
    return ", ".join(ps[:8]) + (" … (+%d more)" % (len(ps) - 8) if len(ps) > 8 else "")
print("\t".join([str(len(new)), show(set(new) - set(old)), show(set(old) - set(new)), show(p for p in set(old) & set(new) if old[p] != new[p])]))
PY
}

# ---- verbs -----------------------------------------------------------------------------------------
cmd="${1:-}"; shift || true
case "$cmd" in
  prepare)
    slug="${1:-}"; shift || true; slug_check "$slug"
    mode=""; items=(); msg=""; dels=(); amend=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --amend) amend=1; shift ;;
        --paths|--commits) [[ -z "$mode" ]] || die "--paths and --commits exclude each other"; mode="${1#--}"; shift
          while [[ $# -gt 0 && "$1" != --* ]]; do items+=("$1"); shift; done ;;
        --delete) [[ -n "${2:-}" && "$2" != --* ]] || die "--delete takes one path"; dels+=("$2"); shift 2 ;;
        --message-file) msg="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ ( -n "$mode" && ${#items[@]} -gt 0 ) || ${#dels[@]} -gt 0 ]] || die "prepare needs --paths <path>..., --commits <sha>... or --delete <path>"
    [[ -z "$mode" || ${#items[@]} -gt 0 ]] || die "--$mode names nothing"
    [[ -n "$msg" && -f "$msg" ]] || die "prepare needs --message-file <f>: the commit message, written for outside readers"
    [[ -n "$(head -1 "$msg" | tr -d '[:space:]')" ]] || die "$msg: the first line (the commit's subject) is empty"
    roster_scrub >/dev/null || exit 1   # a malformed scrub entry is named before any gate runs
    br="publish/$slug"
    if [[ $amend -eq 1 ]]; then
      slug_requested "$slug" >/dev/null || exit 1
      db="$(public_fetch)" || exit 1
      was="$(G rev-parse --verify -q "refs/remotes/public/$br")" || die "$PUB has no branch $br: the request's push never landed; nothing to amend"
    else
      ! G rev-parse --verify -q "refs/heads/$br" >/dev/null || die "$br exists in $root: delete it (git branch -D $br) or choose another slug"
      db="$(public_fetch)" || exit 1
      ! G rev-parse --verify -q "refs/remotes/public/$br" >/dev/null || die "$PUB already has a branch $br: choose another slug"
    fi
    if G rev-parse --verify -q "refs/remotes/public/$db" >/dev/null; then
      parent="$(G rev-parse "refs/remotes/public/$db")"
    else
      parent="$(G commit-tree "$EMPTY_TREE" -m "Initial commit")" || die "cannot make the empty root"
      echo "$PUB is empty: the branch is an orphan, an empty root then the publish commit" >&2
    fi
    # --delete: one source of truth per path, and only what public main carries
    dpaths=()
    for d in ${dels[@]+"${dels[@]}"}; do
      d="$(publish_path "$d")" || exit 1
      [[ "$d" != "." ]] || die "--delete names the whole tree"
      if [[ "$mode" == paths ]]; then
        for p in "${items[@]}"; do
          p="$(publish_path "$p")" || exit 1
          [[ "$p" != "." && "$p" != "$d" && "$d" != "$p/"* && "$p" != "$d/"* ]] || die "--delete $d overlaps --paths $p: one source of truth per path"
        done
      fi
      [[ -z "$(G ls-tree -r --full-tree "$TWIN_MAIN" -- "$OVERLAY_DIR/$d")" ]] || die "--delete $d is shadowed by the overlay $OVERLAY_DIR/$d on twin $TWIN_MAIN: it publishes from there (one source of truth per path)"
      [[ -n "$(G ls-tree -r --full-tree "$parent" -- "$d")" ]] || die "--delete $d: public $db does not carry it (nothing to delete)"
      dpaths+=("$d")
    done
    idx="$(mktemp)"; rm -f "$idx"
    export GIT_INDEX_FILE="$idx"
    G read-tree "$parent^{tree}"
    if [[ "$mode" == paths ]]; then
      for p in "${items[@]}"; do
        p="$(publish_path "$p")" || { rm -f "$idx"; exit 1; }
        mine="$(publish_view "$TWIN_MAIN" "$p" | tr '\0' '\n')"
        theirs="$(G ls-tree -r --full-tree "$parent" -- "$p")"
        [[ -n "$mine$theirs" ]] || { rm -f "$idx"; die "path '$p' is neither in the public view of twin $TWIN_MAIN (its own files and $OVERLAY_DIR/, the root CLAUDE.md never) nor on public $db"; }
        index_drop "$p" || { rm -f "$idx"; die "cannot clear $p in the publish tree"; }
        [[ -z "$mine" ]] || publish_view "$TWIN_MAIN" "$p" | G update-index -z --index-info
      done
    elif [[ "$mode" == commits ]]; then
      shas=()
      for c in "${items[@]}"; do
        s="$(G rev-parse --verify -q "$c^{commit}")" || { rm -f "$idx"; die "commit '$c' is not in $root"; }
        G merge-base --is-ancestor "$s" "$TWIN_MAIN" || { rm -f "$idx"; die "commit $c is not on twin $TWIN_MAIN: publish only what main carries"; }
        [[ "$(G rev-list --parents -n1 "$s" | wc -w)" -le 2 ]] || { rm -f "$idx"; die "commit $c is a merge: name the commits it brought in"; }
        ot="$(overlay_touch "$s")"
        [[ -z "$ot" ]] || { rm -f "$idx"; die "commit $c touches $(tr '\n' ' ' <<< "$ot")— the root CLAUDE.md, $OVERLAY_DIR/ or a path it shadows publish only through the overlay: use --paths"; }
        shas+=("$s")
      done
      # oldest first in topological order (parents before children), never by committer date: two commits made in the
      # same second would otherwise apply out of order
      for s in $(G rev-list --topo-order --reverse "${shas[@]}" | grep -Fx -f <(printf '%s\n' "${shas[@]}")); do
        from="$(G rev-parse -q --verify "$s^" 2>/dev/null || echo "$EMPTY_TREE")"
        G diff --binary --full-index --no-renames "$from" "$s" | G apply --cached --binary \
          || { rm -f "$idx"; die "commit $(G log -1 --format='%h %s' "$s") does not apply to public $db (named above): publish the paths instead, or bring public in first"; }
      done
    fi
    for d in ${dpaths[@]+"${dpaths[@]}"}; do index_drop "$d" || { rm -f "$idx"; die "cannot remove $d from the publish tree"; }; done
    tree="$(G write-tree)"; unset GIT_INDEX_FILE; rm -f "$idx"
    [[ "$tree" != "$(G rev-parse "$parent^{tree}")" ]] || die "nothing to publish: public $db already carries these changes"
    fmsg="$(mktemp)"; cat "$msg" > "$fmsg"
    if [[ ${#dpaths[@]} -gt 0 ]]; then { printf '\nRemoved from this repository:\n'; printf -- '- %s\n' "${dpaths[@]}"; } >> "$fmsg"; fi
    commit="$(G commit-tree "$tree" -p "$parent" -F "$fmsg")" || { rm -f "$fmsg"; die "cannot make the publish commit"; }
    rm -f "$fmsg"
    # the gates on the commit before any branch exists: on a miss or a hit nothing is created
    license_gate "$commit" || die "prepare refused by the license check: the public tree would not carry the roster's license (named above); no branch was created. Render it in the twin (license.sh render -o <file>), commit it and add it to --paths"
    G update-ref "refs/publish-scrub/$slug" "$commit"
    if ! scrub_run "refs/publish-scrub/$slug" "$db"; then G update-ref -d "refs/publish-scrub/$slug"; die "prepare refused by the scrub gate: no branch was created; fix the hits (or the message file) and run prepare again"; fi
    G update-ref -d "refs/publish-scrub/$slug"
    if [[ $amend -eq 1 ]]; then
      [[ "$tree" != "$(G rev-parse "$was^{tree}")" || "$(G log -1 --format=%B "$commit")" != "$(G log -1 --format=%B "$was")" ]] \
        || die "nothing to amend: $PUB's $br (${was:0:12}) already carries this tree and message"
      G update-ref "refs/heads/$br" "$commit" || die "cannot set $br"
      echo "amended $br to $(G rev-parse --short "$commit") on public $db ($(G rev-parse --short "$parent")); the PR is at ${was:0:12}:"
      G diff --stat "$parent" "$commit" | sed 's/^/  /'
      echo "next: publish.sh request $slug --amend --seat <SEAT> [--body-file <f>]"
      exit 0
    fi
    G update-ref "refs/heads/$br" "$commit" "" || die "cannot create $br"
    echo "prepared $br at $(G rev-parse --short "$commit") on public $db ($(G rev-parse --short "$parent")):"
    G diff --stat "$parent" "$commit" | sed 's/^/  /'
    [[ ${#dpaths[@]} -eq 0 ]] || echo "removed from $PUB (the twin keeps its copy): ${dpaths[*]} — name them in the PR body"
    echo "next: publish.sh request $slug --seat <SEAT> --body-file <outside-reader description>"
    ;;
  scrub)
    slug="${1:-}"; shift || true; slug_check "$slug"
    body=""
    while [[ $# -gt 0 ]]; do case "$1" in --body-file) body="$2"; shift 2 ;; *) die "unknown argument $1" ;; esac; done
    [[ -z "$body" || -f "$body" ]] || die "no body file $body"
    br="publish/$slug"
    G rev-parse --verify -q "refs/heads/$br" >/dev/null || die "no branch $br in $root (publish.sh prepare makes it)"
    db="$(public_fetch)" || exit 1
    scrub_run "$br" "$db" "$body" || exit 1
    ;;
  request)
    slug="${1:-}"; shift || true; slug_check "$slug"
    seat=""; body=""; ms=""; amend=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --amend) amend=1; shift ;;
        --seat) seat="$2"; shift 2 ;;
        --body-file) body="$2"; shift 2 ;;
        --milestone) ms="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    roster_scrub >/dev/null || exit 1   # a malformed scrub entry is named before any gate runs
    if [[ $amend -eq 1 ]]; then
      # the amend: re-gate, force-update the PR branch (leased on the PR's head), retitle the PR, one line on the row
      [[ -n "$seat" && ( -z "$body" || -f "$body" ) ]] || die "usage: publish.sh request <slug> --amend --seat <SEAT> [--body-file <f>]"
      [[ -z "$ms" ]] || die "--milestone belongs to the first request: an amend keeps the row where it is"
      seat="$(seat_id "$seat")" || exit 1
      row="$(slug_requested "$slug")" || exit 1
      br="publish/$slug"
      G rev-parse --verify -q "refs/heads/$br" >/dev/null || die "no branch $br in $root (publish.sh prepare $slug --amend rebuilds it)"
      db="$(public_fetch)" || exit 1
      publish_base "$br" "$db" >/dev/null || exit 1
      license_gate "$br" || die "the amend was refused by the license check (named above): nothing was pushed"
      scrub_run "$br" "$db" "$body" || die "the amend was refused by the scrub gate: nothing was pushed"
      n="$(slug_pr "$slug" open)" || die "cannot list the pull requests of $PUB"
      [[ -n "$n" ]] || die "no open PR from $br on $PUB: nothing to amend"
      prh="$(gh_get "repos/$PUB/pulls/$n" | jq -r '.head.sha // empty')" || die "cannot read $PUB#$n"
      there="$(G rev-parse --verify -q "refs/remotes/public/$br")" || die "$PUB has no branch $br"
      [[ "$there" == "$prh" ]] || die "$PUB's $br is at ${there:0:12} but $PUB#$n names its head ${prh:0:12}: fetch again; nothing was pushed"
      head="$(G rev-parse "$br")"
      pend="refs/publish-amend/$slug"   # the replaced head, kept until the row carries the amend line
      if [[ "$head" == "$prh" ]]; then
        old="$(G rev-parse --verify -q "$pend")" || die "nothing to amend: $PUB's $br is already at ${head:0:12} (publish.sh prepare $slug --amend rebuilds it)"
        echo "the branch is already force-updated (${old:0:12} -> ${head:0:12}) but the row has no line for it: posting it now" >&2
      else
        ( publish_base "refs/remotes/public/$br" "$db" ) >/dev/null 2>&1 || die "$PUB's $br (${prh:0:12}) is not one publish commit on its public base: someone else pushed to the PR branch; nothing was pushed. Look at it on $PUB#$n before anything replaces it"
        old="$prh"
        G update-ref "$pend" "$old"
        public_push "$br" "refs/heads/$br" "$old"
        echo "force-updated $PUB's $br: ${old:0:12} -> ${head:0:12} (--force-with-lease on ${old:0:12})"
      fi
      sum="$(amend_summary "$old" "$head" "$db")" || exit 1
      IFS=$'\t' read -r nf added removed changed <<< "$sum"
      args=(-f title="$(G log -1 --format=%s "$br")")
      [[ -z "$body" ]] || args+=(-F body=@"$body")
      public_send PATCH "repos/$PUB/pulls/$n" "${args[@]}" >/dev/null
      echo "retitled $PUB#$n${body:+ and replaced its body}"
      coord_write_guard "$TWIN"
      line="$(amend_line "$nf files; added $added; removed $removed; changed $changed")"
      url="$(issue_comment "$TWIN" "$row" "$line")" || die "the PR branch is amended but the line on $TWIN#$row was NOT posted (named above): an earlier approval would still read as standing; rerun publish.sh request $slug --amend --seat $seat"
      G update-ref -d "$pend"
      echo "$url"
      echo "$line"
      echo "an approval given before this amend no longer counts: the decider approves again on $TWIN#$row"
      exit 0
    fi
    [[ -n "$seat" && -n "$body" && -f "$body" ]] || die "usage: publish.sh request <slug> --seat <SEAT> --body-file <f> [--milestone \"<title>\"]"
    seat="$(seat_id "$seat")" || exit 1
    decider="$(roster_decider)" || exit 1
    [[ -z "$ms" ]] || milestone_title_check "$ms"
    milestone_require "$TWIN" "$ms" >/dev/null || exit 1   # the row's milestone, checked before anything is pushed
    br="publish/$slug"
    G rev-parse --verify -q "refs/heads/$br" >/dev/null || die "no branch $br in $root (publish.sh prepare makes it)"
    db="$(public_fetch)" || exit 1
    base="$(publish_base "$br" "$db")" || exit 1
    license_gate "$br" || die "request refused by the license check (named above): nothing was pushed"
    scrub_run "$br" "$db" "$body" || die "request refused by the scrub gate: nothing was pushed"
    if ! G rev-parse --verify -q "refs/remotes/public/$db" >/dev/null; then
      public_push "$base" "refs/heads/$db"
      echo "pushed the empty root $(G rev-parse --short "$base") as $PUB $db"
    fi
    head="$(G rev-parse "$br")"
    if there="$(G rev-parse --verify -q "refs/remotes/public/$br")"; then
      [[ "$there" == "$head" ]] || die "$PUB's $br is at ${there:0:12}, not the twin's ${head:0:12}: someone moved it; nothing was pushed"
    else
      public_push "$br" "refs/heads/$br"; echo "pushed $br to $PUB"
    fi
    n="$(slug_pr "$slug" open)" || die "cannot list the pull requests of $PUB"
    if [[ -n "$n" ]]; then
      echo "reusing the open PR $PUB#$n"
    else
      n="$(public_send POST "repos/$PUB/pulls" -f title="$(G log -1 --format=%s "$br")" -f head="$br" -f base="$db" -F body=@"$body" | jq -r .number)" || exit 1
    fi
    pr="https://github.com/$PUB/pull/$n"
    echo "PR: $pr"
    "$BEAST_SCRIPTS/decision.sh" new --decides "$PUB" --title "$(row_title "$slug")" --assignee "$decider" --seat "$seat" \
      --decision "Publish $pr to $PUB: one new commit ($(G rev-parse --short "$br"), \"$(G log -1 --format=%s "$br")\"), $(G diff --shortstat "$base" "$br" | sed 's/^ //'). Read the diff there; your word goes on this row, never on the PR." \
      --unblocks "the squash-merge of $pr into $PUB $db" \
      --waits "your review of the PR's diff and description, written for outside readers" \
      --recommendation "Approve when the diff and the description are right for outside readers; the scrub gate passed on both." \
      --approve-with "publish $slug" \
      --record "$pr" ${ms:+--milestone "$ms"}
    ;;
  merge)
    slug="${1:-}"; shift || true; slug_check "$slug"
    words=""; by=""; rec=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --words) words="$2"; shift 2 ;;
        --by) by="$2"; shift 2 ;;
        --record) rec="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "$words" && -n "$by" ]] || die "usage: publish.sh merge <slug> --words \"<verbatim>\" --by <SEAT> [--record <url | commit — path>]"
    by="$(seat_id "$by")" || exit 1
    kind="$(answer_kind "$words" "publish $slug")"
    case "$kind" in
      approve|reject) ;;
      revise) die "the words are a revise: not a close. Rework, run prepare on a new slug or answer on the row; the row stays open" ;;
      *) die "the words \"$words\" neither approve (\"publish $slug\") nor reject (\"reject: …\"): a question back, answered on the row" ;;
    esac
    row="$(slug_row "$slug")" || exit 1
    rowj="$(row_read "$TWIN" "$row")" || exit 1
    if [[ "$kind" == approve ]]; then
      pend="$(row_revise_pending "$rowj")" || exit 1
      [[ -z "$pend" ]] || revise_pending_refusal "$pend"
    fi
    amended="$(row_amended_at "$rowj")"
    [[ -z "$rec" || -z "$amended" || "$kind" != approve ]] \
      || die "$TWIN#$row was amended at $amended: the approval is the decider's comment on the row after it (row_answer_url), and --record cannot show when words given elsewhere were given; nothing merged"
    if [[ -z "$rec" ]]; then
      rec="$(row_answer_url "$rowj" "publish $slug" "$kind")" || exit 1
      [[ -n "$rec" ]] || die "the decider's standing answer on $TWIN#$row is not a $kind comment: words typed to a session are recorded first; pass --record <commit — path>"
    fi
    br="publish/$slug"
    db="$(public_fetch)" || exit 1
    n="$(slug_pr "$slug" open)" || die "cannot list the pull requests of $PUB"
    [[ -n "$n" ]] || die "no open PR from $br on $PUB (publish.sh request opens it)"
    head="$(G rev-parse --verify -q "refs/heads/$br")" || die "no branch $br in $root"
    there="$(G rev-parse --verify -q "refs/remotes/public/$br")" || die "$PUB has no branch $br"
    [[ "$there" == "$head" ]] || die "$PUB's $br is at ${there:0:12}, not the twin's ${head:0:12}: someone moved it; nothing merged"
    if [[ "$kind" == reject ]]; then
      public_send PATCH "repos/$PUB/pulls/$n" -f state=closed >/dev/null
      public_send DELETE "repos/$PUB/git/refs/heads/$br" >/dev/null
      G branch -q -D "$br"
      echo "closed $PUB#$n unmerged and deleted $br"
      "$BEAST_SCRIPTS/decision.sh" close "$TWIN#$row" --words "$words" --record "$rec" --by "$by" --rejected
      exit 0
    fi
    # Public main must carry nothing twin main lacks (outside work not yet pulled), except the empty root: the
    # record below marks public main merged into twin main, which would otherwise drop that work silently.
    while IFS= read -r c; do
      [[ -n "$c" ]] || continue
      [[ "$(G rev-parse "$c^{tree}")" == "$EMPTY_TREE" && "$(G rev-list --parents -n1 "$c" | wc -w)" -eq 1 ]] \
        || die "public $db carries $(G log -1 --format='%h %s' "$c"), which twin $TWIN_MAIN lacks: publish.sh pull first; nothing merged"
    done < <(G rev-list "$TWIN_MAIN..refs/remotes/public/$db")
    scrub_run "$br" "$db" || die "merge refused by the scrub gate: nothing merged"
    subject="$(G log -1 --format=%s "$br")"; rest="$(G log -1 --format=%b "$br")"
    sha="$(public_send PUT "repos/$PUB/pulls/$n/merge" -f merge_method=squash -f sha="$head" -f commit_title="$subject (#$n)" -f commit_message="$rest" | jq -r .sha)" \
      || die "GitHub refused the squash-merge of $PUB#$n (named above): nothing was closed"
    echo "squash-merged $PUB#$n at $sha"
    public_send DELETE "repos/$PUB/git/refs/heads/$br" >/dev/null; echo "deleted $PUB's $br"
    G fetch -q --prune public || die "git fetch public failed after the merge"
    pm="$(G rev-parse "refs/remotes/public/$db")"
    [[ "$pm" == "$sha" ]] || die "public $db is at ${pm:0:12}, not the merge ${sha:0:12}: fetch again and record by hand"
    old="$(G rev-parse "$TWIN_MAIN")"
    rcd="$(G commit-tree "$old^{tree}" -p "$old" -p "$pm" -m "Record the publish of $slug ($PUB#$n): public $db ${pm:0:12} is merged; this tree already carries it")"
    G update-ref "refs/heads/$TWIN_MAIN" "$rcd" "$old" || die "cannot record the publish in twin $TWIN_MAIN (it moved): run publish.sh pull"
    G branch -q -D "$br"
    echo "twin $TWIN_MAIN records public $db ${pm:0:12} as merged ($(G rev-parse --short "$rcd"), same tree); push it: git push origin $TWIN_MAIN"
    "$BEAST_SCRIPTS/decision.sh" close "$TWIN#$row" --words "$words" --record "$rec" --by "$by" --next "push twin $TWIN_MAIN; the publish is live on $PUB"
    ;;
  pull)
    [[ $# -eq 0 ]] || die "pull takes no arguments"
    db="$(public_fetch)" || exit 1
    G rev-parse --verify -q "refs/remotes/public/$db" >/dev/null || die "$PUB has no $db yet: nothing to pull"
    if [[ -z "$(G rev-list "$TWIN_MAIN..refs/remotes/public/$db")" ]]; then echo "twin $TWIN_MAIN already carries public $db $(G rev-parse --short "refs/remotes/public/$db")"; exit 0; fi
    G merge-base "$TWIN_MAIN" "refs/remotes/public/$db" >/dev/null \
      || die "twin $TWIN_MAIN shares no history with public $db: no publish was ever recorded. When twin $TWIN_MAIN carries everything public has, record that once: git merge -s ours --allow-unrelated-histories public/$db"
    [[ "$(G branch --show-current)" == "$TWIN_MAIN" ]] || die "pull merges into $TWIN_MAIN: run it where $TWIN_MAIN is checked out (this tree is on $(G branch --show-current))"
    [[ -z "$(G status --porcelain --untracked-files=no)" ]] || die "$root has uncommitted changes: commit or stash them first"
    if ! G merge -q --no-ff --no-edit -m "Pull $PUB $db $(G rev-parse --short "refs/remotes/public/$db") into the twin (outside contributions)" "refs/remotes/public/$db"; then
      conflicted="$(G diff --name-only --diff-filter=U | tr '\n' ' ')"
      G merge --abort
      die "pulling public $db conflicts in: ${conflicted:-(see git above)}; the merge was aborted, twin $TWIN_MAIN is unchanged. Merge it by hand: git merge public/$db"
    fi
    echo "pulled public $db into twin $TWIN_MAIN ($(G rev-parse --short HEAD)); push it: git push origin $TWIN_MAIN"
    ;;
  release)
    tag="${1:-}"; shift || true
    [[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] || die "release tag '$tag' must be letters, digits, '.', '_' or '-'"
    title=""; notes=""; check=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --title) title="$2"; shift 2 ;;
        --notes-file) notes="$2"; shift 2 ;;
        --check) check=1; shift ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "${title//[[:space:]]/}" && "$title" != *$'\n'* && -n "$notes" && -f "$notes" ]] || die "usage: publish.sh release <tag> --title \"<title>\" --notes-file <f>"
    [[ -n "$(tr -d '[:space:]' < "$notes")" ]] || die "$notes is empty: release notes are written for outside readers"
    db="$(public_info | jq -r .default_branch)" || exit 1
    tf="$(mktemp)"; printf '%s\n' "$title" > "$tf"
    scrub_run "" "" "$tf" >/dev/null || { scrub_run "" "" "$tf"; rm -f "$tf"; die "release refused by the scrub gate on its title: nothing was published"; }
    rm -f "$tf"
    scrub_run "" "" "$notes" || die "release refused by the scrub gate: nothing was published"
    [[ $check -eq 0 ]] || exit 0
    err="$(mktemp)"
    if have="$(gh_get "repos/$PUB/releases/tags/$tag" 2>"$err")"; then
      rm -f "$err"
      [[ "$(jq -r .name <<< "$have")" == "$title" && "$(jq -r '.body // ""' <<< "$have")" == "$(cat "$notes")" ]] \
        || die "$PUB already has a release $tag that differs ($(jq -r .html_url <<< "$have")): choose another tag"
      echo "reusing the release $(jq -r .html_url <<< "$have")"; exit 0
    fi
    grep -q 'HTTP 404' "$err" || { cat "$err" >&2; rm -f "$err"; die "cannot tell whether $PUB has a release $tag (named above)"; }
    rm -f "$err"
    url="$(public_send POST "repos/$PUB/releases" -f tag_name="$tag" -f target_commitish="$db" -f name="$title" -F body=@"$notes" | jq -r .html_url)" || exit 1
    echo "released $url"
    ;;
  *) die "usage: publish.sh prepare|scrub|request|merge|pull|release (see the header of $0)" ;;
esac
