#!/usr/bin/env bash
# Shared helpers for the daita-beast scripts. Sourced, never executed.
set -euo pipefail

die() { echo "daita-beast: $*" >&2; exit 1; }

need() { for t in "$@"; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done; }

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The directory the plugin's scripts live in (claude_block_render, the hooks and seat.sh name it).
BEAST_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# repo_root: the working tree the caller stands in (a worktree home's own tree). In a wrapper home, which
# is not a git tree, it is the checkout the wrapper's .beast/seat.json names in "root" (written by seat.sh new).
repo_root() {
  local t f
  if t="$(git rev-parse --show-toplevel 2>/dev/null)"; then echo "$t"; return 0; fi
  f="$PWD/.beast/seat.json"
  [[ -f "$f" ]] || die "not inside a git repository, nor a Beast wrapper home ($f absent)"
  [[ "$(jq -r '.kind // empty' "$f")" == wrapper ]] || die "$f is not a wrapper home's seat.json, and $PWD is not inside a git repository"
  t="$(jq -r '.root // empty' "$f")"
  [[ -n "$t" && -d "$t/.git" ]] || die "$f names no checkout in \"root\" (got '$t'): rerun seat.sh new from the checkout"
  echo "$t"
}

# repo_main_root: the repo's main checkout, the same from the checkout, any of its worktrees, or a wrapper.
repo_main_root() {
  local c; c="$(git -C "$(repo_root)" rev-parse --path-format=absolute --git-common-dir)" || die "cannot read the git common dir of $(repo_root)"
  [[ "$(basename "$c")" == .git ]] || die "the repo's git dir $c is not a checkout's .git (a bare repo has no main checkout)"
  dirname "$c"
}

# repo_slug [root]: the owner/repo of the checkout's origin on github.com; dies when there is none.
repo_slug() {
  local root="${1:-}" u
  [[ -n "$root" ]] || root="$(repo_root)"
  u="$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
  [[ "$u" =~ ^[^/]+/[^/]+$ ]] || die "$root has no origin remote on github.com"
  echo "$u"
}

# The committed, repo-scoped roster: the main checkout's, so every home of the repo reads one roster.
roster_path() { echo "$(repo_main_root)/.beast/roster.json"; }

# The repo where this repo's deciders' board is published (roster "board"); fails loud if unset.
board_repo() {
  local r; r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  local b; b="$(jq -r '.board // empty' "$r")"
  [[ -n "$b" ]] || die "roster $r has no \"board\" field (owner/repo where the pinned board is published)"
  echo "$b"
}

# The machine-local address file (never committed).
sessions_path() { echo "${BEAST_SESSIONS_FILE:-$HOME/.beast/sessions.json}"; }

# ---- seat identity: the one owner ---------------------------------------------------------------
# A seat's id is <login>/<LABEL>: the roster row's `github` and `label`, derived here and never stored.
# A label is unique per login. Every script resolves a seat through these functions.
SEAT_LOGIN_PART='[A-Za-z0-9-]+'
SEAT_LABEL_PART='[A-Z0-9_-]+'
SEAT_ID_RE="^${SEAT_LOGIN_PART}/${SEAT_LABEL_PART}\$"
SEAT_LABEL_RE="^${SEAT_LABEL_PART}\$"
# A seat as written in a comment (ack, status, close): a qualified id, or a bare label resolved through seat_id.
SEAT_TOKEN_RE="(${SEAT_LOGIN_PART}/)?${SEAT_LABEL_PART}"

# roster_check_unique [roster]: dies when a seat row lacks a well-formed github or label, or when two rows
# share one (github, label) pair. Every script that reads the roster's seats calls it (via roster_seat_ids).
roster_check_unique() {
  local r="${1:-}" bad
  [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  bad="$(jq -r --arg re "$SEAT_ID_RE" '[.seats[]? | "\(.github // "")/\(.label // "")" | select(test($re) | not)] | join(", ")' "$r")"
  [[ -z "$bad" ]] || die "roster $r: seat row(s) whose github/label is not <login>/<LABEL>: $bad"
  bad="$(jq -r '[.seats[]? | "\(.github)/\(.label)"] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' "$r")"
  [[ -z "$bad" ]] || die "roster $r: two seat rows share the id $bad (a label is unique per login)"
}

# roster_seat_ids [roster]: every seat id of the roster, one per line, roster order.
roster_seat_ids() {
  local r="${1:-}"
  [[ -n "$r" ]] || r="$(roster_path)"
  roster_check_unique "$r"
  jq -r '.seats[]? | "\(.github)/\(.label)"' "$r"
}

# seat_id <LABEL | login/LABEL>: the seat's id. An id is validated and returned as is; a bare LABEL resolves
# through this repo's roster to exactly one seat, else dies naming the candidates.
seat_id() {
  local x="${1:-}" ids hits
  [[ -n "$x" ]] || die "no seat given (a LABEL or <login>/<LABEL>)"
  if [[ "$x" == */* ]]; then
    [[ "$x" =~ $SEAT_ID_RE ]] || die "seat id '$x' is not <login>/<LABEL> (login: letters, digits, -; LABEL: A-Z, 0-9, _, -)"
    echo "$x"; return 0
  fi
  [[ "$x" =~ $SEAT_LABEL_RE ]] || die "seat label '$x' must be upper-case letters, digits, _ or -"
  ids="$(roster_seat_ids)" || exit 1
  hits="$(printf '%s\n' "$ids" | awk -F/ -v l="$x" '$2 == l')"
  [[ -n "$hits" ]] || die "seat '$x' is not in $(roster_path) (its seats: $(printf '%s' "$ids" | tr '\n' ' '))"
  [[ "$hits" != *$'\n'* ]] || die "seat label '$x' names several seats in $(roster_path): $(printf '%s' "$hits" | tr '\n' ' '); name one by its id"
  echo "$hits"
}

seat_login() { [[ "${1:-}" =~ $SEAT_ID_RE ]] || die "seat_login: '${1:-}' is not a seat id"; echo "${1%%/*}"; }
seat_label() { [[ "${1:-}" =~ $SEAT_ID_RE ]] || die "seat_label: '${1:-}' is not a seat id"; echo "${1#*/}"; }

# seat_rostered <LABEL | id>: the id, dying unless it is a seat of this repo's roster.
seat_rostered() {
  local id; id="$(seat_id "${1:-}")" || exit 1
  roster_seat_ids | grep -qxF -- "$id" || die "seat $id is not in $(roster_path)"
  echo "$id"
}

# seat_display <id> <viewer-login>: LABEL when the seat is the viewer's own, else the id.
seat_display() { if [[ "$(seat_login "$1")" == "$2" ]]; then seat_label "$1"; else echo "$1"; fi; }

# seat_resolve <token>: a parser's resolution of a seat written in a comment or a row label (without
# "seat:"): the id, or (a bare label that does not resolve to one seat) named on stderr and status 1.
# A qualified id in a comment (login/LABEL) is self-describing and is read as written: a row in one repo is
# acked by seats this checkout's roster may not list. Only a bare LABEL (comments from before the relabel)
# needs the roster, and is dropped, named, when it does not resolve to exactly one seat.
seat_resolve() {
  local id
  if [[ "$1" =~ ^[A-Za-z0-9-]+/[A-Z0-9_-]+$ ]]; then echo "$1"; return 0; fi
  id="$(seat_id "$1")" || { echo "daita-beast: seat '$1' does not resolve to one seat of $(roster_path); dropped" >&2; return 1; }
  echo "$id"
}

# tracking_ref <owner/repo#N | url>: the normalized owner/repo#N of a workstream tracking issue; dies unless it is labelled workstream.
tracking_ref() {
  local r n
  read -r r n < <(parse_issue_ref "$1")
  issue_get "$r" "$n" | jq -e '.labels | any(.name == "workstream")' >/dev/null || die "$r#$n is not labelled workstream"
  echo "$r#$n"
}

# ---- seat home: the one owner of where a seat's session runs -------------------------------------
# The roster row's "home" is {kind: checkout|worktree|wrapper, branch: <branch>|null}, or {kind: subdir, dir:
# <path relative to the checkout>}: portable. The local path is derived here, never stored in the roster.

# seat_home_path_of <kind> <login> <LABEL> <main root> [<dir>]: the formula, one place. <dir> is given for subdir only.
seat_home_path_of() {
  local kind="$1" login="$2" label="$3" root="$4" dir="${5:-}"
  [[ "$kind" == subdir || -z "$dir" ]] || die "a home dir is only for kind subdir, not $kind"
  case "$kind" in
    checkout) echo "$root" ;;
    worktree) echo "$(dirname "$root")/$(basename "$root").seats/$label" ;;
    wrapper)  echo "$HOME/.beast/homes/$login/$label" ;;
    subdir)   [[ -n "$dir" ]] || die "home kind subdir needs its dir (roster home.dir)"; echo "$root/$dir" ;;
    *) die "home kind '$kind' is not checkout, worktree, wrapper or subdir" ;;
  esac
}

# seat_home_kind <id>: the roster row's home.kind, or "legacy" for a row written before homes existed
# (read as a checkout home by seat_home_path; join tells the seat to record it). Dies on any other value.
seat_home_kind() {
  local id="$1" k
  k="$(jq -r --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" \
    '.seats[] | select(.github == $g and .label == $l) | if has("home") then (.home.kind // "MISSING") else "legacy" end' "$(roster_path)")"
  case "$k" in
    checkout|worktree|wrapper|subdir|legacy) echo "$k" ;;
    *) die "seat $id: roster home.kind is '$k', not checkout, worktree, wrapper or subdir" ;;
  esac
}

# seat_repo <LABEL | id>: the owner/repo the seat works in (its roster row's "repo"); dies when the row has none.
seat_repo() {
  local id r
  id="$(seat_rostered "${1:-}")" || exit 1
  r="$(jq -r --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" '.seats[] | select(.github == $g and .label == $l) | .repo // empty' "$(roster_path)")"
  [[ "$r" =~ ^[^/]+/[^/]+$ ]] || die "seat $id: roster row has no \"repo\" (owner/repo), got '$r'"
  echo "$r"
}

# seat_home_path <LABEL | id>: the seat's home on this machine. Only from a checkout (or home) of the seat's own repo.
seat_home_path() {
  local id root repo kind dir=""
  id="$(seat_rostered "${1:-}")" || exit 1
  root="$(repo_main_root)"
  repo="$(jq -r --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" '.seats[] | select(.github == $g and .label == $l) | .repo' "$(roster_path)")"
  [[ "$repo" == "$(repo_slug "$root")" ]] || die "seat $id works in $repo, not in $(repo_slug "$root") ($root): its home is derived from a checkout of $repo"
  kind="$(seat_home_kind "$id")" || exit 1
  [[ "$kind" != legacy ]] || kind=checkout
  [[ "$kind" != subdir ]] || dir="$(jq -r --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" '.seats[] | select(.github == $g and .label == $l) | .home.dir // empty' "$(roster_path)")"
  seat_home_path_of "$kind" "$(seat_login "$id")" "$(seat_label "$id")" "$root" "$dir"
}

# seat_json_id <dir>: the seat id the directory's .beast/seat.json names, or nothing when there is none.
seat_json_id() {
  local f="$1/.beast/seat.json"
  [[ -f "$f" ]] || return 0
  jq -er '.id | strings' "$f" 2>/dev/null || die "$f has no string \"id\" (malformed seat.json)"
}

# ---- the CLAUDE.md block: one renderer, used by join.sh and seat.sh ------------------------------
# protocol_repo: the repo whose docs/protocol.md the block points at. A checkout of the plugin's own twin carries
# its roster beside the plugin: the twin's public repo (publishes_to) once that repo, under its own name, carries
# docs/protocol.md on its default branch, else the twin. A copy installed without that roster was made from a
# publish: its plugin.json "repository" names the public repo.
protocol_repo() {
  local pr="$BEAST_SCRIPTS/../../.beast/roster.json" twin pub info err
  if [[ -f "$pr" ]]; then
    twin="$(jq -r '.repo // empty' "$pr")"; pub="$(jq -r '.publishes_to // empty' "$pr")"
    [[ "$twin" =~ ^[^/]+/[^/]+$ ]] || die "the plugin's roster $pr has no \"repo\" (owner/repo)"
    if [[ -n "$pub" ]]; then
      err="$(mktemp)"
      if info="$(gh_get "repos/$pub" 2>"$err")"; then
        if [[ "$(jq -r .full_name <<< "$info" | tr 'A-Z' 'a-z')" == "$(tr 'A-Z' 'a-z' <<< "$pub")" ]] \
           && gh_get "repos/$pub/contents/docs/protocol.md" >/dev/null 2>"$err"; then rm -f "$err"; echo "$pub"; return 0; fi
      fi
      grep -q 'HTTP 404' "$err" || [[ ! -s "$err" ]] || { cat "$err" >&2; rm -f "$err"; die "cannot tell whether $pub carries docs/protocol.md (named above)"; }
      rm -f "$err"
    fi
    echo "$twin"; return 0
  fi
  pub="$(jq -r '.repository // empty' "$BEAST_SCRIPTS/../.claude-plugin/plugin.json" | sed -E 's#^https://github.com/##; s#\.git$##')"
  [[ "$pub" =~ ^[^/]+/[^/]+$ ]] || die "the plugin has neither its roster ($pr) nor a github \"repository\" in plugin.json: cannot name where the protocol is read"
  echo "$pub"
}

