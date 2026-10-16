#!/usr/bin/env bash
# publish.sh — publish chosen changes of a private twin to its public repo (the roster's "publishes_to"),
# through a pull request on the public repo approved on a row in the twin. Run in a checkout of the twin.
# "Twin main" is the twin's default branch on GitHub; "public main" the public repo's.
# This script is the ONLY writer to a public repo: its pushes go through public_push and its API writes through
# public_send, both below, both refusing any repo but the roster's publishes_to. coord_write_guard (lib.sh) still
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
#   publish.sh scrub <slug> [--body-file <f>]
#       the scrub gate (below) on the branch's one commit: its diff and its message (and the body file). A branch that is
#       not exactly one commit on its public base (prepare's shape; for an empty public repo the empty root plus one
#       commit) is refused, naming its commit count, here and in request and merge (publish_base owns the shape).
#   publish.sh request <slug> --seat <SEAT> --body-file <f> [--milestone "<title>"]
#       re-scrubs (branch and body), pushes the branch to the public repo, opens the PR there with the body (an
#       outside-reader description), and files the approval row in the twin (decision.sh new, home repo,
#       --decides <public>, approved with "publish <slug>", under --milestone, which is required when the twin has an
#       open milestone and is checked before anything is pushed). Nothing else is written on the public repo.
#   publish.sh merge <slug> --words "<verbatim>" --by <SEAT> [--record <comment url | commit — path>]
#       on "publish <slug>" (or bare approve, or "<phrase> — <comment>"): re-scrubs, squash-merges the PR, deletes the
#       public branch, records public main as merged into twin main (a merge commit with twin main's own tree, so a
#       later pull brings only outside changes), closes the row on the words. On "reject: …": closes the PR unmerged,
#       deletes the branch, closes the row rejected. --record defaults to the decider's answer comment on the row.
#   publish.sh pull
#       merges the public default branch into twin main (outside contributions), in the twin's main checkout on
#       main with a clean tree; on a conflict it aborts the merge and names the conflicted files.
#   publish.sh release <tag> --title "<title>" --notes-file <f> [--check]
#       scrubs the title and the notes (written for outside readers) and creates a GitHub Release <tag> on the public repo
#       at its default branch, the notes its body; --check scrubs and writes nothing. An existing release of that tag with the same title and body is reused
#       (a rerun); one that differs dies naming it. wrapup.sh run publishes a milestone's release notes through it.
#
# The scrub gate (scrub_patterns + the scanner, the one owner of what may not leave the twin; the roster's "scrub" and
# "scrub_allow" are parsed by roster_scrub, lib.sh). The content classes read the added lines of each TEXT file; a
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
#   words          any 12-character stretch (case and spacing folded) of the words on a closed row of the twin
#                  (the close comment's verbatim words, decision rows and PR rows)
#   roster scrub   a regex of the roster's "scrub" list: a string on every text file, message and body; a
#                  {"pattern", "paths"} entry only on text files whose path matches one of its globs
#   path name      every added or changed path: a secret-shaped file name (wallet.json, .env, .env.*, *.pem, *.key,
#                  id_rsa*, id_ed25519*, *.p12, *.pfx, keystore*.json, credentials*.json), and the private repo,
#                  private name and roster scrub classes applied to the path itself
# Each hit is printed as <file>:<line>, "<path>: path name", "commit <sha> message:<line>" or "body:<line>", with its
# class; exit 1.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
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