# claude_block_render: the Beast block for this repo's roster, from templates/claude-block.md.
claude_block_render() {
  local roster seats_md board pub twin="" proto decider decider_name
  roster="$(roster_path)"
  pub="$(roster_pair_check "$roster")" || exit 1
  proto="$(protocol_repo)" || exit 1
  [[ -z "$pub" ]] || twin="**This repo is the private twin of \`$pub\`.** All work and coordination happen here: decision rows, desks, tracking issues, status, notes, acks and the decider's words. \`$pub\` receives only publishes and never a coordination comment: the scripts refuse every coordination write to a public or public-intended repo, and \`publish.sh\` is the only writer to \`$pub\`. To publish: (1) \`publish.sh prepare <slug> --paths <path>… | --commits <sha>… --message-file <f>\` cuts \`publish/<slug>\` from \`$pub\`'s default branch with ONE new commit, its message written for outside readers, never this repo's history; (2) the scrub gate runs in prepare and again before every push and merge (\`publish.sh scrub <slug>\`), naming each hit: a private repo's slug or name, a local path, a \`BEAST-\` line, a record path, words from a closed row here, a roster \`scrub\` pattern, a secret-shaped file name; a branch that is not exactly one commit on the public base is refused; (3) \`publish.sh request <slug> --seat <SEAT> --body-file <f>\` pushes the branch, opens the PR on \`$pub\` with an outside-reader description and files the approval row HERE, approved with \`publish <slug>\`; the decider answers on the row, nothing of theirs goes on the PR; (4) on the word, \`publish.sh merge <slug> --words \"<verbatim>\" --by <SEAT>\` squash-merges, deletes the branch and closes the row; (5) \`publish.sh pull\` brings outside contributions merged on \`$pub\` into this repo's default branch."
  seats_md="$(roster_seat_ids "$roster" | while IFS= read -r id; do
    jq -r --arg id "$id" --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" '.seats[] | select(.github == $g and .label == $l) | "- **\($id)** (\(.lane), \(.repo)): \(.role)" + (if .tracking then ". Tracking: \(.tracking)" else "" end)' "$roster"
  done)" || exit 1
  board="$(jq -r '.board // .repo' "$roster")"
  # the decider: the roster's one owner (roster_decider dies naming the roster when there is not exactly one); the
  # name shown is that people[] row's "name", required
  decider="$(roster_decider)" || exit 1
  decider_name="$(jq -r --arg g "$decider" '[.people[] | select(.github == $g) | .name // empty] | first // empty' "$roster")"
  [[ -n "$decider_name" ]] || die "roster $roster: the owner $decider has no \"name\" in people[]: the CLAUDE.md block names the decider"
  BLOCK_SEATS="$seats_md" BLOCK_SCRIPTS="$BEAST_SCRIPTS" BLOCK_BOARD="$board" BLOCK_TWIN="$twin" BLOCK_PROTOCOL="$proto" \
    BLOCK_DECIDER="$decider" BLOCK_DECIDER_NAME="$decider_name" python3 - "$BEAST_SCRIPTS/../templates/claude-block.md" <<'PY2'
import os,sys
s=open(sys.argv[1]).read()
assert "@@TWIN@@\n\n" in s, "the block template has no '@@TWIN@@' paragraph line"
if not os.environ["BLOCK_TWIN"]: s=s.replace("@@TWIN@@\n\n","")
for k in ("TWIN","SEATS","SCRIPTS","BOARD","PROTOCOL","DECIDER_NAME","DECIDER"):
    s=s.replace("@@%s@@"%k, os.environ["BLOCK_"+k])
assert "@@" not in s, "unfilled field in the block template"
sys.stdout.write(s)
PY2
}

# claude_block_write <CLAUDE.md>: replaces the file's block (or appends it); the rest of the file is kept.
claude_block_write() {
  local md="$1" block
  [[ -f "$md" ]] || die "no $md to write the Beast block into"
  block="$(claude_block_render)" || die "cannot render the CLAUDE.md block"
  BLOCK="$block" python3 - "$md" <<'PY2'
import os,re,sys
p=sys.argv[1]; s=open(p).read(); b=os.environ["BLOCK"].rstrip("\n")+"\n"
pat=re.compile(r"<!-- beast:begin.*?<!-- beast:end -->\n?", re.S)
if pat.search(s): new=pat.sub(lambda m:b, s, count=1)
else: new=s.rstrip("\n")+("\n\n" if s.strip() else "")+b
open(p,"w").write(new)
print("block %s in %s" % ("unchanged" if new==s else "written", p))
PY2
}

# seat_label_ensure <repo> <id>: the row label of a seat, created or updated in <repo>.
# seat_comment_tokens <id>: the seat tokens that name <id> in COMMENTS (BEAST-STATUS / BEAST-ACK / Closed by),
# one per line: the id, and the bare LABEL when it resolves to exactly this id (comments written before the
# 2026-10-15 relabel carry bare labels and cannot be relabeled). Row labels never use the bare form.
seat_comment_tokens() {
  local id b; id="$(seat_id "${1:-}")" || exit 1
  echo "$id"
  if b="$(seat_id "$(seat_label "$id")" 2>/dev/null)" && [[ "$b" == "$id" ]]; then seat_label "$id"; fi
}

seat_label_ensure() { label_ensure "$1" "seat:$2" 5319E7 "Seat $2 waits on this"; }

# seat_label_terms <id>: the row label names that mean "waits on <id>" (seat:<id>), one per line.
seat_label_terms() {
  local id
  id="$(seat_id "${1:-}")" || exit 1
  [[ "$id" == "$1" ]] || die "seat_label_terms takes a seat id, not '$1'"
  echo "seat:$id"
}

# row_seat_ids <labels-json>: the seat ids of a row from its labels (REST .labels), one per line, unique.
row_seat_ids() {
  local t
  jq -r '.[] | (.name // .) | select(startswith("seat:")) | sub("^seat:"; "")' <<< "$1" \
    | while IFS= read -r t; do [[ -n "$t" ]] && { seat_resolve "$t" || true; }; done | awk '!seen[$0]++'
}