# public_push <src> <dst-ref>: the one git push to the public repo; never forced.
public_push() {
  local u; u="$(G remote get-url public)"
  [[ "$(sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' <<< "$u" | tr 'A-Z' 'a-z')" == "$(tr 'A-Z' 'a-z' <<< "$PUB")" ]] || die "public_push: the remote public is $u, not $PUB"
  G push -q public "$1:$2" || die "git push public $1:$2 ($PUB) failed"
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

# ---- the scrub gate: the one owner of what may not leave the twin --------------------------------

# scrub_patterns: JSON {slugs: [...], names: [...], skipped: [...], words: [{url, words}], roster: [{pattern, paths}]}: the
# facts the scanner matches, derived from the roster and GitHub (every read through gh_get, so a warm cache costs no
# quota). names are the bare names checked (exact case, 5 characters or more, not in the roster's scrub_allow); skipped
# the bare names left out, whose slug form is still checked.
scrub_patterns() {
  local roster slugs="" names="" r o type me words rows n body excl priv lab rs
  roster="$(roster_path)"
  rs="$(roster_scrub "$roster")" || exit 1
  excl="$(jq -r --arg p "$PUB" '[$p] + [(.public_intended // [])[] | select(contains("/"))] | map(ascii_downcase) | .[]' "$roster")"
  me="$(gh_login)" || exit 1
  # the repos the roster names: private on GitHub (the twin is private by roster_pair_check)
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    grep -qxF -- "$(tr 'A-Z' 'a-z' <<< "$r")" <<< "$excl" && continue
    priv="$(gh_get "repos/$r" | jq -r .private)" || die "cannot read the visibility of $r (named above)"
    [[ "$priv" != true ]] || { slugs+="$r"$'\n'; names+="${r#*/}"$'\n'; }
  done < <(jq -r '[.repo, .board, (.seats[]?.repo)] | map(select(. != null)) | unique | .[]' "$roster")
  # every private repo of every owner the roster names (repo, publishes_to, board, seat repos, tracking refs): an org's
  # through orgs/<o>/repos?type=private, the gh login's through user/repos; another user's cannot be listed and dies
  local lst
  while IFS= read -r o; do
    [[ -n "$o" ]] || continue
    type="$(gh_get "users/$o" | jq -r .type)" || die "cannot read the GitHub account $o (named above)"
    if [[ "$type" == Organization ]]; then lst="$(gh_get_all "orgs/$o/repos?type=private")" || die "cannot list the private repos of the org $o (named above): the scrub would pass them"
    elif [[ "$(tr 'A-Z' 'a-z' <<< "$o")" == "$(tr 'A-Z' 'a-z' <<< "$me")" ]]; then lst="$(gh_get_all "user/repos?visibility=private&affiliation=owner")" || die "cannot list the private repos of $o (named above): the scrub would pass them"
    else die "the roster names the user $o, whose private repos the gh login $me cannot list: the scrub cannot cover them"; fi
    lst="$(jq -r '.[] | select(.private == true) | .full_name' <<< "$lst")" || die "cannot read the private repo list of $o"
    slugs+="$lst"$'\n'; names+="$(sed 's#^[^/]*/##' <<< "$lst")"$'\n'
  done < <(jq -r '[.repo, .publishes_to, .board, (.seats[]?.repo), (.seats[]?.tracking | select(. != null) | split("#")[0])] | map(select(. != null and contains("/")) | split("/")[0]) | unique_by(ascii_downcase) | .[]' "$roster")
  slugs="$(printf '%s' "$slugs" | sed '/^$/d' | while IFS= read -r r; do grep -qxF -- "$(tr 'A-Z' 'a-z' <<< "$r")" <<< "$excl" || echo "$r"; done | sort -fu)"
  # the bare names: those of the slugs that remain (the public target and exact public_intended entries are excluded above)
  names="$(sed 's#^[^/]*/##' <<< "$slugs" | sort -u)"
  # the words of every closed row of the twin (decision rows and PRs on the board)
  words='[]'
  for lab in decision needs-review; do
    rows="$(issues_list "$TWIN" -f labels="$lab" -f state=closed | jq -r '.[].number')" || die "cannot list the closed $lab rows of $TWIN"
    for n in $rows; do
      body="$(issue_comments "$TWIN" "$n" | jq -c --arg u "https://github.com/$TWIN/issues/$n" '
        [.[] | (.body // "") | capture("^(Closed|Rejected) on the word, verbatim: \"(?<w>.*)\"\n\nRecord: "; "p")? | {url: $u, words: .w}]')" \
        || die "cannot read the comments of $TWIN#$n"
      words="$(jq -c -s 'add' <(printf '%s\n' "$words") <(printf '%s\n' "$body"))"
    done
  done
  jq -n --arg s "$slugs" --arg nm "$names" --argjson w "$words" --argjson rs "$rs" --arg rec "$RECORD_PATH_RE" '
    ($nm | split("\n") | map(select(length > 0)) | unique) as $all
    | ($all | map(select(length >= 5 and (. as $n | $rs.allow | index($n) | not)))) as $chk
    | {slugs: ($s | split("\n") | map(select(length > 0))), names: $chk, skipped: ($all - $chk), words: ($w | unique_by(.words)),
       roster: $rs.scrub, record_re: $rec}'
}

# scrub_run <branch> <default> [<body file>]: prints every hit and returns 1, or prints a one-line pass. The branch must
# have publish_base's shape (one commit on its public base; dies otherwise), so the scan reads exactly that commit's
# diff and its message (and the empty root's, for an orphan). With an empty <branch> and <default>, only the body is
# scanned (release notes).
#   content classes  read the added lines of every TEXT file; a binary file (a NUL byte in its first 8000 bytes, git's
#                    own test) is not read, and each one skipped is named on stderr
#   path name        every added or changed path: a secret-shaped file name, a private repo slug or name, a roster
#                    pattern (a scoped one only on the paths its globs match)
scrub_run() {
  local br="$1" db="$2" body="${3:-}" base="" pat
  if [[ -n "$br" ]]; then base="$(publish_base "$br" "$db")" || exit 1; fi
  pat="$(mktemp)"
  scrub_patterns > "$pat" || { rm -f "$pat"; die "cannot derive the scrub patterns (named above)"; }
  local rc=0
  ( cd "$root" && python3 -I - "$pat" "$base" "$br" "$body" ) <<'PY' || rc=$?
import codecs, fnmatch, json, re, subprocess, sys
pat_file, base, br, body = sys.argv[1:5]
P = json.load(open(pat_file))
def git(*a):
    return subprocess.run(["git", *a], check=True, capture_output=True).stdout
rules = []   # (class, compiled regex, path globs or None for every text)
for s in P["slugs"]:
    rules.append(("private repo " + s, re.compile(r"(?<![A-Za-z0-9_.-])" + re.escape(s) + r"(?![A-Za-z0-9_-])", re.I), None))
for n in P["names"]:   # exact case: a repo's own name, never the English word it may also be
    rules.append(("private repo name " + n, re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(n) + r"(?![A-Za-z0-9_-])"), None))
rules.append(("local path", re.compile(r"(?<![A-Za-z0-9_.~-])/(Users|home)/[A-Za-z0-9._-]+/"), None))
rules.append(("record path", re.compile(P["record_re"]), None))
for e in P["roster"]:   # parsed and compiled once already by roster_scrub (lib.sh)
    rules.append(("roster scrub /%s/%s" % (e["pattern"], "" if e["paths"] is None else " in " + ",".join(e["paths"])), re.compile(e["pattern"]), e["paths"]))
def applies(globs, path):
    return globs is None or (path is not None and any(fnmatch.fnmatchcase(path, g) for g in globs))
SECRET_NAMES = ["wallet.json", ".env", ".env.*", "*.pem", "*.key", "id_rsa*", "id_ed25519*", "*.p12", "*.pfx", "keystore*.json", "credentials*.json"]
beast_line = re.compile(r"^[\s>`'\"*#-]*BEAST-[A-Z]+(\s|$)")
fold = lambda t: re.sub(r"\s+", " ", t).casefold()
W = 12
windows = {}
for w in P["words"]:
    f = fold(w["words"])
    for i in range(len(f) - W + 1):
        windows.setdefault(f[i:i+W], w["url"])
hits = []
def scan(where, lineno, line, path=None):
    for cls, rx, globs in rules:
        if not applies(globs, path): continue
        m = rx.search(line)
        if m: hits.append("%s:%d: %s: %s" % (where, lineno, cls, m.group(0)))
    if beast_line.search(line) and not re.search(r"[<$]", line):
        hits.append("%s:%d: BEAST- line: %s" % (where, lineno, line.strip()[:80]))
    f = fold(line)
    for i in range(len(f) - W + 1):
        u = windows.get(f[i:i+W])
        if u:
            hits.append("%s:%d: words of %s: \"%s\"" % (where, lineno, u, f[i:i+W])); break
def scan_path(path):
    leaf = path.rsplit("/", 1)[-1].lower()
    for g in SECRET_NAMES:
        if fnmatch.fnmatchcase(leaf, g): hits.append("%s: path name: secret-shaped file name (%s)" % (path, g)); break
    for cls, rx, globs in rules:
        if not applies(globs, path): continue
        m = rx.search(path)
        if m: hits.append("%s: path name: %s: %s" % (path, cls, m.group(0)))
binaries = set()
if br:
    # the files the one commit adds or changes (a deletion publishes no content), unquoted
    raw = git("diff", "--raw", "-z", "--no-abbrev", "--no-renames", base, br).split(b"\0")
    changed = []   # (path, blob sha, mode)
    for i in range(0, len(raw) - 1, 2):
        meta, path = raw[i].decode(), raw[i + 1].decode("utf-8", "surrogateescape")
        _, mode, _, sha, st = meta.split(" ")   # ":<old mode> <new mode> <old sha> <new sha> <status>"
        if st != "D": changed.append((path, sha, mode))
    blobs = [(p, s) for p, s, m in changed if m != "160000"]
    if blobs:
        out = subprocess.run(["git", "cat-file", "--batch"], input=b"".join(s.encode() + b"\n" for _, s in blobs), check=True, capture_output=True).stdout
        pos = 0
        for p, s in blobs:
            nl = out.index(b"\n", pos); size = int(out[pos:nl].split(b" ")[2]); data = out[nl + 1:nl + 1 + size]; pos = nl + 1 + size + 1
            if b"\0" in data[:8000]: binaries.add(p)
    for p, _, _ in changed: scan_path(p)
    for p in sorted(binaries):
        print("scrub: binary file %s not scanned for content (a NUL byte in its first 8000 bytes); its path name was checked" % p, file=sys.stderr)
    # the added lines of the text files, with their new line numbers
    diff = git("-c", "core.quotePath=false", "diff", "-U0", "--text", "--no-color", "--no-ext-diff", "--no-renames", base, br).decode("utf-8", "replace")
    cur, ln, header = None, 0, False   # a "+++ " line names a file only in a file header, never inside a hunk
    for line in diff.split("\n"):
        if line.startswith("diff --git "):
            header = True
        elif header and line.startswith("+++ "):
            t = line[4:]
            if t.startswith('"'): t = codecs.escape_decode(t[1:-1].encode("latin-1", "backslashreplace"))[0].decode("utf-8", "replace")
            cur = None if t == "/dev/null" else t[2:] if t.startswith("b/") else t
            if cur in binaries: cur = None
        elif line.startswith("@@"):
            header = False; ln = int(re.match(r"@@ -\S+ \+(\d+)", line).group(1))
        elif not header and line.startswith("+") and cur is not None:
            scan(cur, ln, line[1:], cur); ln += 1
    # the one commit's message, and the empty root's when the branch is an orphan
    for sha in git("rev-list", br if git("rev-list", "--max-parents=0", br).decode().strip() == base else base + ".." + br).decode().split():
        msg = git("log", "-1", "--format=%B", sha).decode("utf-8", "replace")
        for i, l in enumerate(msg.split("\n"), 1): scan("commit %s message" % sha[:12], i, l)
if body:
    for i, l in enumerate(open(body, encoding="utf-8").read().split("\n"), 1): scan("body", i, l)
if hits:
    print("scrub: %d hit(s) on %s; nothing of this leaves the twin:" % (len(hits), br or body))
    for h in hits: print("  " + h)
    sys.exit(1)
print("scrub: clean (%s from %s: %d private repo slugs, %d private repo names (%d short or allowed left to their slugs), %d closed rows' words, %d roster patterns checked; %d binary file(s) not read)" % (br or body, base[:12] or "-", len(P["slugs"]), len(P["names"]), len(P["skipped"]), len(P["words"]), len(P["roster"]), len(binaries)))
PY
  rm -f "$pat"
  return $rc
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

# ---- verbs -----------------------------------------------------------------------------------------
cmd="${1:-}"; shift || true
case "$cmd" in
  prepare)
    slug="${1:-}"; shift || true; slug_check "$slug"
    mode=""; items=(); msg=""; dels=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
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
    br="publish/$slug"
    ! G rev-parse --verify -q "refs/heads/$br" >/dev/null || die "$br exists in $root: delete it (git branch -D $br) or choose another slug"
    db="$(public_fetch)" || exit 1
    ! G rev-parse --verify -q "refs/remotes/public/$br" >/dev/null || die "$PUB already has a branch $br: choose another slug"
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
    # the gate on the commit before any branch exists: on a hit nothing is created
    G update-ref "refs/publish-scrub/$slug" "$commit"
    if ! scrub_run "refs/publish-scrub/$slug" "$db"; then G update-ref -d "refs/publish-scrub/$slug"; die "prepare refused by the scrub gate: no branch was created; fix the hits (or the message file) and run prepare again"; fi
    G update-ref -d "refs/publish-scrub/$slug"
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
    seat=""; body=""; ms=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --seat) seat="$2"; shift 2 ;;
        --body-file) body="$2"; shift 2 ;;
        --milestone) ms="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "$seat" && -n "$body" && -f "$body" ]] || die "usage: publish.sh request <slug> --seat <SEAT> --body-file <f> [--milestone \"<title>\"]"
    seat="$(seat_rostered "$seat")" || exit 1
    decider="$(roster_decider)" || exit 1
    [[ -z "$ms" ]] || milestone_title_check "$ms"
    milestone_require "$TWIN" "$ms" >/dev/null || exit 1   # the row's milestone, checked before anything is pushed
    br="publish/$slug"
    G rev-parse --verify -q "refs/heads/$br" >/dev/null || die "no branch $br in $root (publish.sh prepare makes it)"
    db="$(public_fetch)" || exit 1
    base="$(publish_base "$br" "$db")" || exit 1
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
    by="$(seat_rostered "$by")" || exit 1
    kind="$(answer_kind "$words" "publish $slug")"
    case "$kind" in
      approve|reject) ;;
      revise) die "the words are a revise: not a close. Rework, run prepare on a new slug or answer on the row; the row stays open" ;;
      *) die "the words \"$words\" neither approve (\"publish $slug\") nor reject (\"reject: …\"): a question back, answered on the row" ;;
    esac
    row="$(slug_row "$slug")" || exit 1
    if [[ -z "$rec" ]]; then
      rec="$(row_answer_url "$(row_read "$TWIN" "$row")" "publish $slug" "$kind")" || exit 1
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