# Resolve "owner/repo#123" or a full issue or pull request URL to "owner/repo" and the number (the issues
# endpoints serve both). Prints two words: repo number.
parse_issue_ref() {
  local ref="$1"
  if [[ "$ref" =~ ^https://github\.com/([^/]+/[^/]+)/(issues|pull)/([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[3]}"
  elif [[ "$ref" =~ ^([^/#]+/[^/#]+)#([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
  else
    die "cannot read issue reference '$ref' (expected owner/repo#N, or an issue or pull request URL)"
  fi
}

# Extract the text under a "## <Heading>" section of a markdown body, up to the next "## ".
# Usage: section "<heading>" <<< "$body"   (prints nothing if absent; use section_required to fail)
section() {
  local heading="$1"
  awk -v h="## $heading" '
    $0 == h { on=1; next }
    on && /^## / { exit }
    on { print }
  '
}

# Same, but exits 1 naming the issue when the section is absent or empty.
section_required() {
  local heading="$1" body="$2" who="$3" out
  out=$(printf '%s\n' "$body" | section "$heading" | sed '/^[[:space:]]*$/d')
  [[ -n "$out" ]] || die "$who: body has no non-empty '## $heading' section (parse by shape; fix the issue body)"
  printf '%s\n' "$out"
}

# One-line cell for a markdown table: join lines, escape pipes, trim.
cell() { tr '\n' ' ' | sed -e 's/|/\\|/g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//'; }

# The repo's award policy: `.beast/award-policy.md` at the root of the current checkout. Required by
# award.sh and bounty.sh. Fails loud when absent, when it names another repo, when it still carries a
# fill field (`<owner/repo>` or `<TOKEN>`), or when its token is not the one being awarded. Prints the policy's token.
award_policy_token() {
  local repo="$1" want="${2:-}" f
  f="$(repo_root)/.beast/award-policy.md"
  [[ -f "$f" ]] || die "no award policy at $f — write one first: init-repo.sh $repo --path <checkout> --token <TOKEN> (a repo that takes no outside contributions has no policy and awards nothing)"
  head -1 "$f" | grep -q -- "— $repo\$" || die "$f is the policy of '$(head -1 "$f" | sed 's/^# Award policy — //')', not of $repo"
  ! grep -q -e '<owner/repo>' -e '<TOKEN>' "$f" || die "$f still carries a fill field: $(grep -o -e '<owner/repo>' -e '<TOKEN>' "$f" | head -1) — set it, a placeholder policy awards nothing"
  local tok; tok="$(sed -n 's/^Token: \([A-Z0-9]\{2,12\}\).*/\1/p' "$f" | head -1)"
  [[ -n "$tok" ]] || die "$f has no 'Token: <SYMBOL>' line"
  [[ -z "$want" || "$want" == "$tok" ]] || die "token $want is not this repo's award token $tok (one owner: $f)"
  echo "$tok"
}

# ---- GitHub, REST only --------------------------------------------------------------------------
# Every GitHub call of the scripts goes through these helpers: plain `gh api <rest path>` calls, so the
# scripts run wherever gh is logged in, including surfaces whose proxy blocks GraphQL (`gh issue`,
# `gh pr`, `gh label`, `gh project` and `gh api graphql` all fail there; only attached repos answer,
# 403 otherwise). All take owner/repo first and return non-zero on failure.
#
# Every READ is gh_get (one page) or gh_get_all (every page): the only `gh api` GET in the plugin. One REST
# quota (5,000/hour) is shared by every seat, the relay and the board of a login, so each read is conditional:
# the response's ETag (or Last-Modified) and body are kept in a disk cache per gh login,
# ~/.beast/cache/<login>/ (BEAST_CACHE_DIR moves the root), and the next read of the same URL sends
# If-None-Match; GitHub answers 304 without charging the quota and the cached body is served. GitHub stays
# the only truth: every read asks GitHub, and a body is served only on GitHub's own 304 for it. A write changes
# the resource's ETag, so the read after it is a 200 with the new body. Search has no ETag (measured
# 2026-10-15: `Cache-Control: no-cache`, no ETag header) and is never cached; it draws on its own quota (30/min).
# BEAST_CALL_LOG=<file> appends one line per HTTP request: "<UTC>	<status>	charged=yes|no	<resource>	<path>".

# beast_sha <text>: a hex digest of the text (sha256sum on Linux and recent macOS, shasum elsewhere).
if command -v sha256sum >/dev/null 2>&1; then beast_sha() { printf '%s' "$1" | sha256sum | cut -c1-40; }
else beast_sha() { printf '%s' "$1" | shasum -a 256 | cut -c1-40; }; fi

# gh_login: the login gh's token belongs to. A token belongs to one user for its whole life, so the answer is
# kept per token (by digest, never the token) under the cache root and asked of GitHub once per token.
gh_login() {
  local root tok f login t
  root="${BEAST_CACHE_DIR:-$HOME/.beast/cache}"
  tok="$(gh auth token 2>/dev/null)" || die "gh has no token: gh auth login (or GH_TOKEN)"
  f="$root/tokens/$(beast_sha "$tok")"
  if [[ -f "$f" ]]; then
    login="$(cat "$f")"
    [[ "$login" =~ ^[A-Za-z0-9-]+$ ]] || die "cache entry $f is corrupt (not a login: '$login'); delete it"
    echo "$login"; return 0
  fi
  login="$(gh_request "" user | jq -r .login)" || die "cannot read the gh login (gh auth status)"
  [[ "$login" =~ ^[A-Za-z0-9-]+$ ]] || die "GitHub answered GET user without a login"
  mkdir -p "$root/tokens"
  t="$(mktemp "$f.XXXXXX")"; printf '%s\n' "$login" > "$t" && mv -f "$t" "$f"
  echo "$login"
}

# gh_request <cache dir | ""> <path>: the one HTTP GET. With a cache dir: conditional on the cached entry,
# stores a 200 that carries an ETag or Last-Modified, serves the cached body on 304. Body on stdout; any other
# status, or a 200 whose body is not JSON, prints "daita-beast: gh GET <path> failed (…)" or "… truncated response
# from <path>" on stderr and returns 1. Entries are written to a temp file beside them and renamed (atomic).
gh_request() {
  local dir="$1" path="$2" f="" key raw err rc=0 t l1 l2 status hdrs body etag lm resource args=() c_etag="" c_lm="" bad=""
  if [[ -n "$dir" ]]; then
    key="$(beast_sha "GET $path")"; f="$dir/${key:0:2}/$key"
    if [[ -f "$f" ]]; then
      # An entry is: line 1 "BEAST-CACHE 1", line 2 the path, line 3 the ETag, line 4 Last-Modified, then the body.
      if ! { IFS= read -r l1 && IFS= read -r l2 && IFS= read -r c_etag && IFS= read -r c_lm; } < "$f"; then bad="shorter than its four header lines"
      elif [[ "$l1" != "BEAST-CACHE 1" ]]; then bad="line 1 is not 'BEAST-CACHE 1'"
      elif [[ "$l2" != "$path" ]]; then bad="it holds '$l2', not '$path'"
      elif [[ -z "$c_etag$c_lm" ]]; then bad="it has neither an ETag nor a Last-Modified"
      elif ! tail -n +5 "$f" | jq -e . >/dev/null 2>&1; then bad="its body is not JSON"
      fi
      if [[ -n "$bad" ]]; then
        echo "daita-beast: cache entry $f is corrupt ($bad); this read asks GitHub unconditionally and replaces it" >&2
        c_etag=""; c_lm=""
      fi
      [[ -z "$c_etag" ]] || args+=(-H "If-None-Match: $c_etag")
      [[ -n "$c_etag" || -z "$c_lm" ]] || args+=(-H "If-Modified-Since: $c_lm")
    fi
  fi
  raw="$(mktemp)"; err="$(mktemp)"
  gh api -i -X GET "$path" ${args[@]+"${args[@]}"} > "$raw" 2> "$err" || rc=$?
  status="$(head -1 "$raw" | tr -d '\r' | awk '{print $2}')"
  # `gh api -i` prints the status line, the headers (CRLF), a blank line, then the body.
  hdrs="$(awk 'NR > 1 { sub(/\r$/, ""); if ($0 == "") exit; print }' "$raw")"
  resource="$(awk -F': ' 'tolower($1)=="x-ratelimit-resource" {print $2}' <<< "$hdrs")"
  [[ -z "${BEAST_CALL_LOG:-}" ]] || printf '%s\t%s\tcharged=%s\t%s\t%s\n' "$(utc_now)" "${status:-none}" "$([[ "$status" == 304 ]] && echo no || echo yes)" "${resource:-?}" "$path" >> "$BEAST_CALL_LOG"
  case "$status" in
    200)
      body="$(awk 'b { print; next } { sub(/\r$/, "") } NR > 1 && $0 == "" { b = 1 }' "$raw")"
      rm -f "$raw" "$err"
      jq -e . >/dev/null 2>&1 <<< "$body" || { echo "daita-beast: gh GET $path: truncated response from $path (HTTP 200, ${#body} bytes that are not JSON; not cached, not used)" >&2; return 1; }
      etag="$(awk -F': ' 'tolower($1)=="etag" {print $2}' <<< "$hdrs")"
      lm="$(awk -F': ' 'tolower($1)=="last-modified" {print $2}' <<< "$hdrs")"
      if [[ -n "$f" && -n "$etag$lm" ]]; then
        mkdir -p "$(dirname "$f")"
        t="$(mktemp "$f.XXXXXX")"
        printf 'BEAST-CACHE 1\n%s\n%s\n%s\n%s\n' "$path" "$etag" "$lm" "$body" > "$t" && mv -f "$t" "$f"
      fi
      printf '%s\n' "$body" ;;
    304)
      rm -f "$raw" "$err"
      [[ -n "$f" && -f "$f" ]] || die "GET $path: GitHub answered 304 to a request that sent no validator"
      tail -n +5 "$f" ;;
    *)
      echo "daita-beast: gh GET $path failed (exit $rc, HTTP ${status:-none}): $(tr '\n' ' ' < "$err")" >&2
      rm -f "$raw" "$err"
      return 1 ;;
  esac
}

# gh_get <path[?query]>: one page of a REST GET, through the cache of the gh login. Body on stdout.
gh_get() {
  [[ $# -eq 1 ]] || die "gh_get takes one path (the query in it): got $*"
  local login; login="$(gh_login)" || exit 1
  gh_request "${BEAST_CACHE_DIR:-$HOME/.beast/cache}/$login" "$1"
}

# gh_get_all <path[?query]>: every page of a list endpoint as one JSON array, 100 per page, each page cached
# and validated on its own. A full page is followed by the next one (never the Link header, which a 304 does
# not refresh), so an appended item costs one charged page and the unchanged pages answer 304.
gh_get_all() {
  [[ $# -eq 1 ]] || die "gh_get_all takes one path (the query in it): got $*"
  local path="$1" sep='?' page=1 got n acc
  [[ "$path" != *\?* ]] || sep='&'
  acc="$(mktemp)"
  while :; do
    got="$(gh_get "$path${sep}per_page=100&page=$page")" || { rm -f "$acc"; return 1; }
    printf '%s\n' "$got" >> "$acc"
    n="$(jq 'length' <<< "$got")"
    [[ "$n" -eq 100 ]] || break
    page=$((page+1))
  done
  jq -s 'add // []' "$acc"; rm -f "$acc"
}

# gh_send_try <METHOD> <path> [gh field args]: the one WRITE (POST, PATCH, PUT, DELETE; never cached). The response body
# (JSON, or nothing for a 204) on stdout. When gh fails, or answers a body that is not JSON (a truncated response), it
# says so on stderr naming the call and returns 1, so a seat can tell a GitHub hiccup from a script fault.
gh_send_try() {
  local m="$1" p="$2" out err rc=0; shift 2
  [[ "$m" =~ ^(POST|PATCH|PUT|DELETE)$ ]] || die "gh_send: method '$m' is not a write (reads go through gh_get)"
  err="$(mktemp)"
  out="$(gh api -X "$m" "$p" "$@" 2>"$err")" || rc=$?
  [[ -z "${BEAST_CALL_LOG:-}" ]] || printf '%s\t%s\tcharged=yes\twrite\t%s %s\n' "$(utc_now)" "$([[ $rc -eq 0 ]] && echo ok || echo "exit$rc")" "$m" "$p" >> "$BEAST_CALL_LOG"
  if [[ $rc -ne 0 ]]; then echo "daita-beast: gh $m $p failed (exit $rc): $(tr '\n' ' ' < "$err")" >&2; rm -f "$err"; return 1; fi
  rm -f "$err"
  if [[ -n "$out" ]] && ! jq -e . >/dev/null 2>&1 <<< "$out"; then echo "daita-beast: gh $m $p: truncated response from $p (${#out} bytes that are not JSON)" >&2; return 1; fi
  printf '%s\n' "$out"
}

# gh_send <METHOD> <path> [gh field args]: gh_send_try, exiting on failure (the message is already on stderr).
gh_send() { gh_send_try "$@" || exit 1; }

# uri <text>: the text percent-encoded for a query value.
uri() { printf '%s' "$1" | jq -sRr @uri; }

# The owners (user or org part) of every repo the roster names: the roster repo, the board repo and
# each seat's repo. One per line. The roster is the one place that knows; no owner list is typed elsewhere.
roster_owners() {
  local r; r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  jq -r '[.repo, .board, (.seats[].repo)] | map(select(. != null) | split("/")[0]) | unique | .[]' "$r"
}

# The same owners as search terms: "user:a user:b" (a search without them competes with all of GitHub).
roster_user_terms() {
  local t="" o
  while IFS= read -r o; do [[ -n "$o" ]] && t="$t user:$o"; done < <(roster_owners)
  [[ -n "$t" ]] || die "roster $(roster_path) names no owner (repo, board, seats[].repo)"
  printf '%s' "${t# }"
}

user_login() { gh_login; }

user_exists() { gh_get "users/$1" >/dev/null 2>&1; }

# repo_permission <repo> <login>: admin|maintain|write|triage|read, or "none" (no access, or the
# caller may not read the collaborator list — both mean "may not award").
repo_permission() { local p; if p="$(gh_get "repos/$1/collaborators/$2/permission" 2>/dev/null)"; then jq -r .permission <<< "$p"; else echo none; fi; }

# issue_get <repo> <N>: the issue (or pull request) as JSON. Dies naming the issue when unreadable.
issue_get() {
  local err out; err="$(mktemp)"
  if out="$(gh_get "repos/$1/issues/$2" 2>"$err")"; then cat "$err" >&2; rm -f "$err"; printf '%s\n' "$out"; return 0; fi
  local first; first="$(head -1 "$err")"; rm -f "$err"
  die "$1#$2: cannot read (403 = repo not attached to this session or no access; 404 = no such issue): $first"
}

# issue_comments <repo> <N>: every comment, all pages, as one JSON array (REST shape: .user.login,
# .created_at, .html_url, .body).
issue_comments() { gh_get_all "repos/$1/issues/$2/comments"; }

# row_read <repo> <N>: {"issue": <the issue>, "comments": [<every comment>]}, the one read of a board row, a desk or
# any issue whose comments a script derives facts from (acks, events, the close words, asks). Both halves are
# conditional reads, so an unchanged row costs two uncharged 304s. There is no shortcut keyed by the issue's
# updated_at: editing a comment does not bump it (measured 2026-10-15), so a skipped read would serve an edited
# answer stale. The comments are never read with since=: a deleted comment is invisible to it (measured), and the
# per-page ETag already charges only the pages that changed.
row_read() {
  [[ $# -eq 2 ]] || die "row_read takes <repo> <N>, not $*"
  local issue comments
  issue="$(issue_get "$1" "$2")" || exit 1
  comments="$(issue_comments "$1" "$2")" || die "$1#$2: cannot read its comments"
  jq -s '{issue: .[0], comments: .[1]}' <(printf '%s\n' "$issue") <(printf '%s\n' "$comments")
}

# pr_reviews <repo> <N>: every review of a pull request, all pages, as one JSON array.
pr_reviews() { gh_get_all "repos/$1/pulls/$2/reviews"; }

# issue_comment <repo> <N> "<body>": post a comment; prints its html_url.
issue_comment() { gh_send POST "repos/$1/issues/$2/comments" -f body="$3" | jq -r .html_url; }

# comment_edit <repo> <comment-id> <body-file>: edit one issue comment in place; prints its html_url.
comment_edit() {
  [[ -f "$3" ]] || die "comment_edit: no body file $3"
  gh_send PATCH "repos/$1/issues/comments/$2" -F body=@"$3" | jq -r .html_url
}

# issue_create <repo> --title T --body-file F [--label L]... [--assignee A]... [--milestone <number>]: prints the issue's html_url.
issue_create() {
  local repo="$1"; shift
  local title="" body_file="" fields=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --body-file) body_file="$2"; shift 2 ;;
      --label) fields+=(-f "labels[]=$2"); shift 2 ;;
      --assignee) fields+=(-f "assignees[]=$2"); shift 2 ;;
      --milestone) [[ "$2" =~ ^[0-9]+$ ]] || die "issue_create: --milestone takes a milestone number, not '$2'"; fields+=(-F "milestone=$2"); shift 2 ;;
      *) die "issue_create: unknown argument $1" ;;
    esac
  done
  [[ -n "$title" && -n "$body_file" ]] || die "issue_create needs --title and --body-file"
  [[ -f "$body_file" ]] || die "issue_create: no body file $body_file"
  gh_send POST "repos/$repo/issues" -f title="$title" -F body=@"$body_file" ${fields[@]+"${fields[@]}"} | jq -r .html_url
}

# issue_close <repo> <N> [completed|not_planned]
issue_close() {
  local reason="${3:-completed}"
  case "$reason" in completed|not_planned) ;; *) die "issue_close: reason must be completed or not_planned, not '$reason'" ;; esac
  gh_send PATCH "repos/$1/issues/$2" -f state=closed -f state_reason="$reason" >/dev/null
}

# issue_add_labels <repo> <N> <label>...: adds labels to an issue or a pull request (one endpoint for both).
issue_add_labels() {
  local repo="$1" number="$2"; shift 2
  [[ $# -gt 0 ]] || die "issue_add_labels: no label given"
  local fields=() l
  for l in "$@"; do fields+=(-f "labels[]=$l"); done
  gh_send POST "repos/$repo/issues/$number/labels" "${fields[@]}" >/dev/null
}

# issue_remove_label <repo> <N> <label>: removes one label from an issue or a pull request.
issue_remove_label() {
  local enc; enc="$(printf '%s' "$3" | jq -sRr @uri)"
  gh_send DELETE "repos/$1/issues/$2/labels/$enc" >/dev/null
}

# repo_labels <repo>: every label definition of the repo, one name per line.
repo_labels() { gh_get_all "repos/$1/labels" | jq -r '.[].name'; }

# label_delete <repo> <name>: removes a label definition (and with it the label from every issue that carries it).
label_delete() {
  local enc; enc="$(printf '%s' "$2" | jq -sRr @uri)"
  gh_send DELETE "repos/$1/labels/$enc" >/dev/null
}

# issue_edit_body <repo> <N> <file>: replace the body with the file's contents.
issue_edit_body() {
  [[ -f "$3" ]] || die "issue_edit_body: no body file $3"
  gh_send PATCH "repos/$1/issues/$2" -F body=@"$3" >/dev/null
}

# label_ensure_template <repo> <name>: label_ensure with the color and description of templates/labels.json,
# the one owner of every fixed label's definition; dies when the template does not define <name>.
label_ensure_template() {
  local row; row="$(jq -r --arg n "$2" '.[] | select(.name == $n) | [.color, .description] | @tsv' "$BEAST_SCRIPTS/../templates/labels.json")"
  [[ -n "$row" ]] || die "label '$2' is not defined in $BEAST_SCRIPTS/../templates/labels.json"
  label_ensure "$1" "$2" "$(cut -f1 <<< "$row")" "$(cut -f2 <<< "$row")"
}

# issue_add_assignees <repo> <N> <login>...: assigns an issue or a pull request (one endpoint for both);
# dies when GitHub does not list every login as an assignee afterwards (a login without access is dropped silently by the API).
issue_add_assignees() {
  local repo="$1" number="$2"; shift 2
  [[ $# -gt 0 ]] || die "issue_add_assignees: no login given"
  local fields=() l got
  for l in "$@"; do fields+=(-f "assignees[]=$l"); done
  got="$(gh_send POST "repos/$repo/issues/$number/assignees" "${fields[@]}" | jq -r '[.assignees[].login] | join(" ")')" || die "$repo#$number: cannot assign $*"
  for l in "$@"; do [[ " $got " == *" $l "* ]] || die "$repo#$number: GitHub did not assign $l (assignees now: ${got:-none}; a login without access to the repo cannot be assigned)"; done
}

# label_ensure <repo> <name> <color> <description>: create the label, or update it in place when it exists.
label_ensure() {
  local repo="$1" name="$2" color="$3" desc="$4" enc made
  [[ ${#desc} -le 100 ]] || die "label '$name': description is ${#desc} characters, GitHub allows 100"
  # Create; GitHub refuses a name that exists (422), and then the definition is updated in place.
  if made="$(gh_send_try POST "repos/$repo/labels" -f name="$name" -f color="$color" -f description="$desc" 2>&1 >/dev/null)"; then return 0; fi
  enc="$(printf '%s' "$name" | jq -sRr @uri)"
  gh_send_try PATCH "repos/$repo/labels/$enc" -f new_name="$name" -f color="$color" -f description="$desc" >/dev/null \
    || die "cannot create or update label '$name' in $repo (create said: ${made:-nothing}; 403 = repo not attached to this session or no write access)"
}

# issues_list <repo> [-f key=value]...: GET repos/{r}/issues with the given query fields, all pages, as
# one JSON array. The endpoint returns pull requests too: an issues-only caller filters with
# `select(.pull_request == null)`.
issues_list() {
  local repo="$1" q=""; shift
  while [[ $# -gt 0 ]]; do
    [[ "$1" == -f && "${2:-}" == *=* ]] || die "issues_list: expected -f key=value, got '$1 ${2:-}'"
    q="$q&${2%%=*}=$(uri "${2#*=}")"; shift 2
  done
  gh_get_all "repos/$repo/issues${q:+?${q#&}}"
}

# issues_list_shows <repo> <N> [-f key=value]...: returns once issues_list with those fields lists #N; dies after 60 s.
# The issues list lags a create by seconds, labelled or not (measured 2026-10-15: a desk opened twice one second apart
# minted a duplicate; a labelled decision issue was missing from the list at +0 s and listed at +6 s, a plain read and
# the conditional read agreeing). A writer that dedupes by listing waits here after its create, so a rerun finds it.
issues_list_shows() {
  local repo="$1" n="$2" got; shift 2
  for _ in $(seq 1 30); do
    got="$(issues_list "$repo" "$@" | jq --argjson n "$n" '[.[].number] | index($n) != null')" || die "cannot list the issues of $repo"
    [[ "$got" != true ]] || return 0
    sleep 2
  done
  die "the issues list of $repo ($*) does not show the new #$n after 60 s; check it before rerunning, or a rerun files a second one"
}

# search_issues "<q>": REST search, newest-updated first, every page (fails loud past the API's 1000), as one JSON
# array of items (REST shape: .html_url, .state lowercase, .updated_at, .closed_at, .user.login,
# .labels[].name, .assignees[].login, .repository_url, .pull_request.merged_at). The caller's query
# carries `is:issue` or `is:pr` and the `user:<owner>` scope (roster_user_terms).
search_issues() {
  local q="$1" page=1 acc='[]' got n total
  [[ $# -eq 1 ]] || die "search_issues takes one query; a result cap would drop rows silently"
  while :; do
    got="$(gh_request "" "search/issues?q=$(uri "$q")&per_page=100&page=$page&sort=updated&order=desc")" || return 1
    total="$(jq .total_count <<< "$got")"
    [[ "$total" -le 1000 ]] || { echo "daita-beast: search '$q' matches $total items; the search API serves at most 1000: narrow the query (nothing is dropped silently)" >&2; return 1; }
    acc="$(jq -s '.[0] + .[1].items' <(printf '%s\n' "$acc") <(printf '%s\n' "$got"))"
    n="$(jq '.items | length' <<< "$got")"
    [[ "$n" -eq 100 ]] || break
    page=$((page+1))
  done
  printf '%s\n' "$acc"
}

# search_seat_issues <id> "<q>": search_issues for the rows waiting on a seat: one search per label of
# seat_label_terms, merged by URL, newest-updated first, every row (no cap). <q> carries everything but the seat label.
search_seat_issues() {
  [[ $# -eq 2 ]] || die "search_seat_issues takes <id> \"<q>\"; a result cap would drop rows silently"
  local id="$1" q="$2" acc='[]' got name terms
  terms="$(seat_label_terms "$id")" || exit 1
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    got="$(search_issues "$q label:\"$name\"")" || return 1
    acc="$(jq -s 'add | unique_by(.html_url)' <(printf '%s\n' "$acc") <(printf '%s\n' "$got"))"
  done <<< "$terms"
  jq 'sort_by(.updated_at) | reverse' <<< "$acc"
}

# pin_issue <repo> <N>: pinning exists only in GraphQL. Tries it; when it fails (GraphQL blocked on this
# surface, or the repo already has its 3 pins) says so on stderr and returns 0: the issue exists either way.
pin_issue() {
  local node_id
  if node_id="$(issue_get "$1" "$2" 2>/dev/null | jq -r .node_id)" \
     && gh_send_try POST graphql -f query='mutation($id:ID!){ pinIssue(input:{issueId:$id}){ issue { number } } }' -F id="$node_id" >/dev/null; then
    return 0
  fi
  echo "daita-beast: warning: $1#$2 not pinned: pinning needs GraphQL (unavailable on this surface) or the repo has 3 pins already; pin by hand" >&2
  return 0
}

# project_cmd <args...>: the one `gh project` call site. GitHub Projects have no REST API, so on a
# surface without GraphQL this dies naming the fact instead of guessing.
project_cmd() {
  local err what; err="$(mktemp)"; what="project ${1:-}"
  if gh project "$@" 2>"$err"; then rm -f "$err"; return 0; fi
  local first; first="$(head -1 "$err")"; rm -f "$err"
  die "GitHub Projects need GraphQL, unavailable on this surface (gh $what: $first)"
}

# ---- the queue: answers, acks, events (one owner; the page's answerKind/deriveRow are the JS twins) ----

# answer_kind "<body>" "<phrase>": approve | revise | reject | "" — the decider's four forms, first line only.
answer_kind() {
  local b; b="$(printf '%s' "$1" | sed -n '1p' | sed 's/[[:space:]]*$//')"
  local phrase="$2"
  if [[ "$b" == "$phrase" || "$b" == "$phrase — "* ]] || [[ "$b" =~ ^[Aa]pproved?$ ]]; then echo approve
  elif [[ "$b" =~ ^reject:[[:space:]]*[^[:space:]] ]]; then echo reject
  elif [[ "$b" =~ ^revise:[[:space:]]*[^[:space:]] ]]; then echo revise
  else echo ""; fi
}

# seat_acks <row>: (a row_read result) one line per seat id, "<id>\t<at>\t<state>\t<url>", the NEWEST well-formed BEAST-ACK
# by that seat (first line, or the last non-empty line of a close comment). The seat is a qualified id, or a
# bare label (comments written before the 2026-10-15 relabel), read as <the comment author's login>/<LABEL>:
# a comment is posted by the seat's own login, so it names its seat without any roster. A line that starts
# with BEAST-ACK and does not match the shape is named on stderr and dropped.
seat_acks() {
  [[ $# -eq 1 ]] || die "seat_acks takes one row (row_read), not $*"
  local closed_at; closed_at="$(jq -r '.issue.closed_at // ""' <<< "$1")"
  jq '.comments' <<< "$1" | jq -r --arg closed "$closed_at" --arg seat "$SEAT_TOKEN_RE" '
    def lastline: (split("\n") | map(select(test("\\S"))) | last // "");
    def firstline: (split("\n")[0]);
    def ack(l): (l | capture("^BEAST-ACK seat=(?<seat>" + $seat + ") at=(?<at>[^ ]+) state=(?<state>seen|executed|blocked)") // null);
    # A close comment names its closer: "Closed by seat X at T" is X'"'"'s seen ack at T (the same fact, the shape the close has always carried).
    # The close comment is the closer'"'"'s seen ack AT THE CLOSE: its time is the issue'"'"'s closed_at (the comment lands seconds before the close).
    def closer(b): (b | capture("Closed by seat (?<seat>" + $seat + ") at (?<at>[0-9T:Z-]+)\\.") // null | if . == null then null else {seat:.seat, at:(if $closed != "" then $closed else .at end), state:"seen"} end);
    .[] | . as $c | ((.body // "") | firstline) as $f | ((.body // "") | lastline) as $l
      | (closer(.body // "") // ack($f) // ack($l)) as $a
      | if $a != null then "\(if ($a.seat | contains("/")) then $a.seat else "\($c.user.login)/\($a.seat)" end)\t\($a.at)\t\($a.state)\t\($c.html_url)"
        elif ($f | startswith("BEAST-ACK")) or ($l | startswith("BEAST-ACK")) then "BAD\t\($c.html_url)"
        else empty end' \
  | while IFS=$'\t' read -r a b c d; do
      if [[ "$a" == "BAD" ]]; then echo "daita-beast: malformed BEAST-ACK line dropped: $b" >&2; continue; fi
      a="$(seat_resolve "$a")" || { echo "daita-beast: BEAST-ACK dropped: $d" >&2; continue; }
      printf '%s\t%s\t%s\t%s\n' "$a" "$b" "$c" "$d"
    done \
  | sort -t$'\t' -k1,1 -k2,2 | awk -F'\t' '{ last[$1] = $0; if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 } } END { for (i = 1; i <= n; i++) print last[order[i]] }'
}

# approve_phrase "<body>": the first double-quoted phrase of the body's '## Approve with' section, or nothing.
approve_phrase() { { printf '%s\n' "$1" | section "Approve with" | grep -o '"[^"]*"' || true; } | head -1 | tr -d '"'; }

# row_phrase <who> <issue-json>: a row's approving phrase. The first quoted phrase of the body's '## Approve
# with'; a pull request without one approves with "approve" (named on stderr only when it has the section
# but no quoted phrase in it); a decision issue without one is named on stderr and gets nothing (a bare
# approve/approved, revise: and reject: still count).
row_phrase() {
  local who="$1" info="$2" body p
  body="$(jq -r '.body // ""' <<< "$info")"
  p="$(approve_phrase "$body")"
  if [[ -n "$p" ]]; then echo "$p"; return 0; fi
  if jq -e '.pull_request != null' <<< "$info" >/dev/null; then
    [[ -z "$(printf '%s\n' "$body" | section "Approve with" | sed '/^[[:space:]]*$/d')" ]] \
      || echo "daita-beast: $who: the PR's '## Approve with' carries no quoted phrase; it approves with \"approve\"" >&2
    echo approve; return 0
  fi
  echo "daita-beast: $who: '## Approve with' carries no quoted phrase; bare approve/revise:/reject: still count" >&2
}

# The amend line: the one line publish.sh request --amend posts on a publish row after it force-updates the PR branch.
# One owner of its shape: amend_line writes it, row_amended_at reads it.
#   Amended at <UTC>: <n> files; added <list>; removed <list>; changed <list>
AMEND_LINE_RE='^Amended at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z: '

# amend_line <n files> <added> <removed> <changed>: the line, the lists already joined and truncated ("none" when empty).
amend_line() { printf 'Amended at %s: %s files; added %s; removed %s; changed %s' "$(utc_now)" "$1" "$2" "$3" "$4"; }

# row_amended_at <row>: (a row_read result) the created_at of the row's newest comment whose first line is an amend line,
# or nothing. Any author counts: a stray amend line only makes an earlier approval read as stale (the safe direction).
row_amended_at() {
  jq -r --arg re "$AMEND_LINE_RE" '[.comments[] | select(((.body // "") | split("\n")[0]) | test($re)) | .created_at] | sort | last // empty' <<< "$1"
}

# row_answer_url <row> <phrase> <approve|reject|revise>: (a row_read result) the URL of the decider's standing answer when it
# is of that kind, else nothing. The standing answer is the newest comment by an assignee of the row whose first line is an
# answer form (answer_kind): an approve followed by a revise is not an approval. An approve no newer than the row's latest
# amend line (row_amended_at) approved what the amend replaced: it reads as not approved, named on stderr with the amend
# time. The one reader of "the decider answered this row so" (publish.sh merge, wrapup.sh run).
row_answer_url() {
  [[ $# -eq 3 ]] || die "row_answer_url takes <row> <phrase> <kind>, not $*"
  case "$3" in approve|reject|revise) ;; *) die "row_answer_url: kind is approve, reject or revise, not '$3'" ;; esac
  local row="$1" phrase="$2" want="$3" a login at u b k last_u="" last_k="" last_at="" amended
  a="$(jq -r '[.issue.assignees[].login] | join(" ")' <<< "$row")" || die "row_answer_url: not a row_read result"
  while IFS=$'\t' read -r login at u b; do
    [[ -n "$login" && " $a " == *" $login "* ]] || continue
    k="$(answer_kind "$b" "$phrase")"; [[ -n "$k" ]] || continue
    last_u="$u"; last_k="$k"; last_at="$at"
  done < <(jq -r '.comments | sort_by(.created_at)[] | [.user.login, .created_at, .html_url, ((.body // "") | split("\n")[0])] | @tsv' <<< "$row")
  [[ "$last_k" == "$want" ]] || return 0
  amended="$(row_amended_at "$row")"
  if [[ "$want" == approve && -n "$amended" && ! "$last_at" > "$amended" ]]; then
    echo "daita-beast: the approval $last_u ($last_at) predates the amend at $amended: not approved; the decider approves again on the row, after the amend" >&2
    return 0
  fi
  echo "$last_u"
}

# RECORD_PATH_RE: the dated records' directory (an ERE and a Python regex alike). The publish scrub refuses it in what
# leaves the twin; wrapup.sh plan deletes the record files a closed row names under it. One owner of the shape.
RECORD_PATH_RE='(org|docs)/records/'

# The words class (scrub_scan): a closed row's words hit only as a stretch of WORDS_MIN consecutive words of which at
# least WORDS_MIN_RARE are outside WORDS_COMMON (English stopwords and the protocol's verbs). A word is a WORDS_TOKEN_RE
# match (a Python regex: letters and digits, so whitespace and punctuation only separate words), compared casefolded.
# One owner of the rule: roster_scrub reads it to check scrub_allow_words, scrub_scan to match.
WORDS_MIN=5
WORDS_MIN_RARE=2
WORDS_TOKEN_RE='[^\W_]+'
WORDS_COMMON="a about above after again against all am an and any are as at be because been before being below between both but by can could did do does doing down during each few for from further had has have having he her here hers herself him himself his how i if in into is it its itself just me more most my myself no nor not now of off on once only or other our ours ourselves out over own same she should so some such than that the their theirs them themselves then there these they this those through to too under until up very was we were what when where which while who whom why will with would you your yours yourself yourselves approve publish merge close revise reject record"

# roster_scrub [roster]: the one parser of the roster's "scrub", "scrub_allow" and "scrub_allow_words". Prints JSON
# {"scrub": [{"pattern": <regex>, "paths": [<glob>...] | null}], "allow": [<bare name>...], "allow_words": [<phrase>...]}.
# A "scrub" entry is a regex string (every text file, path name, commit message and body) or {"pattern": <regex>, "paths":
# [<glob>, ...]} (only text files and path names whose public path matches a glob: Python fnmatch on the whole path, `*`
# crossing `/`). A "scrub_allow" entry is a private repo's bare name that is also an ordinary word: the bare-name class
# skips exactly it. A "scrub_allow_words" entry is an exact phrase of closed-row words that may publish: the words class
# drops every stretch inside it, and nothing else. Dies naming the first malformed entry: another type, another key, an
# empty pattern or paths list, a regex Python cannot compile, an allow entry that is not a bare repo name, an allowed
# phrase that is not one line of at least WORDS_MIN words (shorter, it could never match).
roster_scrub() {
  local r="${1:-}"; [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  python3 -I - "$r" "$WORDS_TOKEN_RE" "$WORDS_MIN" <<'PY' || exit 1
import json, re, sys
r, tok_re, wmin = sys.argv[1], re.compile(sys.argv[2]), int(sys.argv[3])
def die(m): sys.exit("daita-beast: roster %s: %s" % (r, m))
R = json.load(open(r, encoding="utf-8"))
out = {"scrub": [], "allow": [], "allow_words": []}
s = R.get("scrub", [])
if not isinstance(s, list): die("\"scrub\" is a list of entries, got %s" % json.dumps(s))
for i, e in enumerate(s):
    where = "scrub[%d] %s" % (i, json.dumps(e))
    if isinstance(e, str): pat, paths = e, None
    elif isinstance(e, dict):
        extra = sorted(set(e) - {"pattern", "paths"})
        if extra: die("%s: unknown key(s) %s; an entry is a regex string or {\"pattern\": <regex>, \"paths\": [<glob>, ...]}" % (where, ", ".join(extra)))
        pat, paths = e.get("pattern"), e.get("paths")
        if not isinstance(paths, list) or not paths or not all(isinstance(g, str) and g for g in paths):
            die("%s: \"paths\" is a non-empty list of globs (a pattern for every text file is a plain string)" % where)
    else: die("%s: an entry is a regex string or {\"pattern\": <regex>, \"paths\": [<glob>, ...]}" % where)
    if not isinstance(pat, str) or not pat: die("%s: \"pattern\" is a non-empty regex string" % where)
    try: re.compile(pat)
    except re.error as x: die("%s: the regex /%s/ does not compile: %s" % (where, pat, x))
    out["scrub"].append({"pattern": pat, "paths": paths})
a = R.get("scrub_allow", [])
if not isinstance(a, list): die("\"scrub_allow\" is a list of bare repo names, got %s" % json.dumps(a))
for i, n in enumerate(a):
    if not isinstance(n, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", n):
        die("scrub_allow[%d] %s: an entry is a private repo's bare name (no owner, no /), exact case" % (i, json.dumps(n)))
    out["allow"].append(n)
w = R.get("scrub_allow_words", [])
if not isinstance(w, list): die("\"scrub_allow_words\" is a list of exact phrases, got %s" % json.dumps(w))
for i, p in enumerate(w):
    where = "scrub_allow_words[%d] %s" % (i, json.dumps(p))
    if not isinstance(p, str) or "\n" in p or not p.strip(): die("%s: an entry is a one-line phrase (a string)" % where)
    n = len(tok_re.findall(p))
    if n < wmin: die("%s: %d word(s); the words class matches stretches of %d words, so a shorter phrase could never be allowed" % (where, n, wmin))
    out["allow_words"].append(p)
print(json.dumps(out))
PY
}

# roster_license [roster]: the one parser of the roster's "license": the license every public repo of the roster's owners
# carries. Prints it as compact JSON {"name", "file", "manifest", "source": {"repo", "path", "render" | null, "checkout" |
# null}}, or nothing when the roster has no "license". Dies naming the first malformed part: not an object, an unknown
# key, a missing or empty string, a name that cannot sit in one HTML comment line, a file that is not a plain relative
# path, a source repo that is not owner/repo, a checkout that is not an absolute path.
roster_license() {
  local r="${1:-}"; [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  python3 -I - "$r" <<'PY' || exit 1
import json, re, sys
r = sys.argv[1]
def die(m): sys.exit("daita-beast: roster %s: \"license\": %s" % (r, m))
R = json.load(open(r, encoding="utf-8"))
if "license" not in R: sys.exit(0)
L = R["license"]
if not isinstance(L, dict): die("is an object {\"name\", \"file\", \"manifest\", \"source\"}, got %s" % json.dumps(L))
def keys(o, allowed, where):
    extra = sorted(set(o) - set(allowed))
    if extra: die("%sunknown key(s) %s; allowed: %s" % (where + ": " if where else "", ", ".join(extra), ", ".join(allowed)))
def text(o, k, where, required=True):
    v = o.get(k)
    if v is None and not required: return None
    if not isinstance(v, str) or not v.strip() or "\n" in v: die("%s%s is a non-empty one-line string, got %s" % (where + "." if where else "", k, json.dumps(v)))
    return v
keys(L, ["name", "file", "manifest", "source", "vendored"], "")
name, f, man = text(L, "name", ""), text(L, "file", ""), text(L, "manifest", "")
if "--" in name: die("name %s: it sits in one HTML comment line, so it may not carry \"--\"" % json.dumps(name))
if f.startswith("/") or any(p in ("", ".", "..") for p in f.split("/")): die("file %s: a plain path relative to a repo's root" % json.dumps(f))
S = L.get("source")
if not isinstance(S, dict): die("source is an object {\"repo\", \"path\", \"render\"?, \"checkout\"?}, got %s" % json.dumps(S))
keys(S, ["repo", "path", "render", "checkout"], "source")
repo, path = text(S, "repo", "source"), text(S, "path", "source")
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo): die("source.repo %s: owner/repo" % json.dumps(repo))
if path.startswith("/") or any(p in ("", ".", "..") for p in path.split("/")): die("source.path %s: a plain path relative to the source repo's root" % json.dumps(path))
render, co = text(S, "render", "source", False), text(S, "checkout", "source", False)
if co is not None and not co.startswith("/"): die("source.checkout %s: an absolute path (a checkout of %s on this machine)" % (json.dumps(co), repo))
V = L.get("vendored", [])
if not isinstance(V, list) or not all(isinstance(v, str) and v.strip() and "\n" not in v and not v.startswith("/") and not any(p in ("", ".", "..") for p in v.rstrip("/").split("/")) for v in V):
    die("vendored is a list of plain directory paths relative to a repo's root (copies of upstream packages whose manifests are not ours), got %s" % json.dumps(V))
print(json.dumps({"name": name, "file": f, "manifest": man, "source": {"repo": repo, "path": path, "render": render, "checkout": co}, "vendored": [v.rstrip("/") for v in V]}))
PY
}

# ---- the scrub gate: the one owner of what may not leave a private twin ----------------------------
# scrub_patterns derives the facts, scrub_scan matches them; publish.sh (a publish's commit, body, release notes) and
# license.sh (a license file's header) both run them. The classes are listed in docs/protocol.md, Publishing.

# roster_repo_owners [roster]: every owner of a repo the roster names (repo, publishes_to, board, seat repos, tracking refs),
# one per line, each once (case-insensitively). The scrub lists their private repos; license.sh audit their public ones.
roster_repo_owners() {
  local r="${1:-}"; [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  jq -r '[.repo, .publishes_to, .board, (.seats[]?.repo), (.seats[]?.tracking | select(. != null) | split("#")[0])] | map(select(. != null and contains("/")) | split("/")[0]) | unique_by(ascii_downcase) | .[]' "$r"
}

# scrub_patterns [roster]: the pattern bag, JSON {bag, slugs: [...], names: [...], skipped: [...], words: [{url, words}],
# allow_words: [...], roster: [{pattern, paths}], record_re}: the facts the scanner matches, derived from the roster (the
# repo's own by default) and GitHub (every read through gh_get, so a warm cache costs no quota). names are the bare names
# checked (exact case, 5 characters or more, not in the roster's scrub_allow); skipped the bare names left out, whose slug
# form is still checked. words are the verbatim close words of the twin's closed rows, except a row whose close words are
# exactly its own approving phrase (its '## Approve with', approve_phrase): that phrase is the protocol's, not the decider's.
scrub_patterns() {
  local roster="${1:-}" twin pub slugs="" names="" r o type me words rows n body excl priv lab rs list phrase
  [[ -n "$roster" ]] || roster="$(roster_path)"
  [[ -f "$roster" ]] || die "no roster at $roster"
  twin="$(jq -r '.repo // empty' "$roster")"
  [[ "$twin" =~ ^[^/]+/[^/]+$ ]] || die "roster $roster has no \"repo\" (owner/repo), got '$twin'"
  pub="$(jq -r '.publishes_to // empty' "$roster")"
  rs="$(roster_scrub "$roster")" || exit 1
  excl="$(jq -r --arg p "$pub" '[$p] + [(.public_intended // [])[] | select(contains("/"))] | map(ascii_downcase) | .[]' "$roster")"
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
  done < <(roster_repo_owners "$roster")
  slugs="$(printf '%s' "$slugs" | sed '/^$/d' | while IFS= read -r r; do grep -qxF -- "$(tr 'A-Z' 'a-z' <<< "$r")" <<< "$excl" || echo "$r"; done | sort -fu)"
  # the bare names: those of the slugs that remain (the public target and exact public_intended entries are excluded above)
  names="$(sed 's#^[^/]*/##' <<< "$slugs" | sort -u)"
  # the words of every closed row of the twin (decision rows and PRs on the board), less a close on the row's own phrase
  words='[]'
  for lab in decision needs-review; do
    list="$(issues_list "$twin" -f labels="$lab" -f state=closed)" || die "cannot list the closed $lab rows of $twin"
    rows="$(jq -r '.[].number' <<< "$list")"
    for n in $rows; do
      phrase="$(approve_phrase "$(jq -r --argjson n "$n" '.[] | select(.number == $n) | .body // ""' <<< "$list")")"
      body="$(issue_comments "$twin" "$n" | jq -c --arg u "https://github.com/$twin/issues/$n" --arg p "$phrase" '
        [.[] | (.body // "") | capture("^(Closed|Rejected) on the word, verbatim: \"(?<w>.*)\"\n\nRecord: "; "p")? | select($p == "" or .w != $p) | {url: $u, words: .w}]')" \
        || die "cannot read the comments of $twin#$n"
      words="$(jq -c -s 'add' <(printf '%s\n' "$words") <(printf '%s\n' "$body"))"
    done
  done
  jq -n --arg s "$slugs" --arg nm "$names" --argjson w "$words" --argjson rs "$rs" --arg rec "$RECORD_PATH_RE" '
    ($nm | split("\n") | map(select(length > 0)) | unique) as $all
    | ($all | map(select(length >= 5 and (. as $n | $rs.allow | index($n) | not)))) as $chk
    | {bag: "beast-scrub-patterns/1", slugs: ($s | split("\n") | map(select(length > 0))), names: $chk, skipped: ($all - $chk),
       words: ($w | unique_by(.words)), allow_words: $rs.allow_words, roster: $rs.scrub, record_re: $rec}'
}

# scrub_scan <root> <patterns file> <base> <branch> <body file> [<format> [<tree dir> [<paths file>]]]: the scanner, the one
# matcher of every class. Exit 0 clean, 1 on any hit, 2 on a malformed pattern bag or a scanner fault (never read as clean).
#   diff mode   with a <branch>: the diff <base>..<branch> in the git tree <root> (the caller owns the branch's shape:
#               publish_base, publish.sh) and the messages of the commits <base>..<branch>
#   tree mode   with a <tree dir> (and empty <base> and <branch>): every file under it (.git excepted), whole
#   body        the body file, when given
#   paths file  one path per line: the diff or the tree is read only under those paths
#   format      human (the default: a header, "  <where>:<line>: <class text>: <match>" per hit, or a pass line) or
#               contract, publish.sh scan's stable shape: per hit "<file>:<line> <class> <match>" ("<path>:0 path-name
#               <match>" for a path, "commit-message <class> <match>" for a message, "body:<line> <class> <match>"),
#               nothing else on stdout. Classes: private-repo private-name local-path record-path roster-scrub
#               beast-line words path-name.
#   content classes  read every added line (diff) or every line (tree) of every TEXT file; a binary file (a NUL byte in its
#                    first 8000 bytes, git's own test) is not read, and each one skipped is named on stderr
#   path name        every added or changed path (diff) or every path (tree): a secret-shaped file name, a private repo
#                    slug or name, a roster pattern (a scoped one only on the paths its globs match)
scrub_scan() {
  local root="$1" pat="$2" base="$3" br="$4" body="$5" fmt="${6:-human}" tree="${7:-}" paths="${8:-}" rc=0
  case "$fmt" in human|contract) ;; *) echo "daita-beast: scrub_scan: format is human or contract, not '$fmt'" >&2; return 2 ;; esac
  ( cd "$root" && python3 -I - "$pat" "$base" "$br" "$body" "$fmt" "$tree" "$paths" "$WORDS_TOKEN_RE" "$WORDS_MIN" "$WORDS_MIN_RARE" "$WORDS_COMMON" ) <<'PY' || rc=$?
import codecs, fnmatch, json, os, re, subprocess, sys
pat_file, base, br, body, fmt, tree, paths_file, tok_re, wmin, wrare, common = sys.argv[1:12]
def fail(m):
    print("daita-beast: scrub: %s" % m, file=sys.stderr); sys.exit(2)
try:
    P = json.load(open(pat_file, encoding="utf-8"))
except Exception as x:
    fail("the pattern bag %s is not JSON: %s" % (pat_file, x))
SHAPE = {"slugs": list, "names": list, "skipped": list, "words": list, "allow_words": list, "roster": list, "record_re": str}
if not isinstance(P, dict) or P.get("bag") != "beast-scrub-patterns/1":
    fail("%s is not a pattern bag (\"bag\": \"beast-scrub-patterns/1\"; publish.sh scan --dump-patterns writes one)" % pat_file)
for k, t in SHAPE.items():
    if not isinstance(P.get(k), t): fail("the pattern bag %s: \"%s\" is missing or not a %s" % (pat_file, k, t.__name__))
try:
    want_paths = [l.strip().strip("/") for l in open(paths_file, encoding="utf-8") if l.strip()] if paths_file else []
    def git(*a):
        return subprocess.run(["git", *a], check=True, capture_output=True).stdout
    rules = []   # (class id, class text, compiled regex, path globs or None for every text)
    for s in P["slugs"]:
        rules.append(("private-repo", "private repo " + s, re.compile(r"(?<![A-Za-z0-9_.-])" + re.escape(s) + r"(?![A-Za-z0-9_-])", re.I), None))
    for n in P["names"]:   # exact case: a repo's own name, never the English word it may also be
        rules.append(("private-name", "private repo name " + n, re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(n) + r"(?![A-Za-z0-9_-])"), None))
    rules.append(("local-path", "local path", re.compile(r"(?<![A-Za-z0-9_.~-])/(Users|home)/[A-Za-z0-9._-]+/"), None))
    rules.append(("record-path", "record path", re.compile(P["record_re"]), None))
    for e in P["roster"]:   # parsed and compiled once already by roster_scrub (lib.sh)
        rules.append(("roster-scrub", "roster scrub /%s/%s" % (e["pattern"], "" if e["paths"] is None else " in " + ",".join(e["paths"])), re.compile(e["pattern"]), e["paths"]))
    def applies(globs, path):
        return globs is None or (path is not None and any(fnmatch.fnmatchcase(path, g) for g in globs))
    SECRET_NAMES = ["wallet.json", ".env", ".env.*", "*.pem", "*.key", "id_rsa*", "id_ed25519*", "*.p12", "*.pfx", "keystore*.json", "credentials*.json"]
    beast_line = re.compile(r"^[\s>`'\"*#-]*BEAST-[A-Z]+(\s|$)")
    # the words class (WORDS_* in lib.sh): stretches of wmin consecutive words with at least wrare outside the common list
    TOK, WMIN, WRARE, COMMON = re.compile(tok_re), int(wmin), int(wrare), set(common.split())
    def words(t): return [w.casefold() for w in TOK.findall(t)]
    def grams(ws, rare=True):
        for i in range(len(ws) - WMIN + 1):
            g = tuple(ws[i:i + WMIN])
            if not rare or sum(1 for w in g if w not in COMMON) >= WRARE: yield g
    windows = {}
    for w in P["words"]:
        for g in grams(words(w["words"])): windows.setdefault(g, w["url"])
    for a in P["allow_words"]:   # the roster's scrub_allow_words: every stretch inside the phrase, and nothing else
        for g in grams(words(a), rare=False): windows.pop(g, None)
    hits = []   # (where, line or None, class id, class text, match); where is a file, "commit <sha>" or "body"
    def scan(where, lineno, line, path=None, kind="file"):
        for cid, cls, rx, globs in rules:
            if not applies(globs, path): continue
            m = rx.search(line)
            if m: hits.append((kind, where, lineno, cid, cls, m.group(0)))
        if beast_line.search(line) and not re.search(r"[<$]", line):
            hits.append((kind, where, lineno, "beast-line", "BEAST- line", line.strip()[:80]))
        for g in grams(words(line)):
            u = windows.get(g)
            if u:
                hits.append((kind, where, lineno, "words", "words of " + u, " ".join(g))); break
    def scan_path(path):
        leaf = path.rsplit("/", 1)[-1].lower()
        for g in SECRET_NAMES:
            if fnmatch.fnmatchcase(leaf, g): hits.append(("path", path, None, "path-name", "path name: secret-shaped file name (%s)" % g, leaf)); break
        for cid, cls, rx, globs in rules:
            if not applies(globs, path): continue
            m = rx.search(path)
            if m: hits.append(("path", path, None, "path-name", "path name: " + cls, m.group(0)))
    binaries = set()
    def is_binary(data): return b"\0" in data[:8000]
    def scan_text(path, data):
        for i, l in enumerate(data.decode("utf-8", "replace").split("\n"), 1): scan(path, i, l, path)
    spec = ["--", *want_paths] if want_paths else []
    if tree:
        for top, dirs, files in os.walk(tree):
            dirs[:] = sorted(d for d in dirs if d != ".git")
            for f in sorted(files):
                rel = os.path.relpath(os.path.join(top, f), tree).replace(os.sep, "/")
                if want_paths and not any(rel == p or rel.startswith(p + "/") for p in want_paths): continue
                scan_path(rel)
                data = open(os.path.join(top, f), "rb").read()
                if is_binary(data): binaries.add(rel)
                else: scan_text(rel, data)
    elif br:
        # the files the diff adds or changes (a deletion publishes no content), unquoted
        raw = git("diff", "--raw", "-z", "--no-abbrev", "--no-renames", base, br, *spec).split(b"\0")
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
                if is_binary(data): binaries.add(p)
        for p, _, _ in changed: scan_path(p)
        # the added lines of the text files, with their new line numbers
        diff = git("-c", "core.quotePath=false", "diff", "-U0", "--text", "--no-color", "--no-ext-diff", "--no-renames", base, br, *spec).decode("utf-8", "replace")
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
        # the messages of the commits base..branch, and the root's too when base is the branch's own root (an orphan publish)
        for sha in git("rev-list", br if git("rev-list", "--max-parents=0", br).decode().strip() == base else base + ".." + br).decode().split():
            msg = git("log", "-1", "--format=%B", sha).decode("utf-8", "replace")
            for i, l in enumerate(msg.split("\n"), 1): scan("commit %s message" % sha[:12], i, l, None, "message")
    for p in sorted(binaries):
        print("scrub: binary file %s not scanned for content (a NUL byte in its first 8000 bytes); its path name was checked" % p, file=sys.stderr)
    if body:
        for i, l in enumerate(open(body, encoding="utf-8").read().split("\n"), 1): scan("body", i, l, None, "body")
except SystemExit:
    raise
except Exception as x:
    fail("the scanner failed (%s: %s); nothing is known clean" % (type(x).__name__, x))
what = br or tree or body
if fmt == "contract":
    for kind, where, ln, cid, cls, m in hits:
        m = m.replace("\n", " ")
        if kind == "message": print("commit-message %s %s" % (cid, m))
        elif kind == "path": print("%s:0 %s %s" % (where, cid, m))
        else: print("%s:%d %s %s" % (where, ln, cid, m))
    print("scrub: %s (%s: %d hit(s))" % ("clean" if not hits else "HITS", what, len(hits)), file=sys.stderr)
    sys.exit(1 if hits else 0)
if hits:
    print("scrub: %d hit(s) on %s; nothing of this leaves the twin:" % (len(hits), what))
    for kind, where, ln, cid, cls, m in hits:
        if kind == "path": print("  %s: %s: %s" % (where, cls, m))
        elif cid == "beast-line": print("  %s:%d: BEAST- line: %s" % (where, ln, m))
        elif cid == "words": print("  %s:%d: %s: \"%s\"" % (where, ln, cls, m))
        else: print("  %s:%d: %s: %s" % (where, ln, cls, m))
    sys.exit(1)
print("scrub: clean (%s from %s: %d private repo slugs, %d private repo names (%d short or allowed left to their slugs), %d closed rows' words, %d roster patterns checked; %d binary file(s) not read)" % (what, base[:12] or "-", len(P["slugs"]), len(P["names"]), len(P["skipped"]), len(P["words"]), len(P["roster"]), len(binaries)))
PY
  return $rc
}

# ---- rows: the board's two kinds (decision issues, pull requests for review) and the desks ----------
# The labels a row carries, one owner. A search term "label:a,b" matches either (measured 2026-10-15).
BOARD_ROW_LABELS="decision,needs-review"        # the board, the decided table, decision.sh inbox
RELAY_ROW_LABELS="decision,needs-review,desk"   # watch.sh: every row a seat hears about

# roster_decider: the login of the roster's people[] row whose role names "owner"; dies unless exactly one.
roster_decider() {
  local r got; r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  got="$(jq -r '[.people[]? | select((.role // "") | test("\\bowner\\b"; "i")) | .github] | join(" ")' "$r")"
  [[ -n "$got" ]] || die "roster $r: no people[] row has a role naming \"owner\"; pass the decider with --assignee"
  [[ "$got" != *" "* ]] || die "roster $r: several people[] rows name \"owner\" ($got); pass the decider with --assignee"
  echo "$got"
}

# ---- coordination stays private: the one owner ---------------------------------------------------
# A public product has a private twin (the roster's "repo"; "publishes_to" names the public repo). Every
# coordination write (decision rows, desks, tracking issues, status, notes, acks, review requests, the board)
# goes to a private repo; a public or public-intended repo receives only publishes. Readers still read public
# repos' existing rows, so history renders; only writes are refused, here, before the first API write.

# roster_repo: the roster's own "repo": the private home repo of the seats working from this checkout.
roster_repo() {
  local r v; r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  v="$(jq -r '.repo // empty' "$r")"
  [[ "$v" =~ ^[^/]+/[^/]+$ ]] || die "roster $r has no \"repo\" (owner/repo), got '$v'"
  echo "$v"
}

# repo_public_why <repo> [roster]: one line saying why <repo> is public ("listed in the roster's public_intended
# (<entry>)" or "public on GitHub"), or nothing when it is private and not public-intended. The roster is read
# first (a repo that does not exist yet is public-intended by its owner's entry); then GitHub's visibility. Names
# compare case-insensitively, as GitHub's do. Dies when <repo> is not owner/repo or its visibility cannot be read.
repo_public_why() {
  local r="$1" roster="${2:-}" hit priv
  [[ "$r" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "'$r' is not owner/repo"
  [[ -n "$roster" ]] || roster="$(roster_path)"
  hit="$(jq -r --arg r "$r" '($r | ascii_downcase) as $lr | ($lr | split("/")[0]) as $lo
    | [(.public_intended // [])[] | select((ascii_downcase == $lr) or (ascii_downcase == $lo))] | first // empty' "$roster")" \
    || die "cannot read \"public_intended\" of the roster $roster"
  if [[ -n "$hit" ]]; then echo "listed in the roster's public_intended ($hit)"; return 0; fi
  priv="$(gh_get "repos/$r" | jq -r .private)" || die "cannot read the visibility of $r (named above)"
  [[ "$priv" == true || "$priv" == false ]] || die "GitHub answered repos/$r without a boolean \"private\""
  [[ "$priv" == true ]] || echo "public on GitHub"
}

# roster_pair_check [roster]: dies unless the roster's "repo" is private and not public-intended, and, when the
# roster declares "publishes_to", unless that repo is public or public-intended. Prints "publishes_to" (or nothing).
roster_pair_check() {
  local r="${1:-}" repo why pub
  [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  repo="$(jq -r '.repo // empty' "$r")"
  [[ "$repo" =~ ^[^/]+/[^/]+$ ]] || die "roster $r has no \"repo\" (owner/repo), got '$repo'"
  why="$(repo_public_why "$repo" "$r")" || exit 1
  [[ -z "$why" ]] || die "roster $r: its repo $repo is $why. A roster's repo is the private twin, where all work and coordination happen; the public repo it publishes to is named in \"publishes_to\""
  pub="$(jq -r '.publishes_to // empty' "$r")"
  [[ -n "$pub" ]] || return 0
  [[ "$pub" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "roster $r: \"publishes_to\" '$pub' is not owner/repo"
  why="$(repo_public_why "$pub" "$r")" || exit 1
  [[ -n "$why" ]] || die "roster $r: \"publishes_to\" $pub is private and not public-intended: a twin publishes to a public repo (or one the roster's public_intended lists)"
  echo "$pub"
}

# coord_write_guard <repo> [<seat>]: the one guard every coordination write passes before its first API write.
# Exits 1 when <repo> is public or public-intended, naming the rule and the private repo to write in instead
# (the seat's roster repo, else this roster's repo). There is no override.
coord_write_guard() {
  [[ $# -ge 1 && $# -le 2 ]] || die "coord_write_guard takes <repo> [<seat>], not $*"
  local r="$1" seat="${2:-}" why home="" id
  why="$(repo_public_why "$r")" || exit 1
  [[ -n "$why" ]] || return 0
  if [[ -n "$seat" ]] && id="$(seat_id "$seat" 2>/dev/null)"; then
    home="$(jq -r --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" '.seats[]? | select(.github == $g and .label == $l) | .repo // empty' "$(roster_path)")"
  fi
  [[ -n "$home" ]] || home="$(roster_repo)" || exit 1
  if [[ "$(printf '%s' "$home" | tr 'A-Z' 'a-z')" == "$(printf '%s' "$r" | tr 'A-Z' 'a-z')" ]]; then
    die "refused: $r is $why, and the roster $(roster_path) names it as the repo of ${id:-this roster}. Coordination stays private: a seat's home is a private repo (the twin; its roster names the public repo in \"publishes_to\"). Move the roster row to the twin; no coordination write goes to $r."
  fi
  die "refused: $r is $why. Coordination stays private: decision rows, desks, tracking issues, status, notes, acks, review requests and the board are written only in a private repo; a public repo receives only publishes. Write it in $home${id:+, the home repo of $id}."
}

# row_close_comment <repo> <N> "<words>" "<record>" <by-id> "<next>" closed|rejected: posts the close comment,
# the one writer of its shape for a decision issue and a pull request alike: the words verbatim, the record,
# the closer, and as its last line the closer's BEAST-ACK (state=seen). The caller closes, merges or labels.
row_close_comment() {
  local repo="$1" n="$2" words="$3" rec="$4" by="$5" next="$6" verdict
  case "$7" in
    closed) verdict="Closed" ;;
    rejected) verdict="Rejected" ;;
    *) die "row_close_comment: verdict must be closed or rejected, not '$7'" ;;
  esac
  [[ "$by" =~ $SEAT_ID_RE ]] || die "row_close_comment: --by '$by' is not a seat id"
  [[ "$next" != *$'\n'* ]] || die "--next is one line"
  issue_comment "$repo" "$n" "$verdict on the word, verbatim: \"$words\"

Record: $rec. Closed by seat $by at $(utc_now).

BEAST-ACK seat=$by at=$(utc_now) state=seen next=$next" >/dev/null
}

# row_mark_rejected <repo> <N>: the label `rejected` (defined in templates/labels.json) on a rejected row.
row_mark_rejected() { label_ensure_template "$1" rejected; issue_add_labels "$1" "$2" rejected; }

# row_after_close <repo> <N> <by-id> <board-repo>: what every close does next: republish the decider's board
# and print the row's seats, each acked by this close or unacked with its live address.
row_after_close() {
  local repo="$1" n="$2" by="$3" board="$4" info assignee waiting s addr
  info="$(issue_get "$repo" "$n")"
  assignee="$(jq -r '.assignees[0].login // empty' <<< "$info")"
  [[ -n "$assignee" ]] || die "$repo#$n has no assignee: no decider's board to republish"
  if "$BEAST_SCRIPTS/board.sh" --assignee "$assignee" --publish --repo "$board" >/dev/null; then echo "board republished in $board"
  else echo "daita-beast: the row is closed but the board in $board was NOT republished (board.sh failed, named above); fix that and run board.sh --publish --repo $board" >&2; fi
  waiting="$(row_seat_ids "$(jq -c .labels <<< "$info")")"
  if [[ -z "$waiting" ]]; then echo "no seat:* label on this row; nobody to tell beyond the board"; return 0; fi
  echo "seats on this row (each acks for itself with ack.sh; the words verbatim + $(jq -r .html_url <<< "$info")):"
  while read -r s; do
    [[ -n "$s" ]] || continue
    if [[ "$s" == "$by" ]]; then echo "  $s -> acked (seen) by this close"; continue; fi
    addr="$("$BEAST_SCRIPTS/seats.sh" address "$s" 2>/dev/null || echo "no live address recorded")"
    echo "  $s -> unacked; address $addr"
  done <<< "$waiting"
}

# row_events <row> ["<phrase>"]: (a row_read result) "<at>\t<kind>" of the row's latest event: created | answered
# (the assignee's newest answer-form comment) | closed. The phrase is row_phrase's when not given. Works for a
# decision issue and a pull request alike.
row_events() {
  local row="$1" phrase="${2:-}" info at kind c_at c_body login assignees
  info="$(jq '.issue' <<< "$row")"
  at="$(jq -r .created_at <<< "$info")"; kind=created
  [[ -n "$phrase" ]] || phrase="$(row_phrase "$(jq -r '"\(.repository_url | sub(".*/repos/"; ""))#\(.number)"' <<< "$info")" "$info")"
  assignees="$(jq -r '[.assignees[].login] | join(" ")' <<< "$info")"
  while IFS=$'\t' read -r c_at login c_body; do
    [[ -n "$c_at" ]] || continue
    [[ " $assignees " == *" $login "* ]] || continue
    [[ -n "$(answer_kind "$c_body" "$phrase")" ]] || continue
    if [[ "$c_at" > "$at" ]]; then at="$c_at"; kind=answered; fi
  done < <(jq -r '.comments[] | [.created_at, .user.login, ((.body // "") | split("\n")[0])] | @tsv' <<< "$row")
  local closed; closed="$(jq -r '.closed_at // empty' <<< "$info")"
  if [[ -n "$closed" && "$closed" > "$at" ]]; then at="$closed"; kind=closed; fi
  printf '%s\t%s\n' "$at" "$kind"
}

# ---- the desk ask header and the desk parser: the one owner (the page's ASK_RE / parseDesk are the JS twins) ----
# BEAST-ASK n=<seq> seat=<login>/<LABEL> at=<UTC>[ milestone="<title>"]   the first line of an ask; an ask written
# before milestones existed has no milestone field and still parses. The seat is a seat token (SEAT_TOKEN_RE's shape). ASK_HEADER_RE
# is read by desk_parse (jq) and ask_header writes it; plugin/tests/regex-mirror.test.mjs holds the page's ASK_RE to it.
ASK_HEADER_RE='^BEAST-ASK n=(?<n>[0-9]+) seat=(?<seat>([A-Za-z0-9-]+/)?[A-Z0-9_-]+) at=(?<at>[^ ]+)( milestone="(?<ms>[^"]+)")?$'

# ask_header <n> <id> <at> [<milestone title>]: the header line of an ask.
ask_header() {
  local n="$1" id="$2" at="$3" ms="${4:-}"
  [[ "$n" =~ ^[0-9]+$ ]] || die "ask_header: n '$n' is not a number"
  [[ "$id" =~ $SEAT_ID_RE ]] || die "ask_header: '$id' is not a seat id"
  [[ -z "$ms" ]] || milestone_title_check "$ms"
  printf 'BEAST-ASK n=%s seat=%s at=%s%s\n' "$n" "$id" "$at" "${ms:+ milestone=\"$ms\"}"
}

# ask_next_n <comments-json>: the n of a desk's next ask: the highest n of every comment whose first line opens as an
# ask header (a malformed one included, so no n is reused), plus one.
ask_next_n() {
  jq -r '[.[] | (.body // "") | split("\n")[0] | capture("^BEAST-ASK n=(?<n>[0-9]+) ") | .n | tonumber] | (max // 0) + 1' <<< "$1" \
    || die "cannot read the ask numbers of a desk"
}

# desk_find <id>: "<repo> <number> <state>" of the seat's desk, or nothing; dies when there are two. The list
# API, not search: search lags a create by seconds and would mint a second desk.
desk_find() {
  local id="$1" repo got n
  repo="$(seat_repo "$id")" || exit 1
  got="$(issues_list "$repo" -f labels="desk,seat:$id" -f state=all | jq -c '[.[] | select(.pull_request == null) | {number, state, html_url}]')" \
    || die "cannot list the issues of $repo (403 = repo not attached to this session or no access)"
  n="$(jq length <<< "$got")"
  [[ "$n" -le 1 ]] || die "$repo has $n desks for $id: $(jq -r '[.[].html_url] | join(" and ")' <<< "$got") — close all but one by hand"
  [[ "$n" -eq 1 ]] || return 0
  echo "$repo $(jq -r '.[0].number, .[0].state' <<< "$got" | tr '\n' ' ')"
}

# desk_parse <id> <row>: (a row_read of the desk) the desk's comments read into {asks:[…], messages:[…], dropped:[…]}, in comment order.
# Each ask: {n, url, at, milestone (null on an ask without one), waits_on:[refs], question:[lines], options, default,
# state: open|answered|withdrawn, answer:{text, url, at, by}}. The question lines are the ask's lines other than
# `options:`, `default:` and the `Waits on: <ref>` lines (waits_on_parse's shape). Each message: {from, at, url, text}.
# The dropped lines are printed on stderr here.
desk_parse() {
  local id="$1" row="$2" parsed
  parsed="$(jq '.comments' <<< "$row" | jq -c --arg seat "$id" --arg askre "$ASK_HEADER_RE" --arg wre "$WAITS_ON_RE" --argjson as "$(jq -c '[.issue.assignees[].login]' <<< "$row")" '
    def m(re): [capture(re)] | .[0];
    ("(words typed to " + $seat + "'"'"'s session, verbatim)") as $typed |
    reduce (.[] | {url: .html_url, at: .created_at, by: .user.login, lines: ((.body // "") | gsub("\r"; "") | split("\n"))}) as $c
      ({asks: {}, order: [], messages: [], dropped: []};
       ($c.lines[0] | sub("\\s+$"; "")) as $f
       | ($c.lines[1:] | map(sub("\\s+$"; ""))) as $rest
       | if ($f | startswith("BEAST-ASK")) then
           ($f | m($askre)) as $a
           | if $a == null then .dropped += ["malformed BEAST-ASK line: \($c.url)"]
             elif $a.seat != $seat then .dropped += ["an ask for \($a.seat) on the desk of \($seat): \($c.url)"]
             elif .asks[$a.n] != null then .dropped += ["a second ask n=\($a.n) (the first stands): \($c.url)"]
             else .asks[$a.n] = {n: ($a.n | tonumber), url: $c.url, at: $c.at, milestone: $a.ms,
                    waits_on: [$rest[] | select(startswith("Waits on:")) | (capture($wre) // {ref: "MALFORMED:\(.)"}) | .ref],
                    question: [$rest[] | select(test("\\S") and (test("^(options|default):") | not) and (startswith("Waits on:") | not))],
                    options: ([$rest[] | select(startswith("options:")) | sub("^options:\\s*"; "")] | .[0]),
                    default: ([$rest[] | select(startswith("default:")) | sub("^default:\\s*"; "")] | .[0]),
                    state: "open", answer: null}
                  | .order += [$a.n] end
         elif ($f | startswith("BEAST-ANSWER")) then
           ($f | m("^BEAST-ANSWER n=(?<n>[0-9]+)( (?<t>.*))?$")) as $a
           | ([$rest[] | select(. == $typed)] | length > 0) as $is_typed
           | ((([($a.t // "")] + [$rest[] | select(. != $typed)]) | map(select(test("\\S"))) | join("\n"))) as $text
           | if $a == null then .dropped += ["malformed BEAST-ANSWER line: \($c.url)"]
             elif (($as | index($c.by)) == null and ($is_typed | not)) then .dropped += ["BEAST-ANSWER n=\($a.n) by \($c.by), not an assignee of the desk nor posted by desk.sh answer: \($c.url)"]
             elif (.asks[$a.n] == null or .asks[$a.n].state != "open") then .dropped += ["BEAST-ANSWER n=\($a.n) answers no open ask: \($c.url)"]
             elif $text == "" then .dropped += ["BEAST-ANSWER n=\($a.n) carries no answer text: \($c.url)"]
             else .asks[$a.n].state = "answered" | .asks[$a.n].answer = {text: $text, url: $c.url, at: $c.at, by: (if $is_typed then "typed to the session" else $c.by end)} end
         elif ($f | startswith("BEAST-WITHDRAW")) then
           ($f | m("^BEAST-WITHDRAW n=(?<n>[0-9]+)$")) as $a
           | if $a == null then .dropped += ["malformed BEAST-WITHDRAW line: \($c.url)"]
             elif (.asks[$a.n] == null or .asks[$a.n].state != "open") then .dropped += ["BEAST-WITHDRAW n=\($a.n) withdraws no open ask: \($c.url)"]
             else .asks[$a.n].state = "withdrawn" | .asks[$a.n].answer = {text: "(withdrawn)", url: $c.url, at: $c.at, by: "the seat"} end
         elif ($f | startswith("BEAST-MSG")) then
           ($f | m("^BEAST-MSG from=(?<from>[^ ]+) to=(?<to>[^ ]+) at=(?<at>[^ ]+)$")) as $a
           | if $a == null then .dropped += ["malformed BEAST-MSG line: \($c.url)"]
             elif $a.to != $seat then .dropped += ["a message to \($a.to) on the desk of \($seat): \($c.url)"]
             else .messages += [{from: $a.from, at: $c.at, url: $c.url, text: ([$rest[] | select(test("\\S"))] | join("\n"))}] end
         elif ($f | startswith("BEAST-")) then .
         elif ($as | index($c.by)) != null then .messages += [{from: "@\($c.by)", at: $c.at, url: $c.url, text: ($c.lines | map(select(test("\\S"))) | join("\n"))}]
         else .dropped += ["a plain comment by \($c.by), not an assignee of the desk, is neither an answer nor a message: \($c.url)"] end)
    | {asks: [.order[] as $k | .asks[$k]], messages, dropped}')" || die "cannot read the desk of $id"
  jq -r '.dropped[] | "daita-beast: desk of '"$id"': dropped: \(.)"' <<< "$parsed" >&2
  jq -r '.asks[] | .url as $u | .waits_on[] | select(startswith("MALFORMED:")) | "daita-beast: desk of '"$id"': a \"Waits on:\" line that is not \"Waits on: <seat id | owner/repo#N>\" (\(sub("^MALFORMED:"; ""))): \($u)"' <<< "$parsed" >&2
  jq -c '.asks |= map(.waits_on |= map(select(startswith("MALFORMED:") | not)))' <<< "$parsed"
}

# ---- dependencies as data: the one owner of the waits-on shape --------------------------------------
# A dependency is one line, `Waits on: <ref>`, where <ref> is a seat id (<login>/<LABEL>) or a row (owner/repo#N). The
# same line is used everywhere a dependency is declared: in a decision row's `## Waits` section (decision.sh new
# --waits-on), in a desk ask's lines (desk.sh ask --waits-on) and in a milestone's description (milestone.sh new
# --waits-on). waits_on_line writes it, waits_on_parse and desk_parse read it (WAITS_ON_RE), dep_state measures it.
WAITS_ON_RE='^Waits on: (?<ref>[A-Za-z0-9-]+/[A-Z0-9_-]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+)$'

# waits_on_ref <seat LABEL | seat id | owner/repo#N | issue or PR url>: the normalized ref (a bare LABEL resolves through
# the roster; a url becomes owner/repo#N); dies on anything else.
waits_on_ref() {
  local x="${1:-}" r n
  [[ -n "$x" ]] || die "--waits-on needs a seat (LABEL or <login>/<LABEL>) or a row (owner/repo#N or its url)"
  if [[ "$x" == *#* || "$x" == https://* ]]; then read -r r n < <(parse_issue_ref "$x"); echo "$r#$n"; return 0; fi
  seat_id "$x"
}

# waits_on_line <ref>: the declaration line for a normalized ref.
waits_on_line() {
  local l="Waits on: $1"
  jq -en --arg l "$l" --arg re "$WAITS_ON_RE" '$l | test($re)' >/dev/null || die "'$1' is not a seat id or owner/repo#N"
  printf '%s\n' "$l"
}

# waits_on_parse <who> <text>: every ref declared in the text, one per line. A line that starts "Waits on:" and is not the
# shape dies naming <who>: a dependency that cannot be read is never silently dropped.
waits_on_parse() {
  local who="$1" text="$2" bad
  bad="$(printf '%s\n' "$text" | tr -d '\r' | jq -Rr --arg re "$WAITS_ON_RE" 'select(startswith("Waits on:")) | sub("\\s+$"; "") | select(test($re) | not)')"
  [[ -z "$bad" ]] || die "$who: a \"Waits on:\" line that is not \"Waits on: <seat id | owner/repo#N>\": $bad"
  printf '%s\n' "$text" | tr -d '\r' | jq -Rr --arg re "$WAITS_ON_RE" 'sub("\\s+$"; "") | capture($re) // empty | .ref'
}

# ---- milestones: the one owner of the milestone shape -------------------------------------------------
# A milestone is a GitHub milestone on the repo an item lives in (a seat's milestones are on its home, the roster
# `repo`). Its title is one line without `"` (the ask header quotes it). Its due date is GitHub's own due_on, the only
# copy (set at noon UTC: measured 2026-10-16, a due_on of T00:00:00Z is stored as the day before; T12:00:00Z keeps the
# date). Its description is fixed lines, written only by milestone_desc:
#   Delivers: <one line>                              required
#   Moved: later|earlier — <why>                      the latest move only (milestone.sh move); no history
#   Waits on: <ref>                                   one per dependency (waits_on_line)
#   Report: <one line>                                the latest participant report's summary (report.sh milestone)
MILESTONE_DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

milestone_title_check() {
  local t="${1:-}"
  [[ -n "${t//[[:space:]]/}" ]] || die "a milestone title is not empty"
  [[ "$t" != *$'\n'* && "$t" != *'"'* ]] || die "milestone title '$t': one line, no double quote (the ask header quotes it)"
  [[ "$t" != *'|'* ]] || die "milestone title '$t': no '|' (workstream.sh --milestone splits on it)"
}

milestone_date_check() {
  [[ "${1:-}" =~ $MILESTONE_DATE_RE ]] || die "due date '${1:-}' is not YYYY-MM-DD"
  jq -en --arg d "$1" '($d + "T12:00:00Z" | fromdate | strftime("%Y-%m-%d")) == $d' >/dev/null 2>&1 || die "due date '$1' is not a calendar date"
}

# milestone_all <repo> [open|closed|all]: the repo's milestones as one JSON array, soonest due first.
milestone_all() { gh_get_all "repos/$1/milestones?state=${2:-open}&sort=due_on&direction=asc" || die "cannot list the milestones of $1 (named above)"; }

# milestone_get <repo> <title>: the milestone with exactly that title (any state) as JSON; dies naming the open ones.
milestone_get() {
  local all got
  all="$(milestone_all "$1" all)" || exit 1
  got="$(jq -c --arg t "$2" '[.[] | select(.title == $t)] | .[0] // empty' <<< "$all")"
  [[ -n "$got" ]] || die "$1 has no milestone titled \"$2\" (open: $(jq -r '[.[] | select(.state == "open") | "\"\(.title)\""] | join(", ") | if . == "" then "none" else . end' <<< "$all"))"
  printf '%s\n' "$got"
}

# milestone_field <ms-json> <Delivers|Moved|Report>: the value of that description line, or nothing.
milestone_field() { jq -r --arg k "$2: " '(.description // "") | gsub("\r"; "") | split("\n") | map(select(startswith($k)) | ltrimstr($k)) | .[0] // empty' <<< "$1"; }

# milestone_desc <delivers> <moved> <report> [<ref>...]: the description, the one writer of its lines.
milestone_desc() {
  local d="$1" mv="$2" rep="$3"; shift 3
  [[ -n "${d//[[:space:]]/}" && "$d" != *$'\n'* ]] || die "a milestone's delivers is one non-empty line"
  [[ "$mv$rep" != *$'\n'* ]] || die "a milestone's moved and report are one line each"
  printf 'Delivers: %s\n' "$d"
  [[ -z "$mv" ]] || printf 'Moved: %s\n' "$mv"
  local r; for r in "$@"; do waits_on_line "$r"; done
  [[ -z "$rep" ]] || printf 'Report: %s\n' "$rep"
}

# milestone_write <repo> <POST | PATCH number> <due> <desc> [<title>]: the one write of a milestone; checks the due date
# GitHub stored is the one asked for. Prints the milestone JSON.
milestone_write() {
  local repo="$1" how="$2" due="$3" desc="$4" title="${5:-}" out path args=()
  milestone_date_check "$due"
  if [[ "$how" == POST ]]; then path="repos/$repo/milestones"; milestone_title_check "$title"; args+=(-f title="$title")
  else [[ "$how" =~ ^[0-9]+$ ]] || die "milestone_write: '$how' is not POST or a milestone number"; path="repos/$repo/milestones/$how"; how=PATCH; fi
  out="$(gh_send "$how" "$path" ${args[@]+"${args[@]}"} -f due_on="${due}T12:00:00Z" -f description="$desc")" || exit 1
  [[ "$(jq -r '.due_on // "" | .[:10]' <<< "$out")" == "$due" ]] || die "$repo milestone \"$(jq -r .title <<< "$out")\": GitHub stored due $(jq -r .due_on <<< "$out"), not $due"
  printf '%s\n' "$out"
}

# milestone_create <repo> <title> <due> <delivers> [<ref>...]: the one creator of a milestone (milestone.sh new and
# workstream.sh new). An existing milestone of that title with the same due date and delivers is reused (a rerun);
# one that differs dies naming it. Prints the milestone's html_url.
milestone_create() {
  local repo="$1" title="$2" due="$3" delivers="$4" desc all got; shift 4
  milestone_title_check "$title"; milestone_date_check "$due"
  desc="$(milestone_desc "$delivers" "" "" "$@")" || exit 1
  all="$(milestone_all "$repo" all)" || exit 1
  got="$(jq -c --arg t "$title" '[.[] | select(.title == $t)] | .[0] // empty' <<< "$all")"
  if [[ -n "$got" ]]; then
    [[ "$(jq -r '.due_on // "" | .[:10]' <<< "$got")" == "$due" && "$(milestone_field "$got" Delivers)" == "$delivers" && "$(jq -r .state <<< "$got")" == open ]] \
      || die "$repo already has a milestone \"$title\" ($(jq -r '"\(.state), due \(.due_on // "none" | .[:10])"' <<< "$got"), delivering \"$(milestone_field "$got" Delivers)\"): $(jq -r .html_url <<< "$got") — move it (milestone.sh move) or choose another title"
    echo "reusing $(jq -r .html_url <<< "$got")" >&2
    jq -r .html_url <<< "$got"; return 0
  fi
  milestone_write "$repo" POST "$due" "$desc" "$title" | jq -r .html_url
}

# milestone_require <repo> <title | "">: the number of the open milestone an item of <repo> is filed under. With a title, it
# must be an open milestone of <repo>. Without one, nothing is printed when <repo> has no open milestone; when it has any,
# it dies listing them: every row, ask and PR of a repo with milestones names one.
milestone_require() {
  local repo="$1" t="${2:-}" open
  open="$(milestone_all "$repo" open)" || exit 1
  if [[ -z "$t" ]]; then
    [[ "$(jq length <<< "$open")" -eq 0 ]] || die "$repo has open milestones; pass --milestone with one of: $(jq -r '[.[] | "\"\(.title)\" (due \(.due_on // "none" | .[:10]))"] | join(", ")' <<< "$open")"
    return 0
  fi
  jq -er --arg t "$t" '[.[] | select(.title == $t)] | .[0].number // empty' <<< "$open" \
    || die "\"$t\" is not an open milestone of $repo (open: $(jq -r '[.[] | "\"\(.title)\""] | join(", ") | if . == "" then "none" else . end' <<< "$open"))"
}

# milestone_set <repo> <N> <milestone number>: files issue or PR <repo>#<N> under the milestone.
milestone_set() { gh_send PATCH "repos/$1/issues/$2" -F milestone="$3" >/dev/null; }

# milestone_days <ms-json>: whole days from today (UTC) to the due date (negative when overdue), or nothing without one.
milestone_days() { jq -r 'if .due_on then (((.due_on[:10] + "T00:00:00Z" | fromdate) - (now | strftime("%Y-%m-%dT00:00:00Z") | fromdate)) / 86400 | floor) else empty end' <<< "$1"; }

# milestone_slip <ms-json>: one line when an open milestone is late (overdue, or its latest move was later), else nothing.
milestone_slip() {
  local d mv out=""
  [[ "$(jq -r .state <<< "$1")" == open ]] || return 0
  d="$(milestone_days "$1")" && mv="$(milestone_field "$1" Moved)" || die "cannot read the due date or the Moved line of milestone $(jq -r .html_url <<< "$1")"
  [[ -z "$d" || "$d" -ge 0 ]] || out="overdue by $(( -d )) day(s), due $(jq -r '.due_on[:10]' <<< "$1")"
  [[ "$mv" != later* ]] || out="${out:+$out; }moved later to $(jq -r '.due_on[:10]' <<< "$1"): ${mv#later — }"
  [[ -z "$out" ]] || printf '%s\n' "$out"
}

# milestone_due_flags <repo>: one line per open milestone of <repo> due within 3 days or overdue.
milestone_due_flags() {
  local all m d
  all="$(milestone_all "$1" open)" || exit 1
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    d="$(milestone_days "$m")"; [[ -n "$d" && "$d" -le 3 ]] || continue
    printf 'milestone "%s" %s (due %s, %s open item(s)) %s\n' "$(jq -r .title <<< "$m")" \
      "$( if (( d < 0 )); then echo "OVERDUE by $(( -d )) day(s)"; elif (( d == 0 )); then echo "due TODAY"; else echo "due in $d day(s)"; fi)" \
      "$(jq -r '.due_on[:10]' <<< "$m")" "$(jq -r .open_issues <<< "$m")" "$(jq -r .html_url <<< "$m")"
  done < <(jq -c '.[]' <<< "$all")
}

# ---- dependency state: the one measure (deps.sh and report.sh milestone) ------------------------------
# dep_state <ref> <reader repo>: "<state>\t<detail>" for a declared dependency, state one of:
#   released            a row closed approved (completed, not rejected) or a PR merged; a seat whose home has no open
#                       milestone left and closed one (the latest) — with the link
#   delayed             open, and its milestone (the row's, or the seat's soonest open one) is overdue or was moved later — with the why
#   changed direction   a row closed rejected (not planned / label rejected) or a PR closed unmerged, or an open row whose
#                       decider's newest answer is revise: — with the row's link, and the first line of the words only when
#                       the reader's repo is the row's own (words stay in the home where they were said)
#   waiting, on time    open and not late (the negative control)
#   waiting, no milestone  a seat whose home has never set a milestone
dep_state() {
  local ref="$1" reader="$2" r n row info url words="" slip ms id home all last
  if [[ "$ref" == *#* ]]; then
    read -r r n < <(parse_issue_ref "$ref")
    row="$(row_read "$r" "$n")" || exit 1
    info="$(jq -c .issue <<< "$row")"; url="$(jq -r .html_url <<< "$info")"
    if [[ "$(tr 'A-Z' 'a-z' <<< "$r")" == "$(tr 'A-Z' 'a-z' <<< "$reader")" ]]; then
      words="$(jq -r '[.comments[] | select((.body // "") | test("^(Closed|Rejected) on the word"))] | if length == 0 then "" else (last.body | split("\n")[0] | sub("^(Closed|Rejected) on the word, verbatim: "; "")) end' <<< "$row")" \
        || die "$r#$n: cannot read its close words"
    fi
    if [[ "$(jq -r .state <<< "$info")" == closed ]]; then
      if jq -e '.pull_request != null' <<< "$info" >/dev/null; then
        if jq -e '.pull_request.merged_at' <<< "$info" >/dev/null; then printf 'released\tmerged %s %s\n' "$(jq -r '.pull_request.merged_at[:10]' <<< "$info")" "$url"
        else printf 'changed direction\tclosed unmerged %s%s\n' "$url" "${words:+ — $words}"; fi
      elif jq -e '.state_reason == "not_planned" or any(.labels[]; .name == "rejected")' <<< "$info" >/dev/null; then
        printf 'changed direction\trejected %s%s\n' "$url" "${words:+ — $words}"
      else printf 'released\tclosed %s %s\n' "$(jq -r '.closed_at[:10]' <<< "$info")" "$url"; fi
      return 0
    fi
    local phrase assignees c_body login k kind="" ktext=""
    phrase="$(row_phrase "$r#$n" "$info" 2>/dev/null)" || true
    assignees="$(jq -r '[.assignees[].login] | join(" ")' <<< "$info")"
    while IFS=$'\t' read -r login c_body; do
      [[ " $assignees " == *" $login "* ]] || continue
      k="$(answer_kind "$c_body" "$phrase")"; [[ -n "$k" ]] || continue
      kind="$k"; ktext="$c_body"
    done < <(jq -r '.comments | sort_by(.created_at)[] | [.user.login, ((.body // "") | split("\n")[0])] | @tsv' <<< "$row")
    if [[ "$kind" == revise ]]; then
      [[ "$(tr 'A-Z' 'a-z' <<< "$r")" == "$(tr 'A-Z' 'a-z' <<< "$reader")" ]] && words="$ktext" || words=""
      printf 'changed direction\trevised %s%s\n' "$url" "${words:+ — $words}"; return 0
    fi
    ms="$(jq -c '.milestone // empty' <<< "$info")"
    if [[ -n "$ms" ]]; then
      slip="$(milestone_slip "$ms")" || die "$r#$n: cannot read its milestone's due state"
      if [[ -n "$slip" ]]; then printf 'delayed\tmilestone "%s" %s %s\n' "$(jq -r .title <<< "$ms")" "$slip" "$url"; return 0; fi
      printf 'waiting, on time\tmilestone "%s" due %s %s\n' "$(jq -r .title <<< "$ms")" "$(jq -r '.due_on // "none" | .[:10]' <<< "$ms")" "$url"; return 0
    fi
    printf 'waiting, on time\topen, no milestone %s\n' "$url"; return 0
  fi
  id="$(seat_rostered "$ref")" || exit 1
  home="$(seat_repo "$id")" || exit 1
  all="$(milestone_all "$home" all)" || exit 1
  ms="$(jq -c '[.[] | select(.state == "open")] | sort_by(.due_on // "9999") | .[0] // empty' <<< "$all")" || die "cannot read the milestones of $home"
  if [[ -n "$ms" ]]; then
    slip="$(milestone_slip "$ms")" || die "cannot read the due state of $id's milestone"
    if [[ -n "$slip" ]]; then printf 'delayed\t%s milestone "%s" %s %s\n' "$id" "$(jq -r .title <<< "$ms")" "$slip" "$(jq -r .html_url <<< "$ms")"; return 0; fi
    printf 'waiting, on time\t%s milestone "%s" due %s %s\n' "$id" "$(jq -r .title <<< "$ms")" "$(jq -r '.due_on // "none" | .[:10]' <<< "$ms")" "$(jq -r .html_url <<< "$ms")"; return 0
  fi
  last="$(jq -c '[.[] | select(.state == "closed")] | sort_by(.closed_at) | .[-1] // empty' <<< "$all")" || die "cannot read the milestones of $home"
  if [[ -n "$last" ]]; then printf 'released\t%s milestone "%s" closed %s %s\n' "$id" "$(jq -r .title <<< "$last")" "$(jq -r '.closed_at[:10]' <<< "$last")" "$(jq -r .html_url <<< "$last")"; return 0; fi
  printf 'waiting, no milestone\t%s has set no milestone in %s\n' "$id" "$home"
}

# deps_declared <id>: what the seat declared it waits on, "<ref>\t<declared on url>" per line: the `Waits on:` lines of the
# open decision rows labelled seat:<id> in its home, of its open desk asks, and of its home's open milestones.
deps_declared() {
  local id="$1" home rows f repo n state parsed o u body refs
  home="$(seat_repo "$id")" || exit 1
  rows="$(issues_list "$home" -f labels="decision,seat:$id" -f state=open | jq -c '[.[] | select(.pull_request == null) | {u: .html_url, b: (.body // "")}]')" \
    || die "cannot list the decision rows of $home"
  f="$(milestone_all "$home" open | jq -c '[.[] | {u: .html_url, b: (.description // "")}]')" || die "cannot list the milestones of $home"
  rows="$(jq -c -s 'add' <(printf '%s\n' "$rows") <(printf '%s\n' "$f"))" || die "cannot merge the declaring items of $id"
  # Each declaring item is read whole as one JSON object per line, never through @tsv (it escapes the body's newlines).
  while IFS= read -r o; do
    u="$(jq -r .u <<< "$o")" && body="$(jq -r .b <<< "$o")" || die "cannot read a declaring item: $o"
    refs="$(waits_on_parse "$u" "$body")" || exit 1
    [[ -z "$refs" ]] || awk -v u="$u" '{ print $0 "\t" u }' <<< "$refs"
  done < <(jq -c '.[]' <<< "$rows")
  f="$(desk_find "$id")" || exit 1
  if [[ -n "$f" ]]; then
    read -r repo n state <<< "$f"
    parsed="$(desk_parse "$id" "$(row_read "$repo" "$n")")" || exit 1
    jq -r '.asks[] | select(.state == "open") | .url as $u | .waits_on[] | "\(.)\t\($u)"' <<< "$parsed"
  fi
}
