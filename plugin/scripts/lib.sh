#!/usr/bin/env bash
# Shared helpers for the daita-beast scripts. Sourced, never executed.
set -euo pipefail

die() { echo "daita-beast: $*" >&2; exit 1; }

need() { for t in "$@"; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"; done; }

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The directory the plugin's scripts live in (claude_block_render, the hooks and seat.sh name it).
BEAST_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The published DeSciX CLI every printed descix command runs: the one owner of its version (bootstrap.sh, wrapup.sh
# and the skills and docs read it here). descix_cmd <args>: the command line, `npx -y -p <pin> descix <args>`.
DESCIX_CLI_PKG='@descix/cli@4.2.0'
descix_cmd() { printf 'npx -y -p %s descix %s' "$DESCIX_CLI_PKG" "$*"; }

# ---- a checkout: the one owner of "is <dir> a git checkout", "its root" and "is it the repo's main checkout" ------
# A checkout root is `git rev-parse --show-toplevel`. The main checkout of a repo, the one whose git dir holds the repo
# (the roster, the seats' homes and the publish branches are read there), is the worktree whose git dir IS the common
# dir: a plain checkout (its .git a directory), and a submodule's checkout (its .git a FILE, `gitdir: ../.git/modules/
# <path>`, and its common dir that modules dir; measured 2026-10-19 on a platform twin checked out as a submodule:
# --git-dir and --git-common-dir both <super>/.git/modules/<path>). A linked worktree's git dir is <common>/worktrees/<name>, so
# it is not the main checkout. No script tests `-d .git`: a submodule has none.

# checkout_root <dir>: the real path of the root of the checkout <dir> is in; dies when <dir> is not inside one.
checkout_root() {
  local t; t="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" || die "${1:-.} is not inside a git checkout"
  cd "$t" && pwd -P
}

# checkout_require_root <dir>: dies unless <dir> is the root of a git checkout (a subdirectory of one is not).
checkout_require_root() {
  local d; d="$(cd "${1:-}" 2>/dev/null && pwd -P)" || die "${1:-}: no such directory"
  [[ "$(checkout_root "$d")" == "$d" ]] || die "$1 is not the root of a git checkout (it is inside $(checkout_root "$d"))"
}

# checkout_is_main <dir>: status 0 when <dir> is in its repo's main checkout (git dir equals common dir), 1 when it is
# in a linked worktree or in no checkout at all. Prints nothing.
checkout_is_main() {
  local g c
  g="$(git -C "${1:-.}" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || return 1
  c="$(git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [[ "$(cd "$g" && pwd -P)" == "$(cd "$c" && pwd -P)" ]]
}

# repo_root: the working tree the caller stands in (a worktree home's own tree). In a wrapper home, which
# is not a git tree, it is the checkout the wrapper's .beast/seat.json names in "root" (written by seat.sh new).
repo_root() {
  local t f
  if t="$(git rev-parse --show-toplevel 2>/dev/null)"; then echo "$t"; return 0; fi
  f="$PWD/.beast/seat.json"
  [[ -f "$f" ]] || die "not inside a git repository, nor a Beast wrapper home ($f absent)"
  [[ "$(jq -r '.kind // empty' "$f")" == wrapper ]] || die "$f is not a wrapper home's seat.json, and $PWD is not inside a git repository"
  t="$(jq -r '.root // empty' "$f")"
  [[ -n "$t" ]] && checkout_is_main "$t" || die "$f names no main checkout in \"root\" (got '$t'): rerun seat.sh new from the checkout"
  echo "$t"
}

# repo_main_root: the repo's main checkout, the same from the checkout, any of its linked worktrees, or a wrapper. From
# a linked worktree it is the common dir's work tree: core.worktree of the common dir when set (a submodule's modules
# dir records it), else the directory holding the .git dir.
repo_main_root() {
  local root c wt
  root="$(repo_root)" || exit 1
  if checkout_is_main "$root"; then checkout_root "$root"; return 0; fi
  c="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)" || die "cannot read the git common dir of $root"
  [[ "$(git --git-dir="$c" config --get core.bare 2>/dev/null)" != true ]] || die "the repo's git dir $c is bare: no main checkout"
  if wt="$(git --git-dir="$c" config --get core.worktree 2>/dev/null)" && [[ -n "$wt" ]]; then
    (cd "$c" && cd "$wt" && pwd -P) || die "the git dir $c names a work tree '$wt' that does not exist"
  else
    [[ "$(basename "$c")" == .git ]] || die "the git dir $c is neither a checkout's .git nor a submodule's modules dir (no core.worktree): no main checkout"
    (cd "$(dirname "$c")" && pwd -P)
  fi
}

# repo_slug [root]: the owner/repo of the checkout's origin on github.com; dies when there is none.
repo_slug() {
  local root="${1:-}" u
  [[ -n "$root" ]] || root="$(repo_root)"
  u="$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
  [[ "$u" =~ ^[^/]+/[^/]+$ ]] || die "$root has no origin remote on github.com"
  echo "$u"
}

# checkout_lane <checkout>: the lane its CLAUDE.md declares on a `LANE: <name>` line (a name: a-z, 0-9, -), or nothing
# when it has no such line: a lane is recorded only when declared, never defaulted.
checkout_lane() { [[ ! -f "$1/CLAUDE.md" ]] || sed -n 's/^LANE: *\([a-z][a-z0-9-]*\).*/\1/p' "$1/CLAUDE.md" | head -1; }

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

# The machine-local session file (never committed). It is keyed by the identity <slug>/<LABEL>/<login> only:
# sessions_key_check refuses any other key before a write, and seats.sh drops one, named. An entry holds two facts:
#   the address cache  {name, ref, address, account, machine, cwd, recorded_at}: seats.sh record, a cache of
#                      the seat's BEAST-ADDRESS comment (the owner of the address)
#   the session claim  {session, session_at, launch, tracking, ended_at, previous}: the one owner of which Claude Code
#                      session on this machine holds the seat. Written by sessions_claim (join.sh, seats.sh record) and
#                      sessions_end (the SessionEnd hook), read by the SessionStart hook to rejoin (seat-hello.sh).
#                      previous lists the sessions the claim was taken from, newest last (SESSIONS_PREVIOUS_MAX).
sessions_path() { echo "${BEAST_SESSIONS_FILE:-$HOME/.beast/sessions.json}"; }
sessions_key_check() { [[ "${1:-}" =~ $SEAT_IDENTITY_RE ]] || die "refused: '${1:-}' is not <slug>/<LABEL>/<login>; the cache $(sessions_path) is keyed by the identity only"; }
SESSIONS_PREVIOUS_MAX=5

# sessions_update <jq filter> [jq args]...: the one writer of the session file: the filter applied, written atomically.
sessions_update() {
  local f t; f="$(sessions_path)"; mkdir -p "$(dirname "$f")"
  [[ -s "$f" ]] || echo '{}' > "$f"
  t="$(mktemp "$f.XXXXXX")"
  jq "${@:2}" "$1" "$f" > "$t" || { rm -f "$t"; die "the session file $f is not JSON; fix or delete it"; }
  mv -f "$t" "$f"
}

# sessions_claim <identity> [<launch dir>] [<tracking ref>]: records that this session ($CLAUDE_CODE_SESSION_ID) holds
# the seat: session, session_at (now), launch and tracking when given, ended_at cleared; a claim held by another session
# moves to previous. Prints the line join shows; outside a Claude Code session (no id) it records nothing and says so.
sessions_claim() {
  local id="$1" launch="${2:-}" tracking="${3:-}" sid="${CLAUDE_CODE_SESSION_ID:-}"
  sessions_key_check "$id"
  if [[ -z "$sid" ]]; then echo "session: none recorded (CLAUDE_CODE_SESSION_ID is unset: not a Claude Code session), so no SessionStart hook rejoins this seat"; return 0; fi
  sessions_update '.[$k] = ((.[$k] // {}) as $e
      | $e + {session: $s, session_at: $t}
      + (if $l != "" then {launch: $l} else {} end) + (if $r != "" then {tracking: $r} else {} end)
      + {previous: ((($e.previous // []) + (if ($e.session // $s) != $s then [{session: $e.session, session_at: $e.session_at, launch: $e.launch, ended_at: $e.ended_at}] else [] end))[-($n):])}
      | del(.ended_at))' \
    --arg k "$id" --arg s "$sid" --arg t "$(utc_now)" --arg l "$launch" --arg r "$tracking" --argjson n "$SESSIONS_PREVIOUS_MAX"
  launch="$(jq -r --arg k "$id" '.[$k].launch // empty' "$(sessions_path)")"
  echo "session: $sid holds $id ($(sessions_path)); the SessionStart hook rejoins it after a compaction or a resume, and after a restart in ${launch:-its launch folder (recorded at its next join)} once this session has ended"
}

# sessions_end <session id>: marks every claim that session holds as ended now (the SessionEnd hook).
sessions_end() {
  [[ -n "${1:-}" ]] || die "sessions_end: no session id"
  [[ -s "$(sessions_path)" ]] || return 0
  sessions_update 'with_entries(if .value.session == $s then .value.ended_at = $t else . end)' --arg s "$1" --arg t "$(utc_now)"
}

# ---- hooks.log: the one record of a hook's block or fault ---------------------------------------------------------
# A hook never fails a session: it puts a fault into the session's context (seat-hello.sh) or onto stderr (seat-bye.sh,
# permit.sh), where no log keeps it. hook_log appends one line to ~/.beast/hooks.log (BEAST_HOOKS_LOG moves it):
#   <UTC>\t<hook>\t<block|fault>\tsession=<id or ->\t<the message, one line>
# The machine watchdog reads the file from its last offset and files one deduplicated bug per hook and message class.
hooks_log_path() { echo "${BEAST_HOOKS_LOG:-$HOME/.beast/hooks.log}"; }
hook_log() {
  [[ $# -eq 4 ]] || die "hook_log takes <hook> <block|fault> <session id | -> \"<message>\", not $*"
  case "$2" in block|fault) ;; *) die "hook_log: kind is block or fault, not '$2'" ;; esac
  local f; f="$(hooks_log_path)"; mkdir -p "$(dirname "$f")"
  printf '%s\t%s\t%s\tsession=%s\t%s\n' "$(utc_now)" "$1" "$2" "${3:--}" "$(printf '%s' "$4" | tr '\t\n\r' '   ')" >> "$f"
}

# ---- the watchdog's allowlist: the one owner of what a watchdog session may run ------------------------------------
# The watchdog (watchdog.sh, plugin/agents/watchdog.md) starts its Haiku session with BEAST_WATCHDOG=1. Every plugin
# script sources this file at its top, so under that variable a script runs only when its name and first argument are
# listed here, and dies naming the rule otherwise: the watchdog never answers, acks, closes, labels, files a row, posts
# status or notes, records, re-stamps or forgets an address (the tick re-stamps, seats.sh touch, outside the session),
# or makes a seat or a workstream. The hooks run in its session too.
WATCHDOG_ALLOWED='watchdog.sh:* permit.sh:* seat-hello.sh:* seat-bye.sh:*'
watchdog_guard() {
  [[ "${BEAST_WATCHDOG:-}" == 1 ]] || return 0
  local name a; name="$(basename "$0")"
  [[ "$name" == *.sh ]] || return 0   # a shell or a test sourcing this file is not a plugin script run
  for a in $WATCHDOG_ALLOWED; do [[ "$a" == "$name:*" || "$a" == "$name:${1:-}" ]] && return 0; done
  die "refused: $name ${1:-} under the watchdog (BEAST_WATCHDOG=1): it may run only $WATCHDOG_ALLOWED; answering, acking, closing, labelling, filing, status, notes and address records are a seat's or the decider's acts"
}
watchdog_guard "$@"

# ---- the run cache: one search per query per run ---------------------------------------------------------------
# A run is a top-level script and every script it starts (join.sh starts seats.sh record, resume.sh, seats.sh list,
# notes.sh, decision.sh inbox, desk.sh inbox). GitHub's search quota is 30 a minute per login, shared by every seat
# of that login, and one run re-asks the same queries many times (the tracking issue of a slug, every open
# workstream). So the first script of a run makes $BEAST_WS_CACHE, a directory, exports it, and deletes it when it
# exits; the scripts it starts inherit the variable and read what is already there (search_issues, ws_seats_all).
# A result re-asked within a run is no fresher: the search index lags a write by seconds to minutes (Reading
# GitHub, protocol.md). A long-running loop (watch.sh --interval) empties it before each poll (run_cache_clear).
# Every EXIT cleanup goes through on_exit, so a script's own temp dir and the run cache are both removed.
BEAST_EXIT_CMDS=()
on_exit() { BEAST_EXIT_CMDS+=("$1"); trap 'for c in "${BEAST_EXIT_CMDS[@]}"; do eval "$c"; done' EXIT; }
if [[ -z "${BEAST_WS_CACHE:-}" ]]; then
  BEAST_WS_CACHE="$(mktemp -d)" || die "cannot make the run cache directory (mktemp -d)"
  export BEAST_WS_CACHE
  on_exit 'rm -rf "$BEAST_WS_CACHE"'
fi
[[ -d "$BEAST_WS_CACHE" ]] || die "BEAST_WS_CACHE=$BEAST_WS_CACHE is not a directory: the run cache is made by the first script of a run; unset it"

# run_cache_clear: forgets every memoized search and seat table (a loop that polls calls it before each poll).
run_cache_clear() { rm -f "$BEAST_WS_CACHE"/search-* "$BEAST_WS_CACHE/ws-seats.tsv"; }

# ---- seat identity: the one owner ---------------------------------------------------------------
# A seat is one role (its roster row's `agent`, an agent file) held in one workstream (its row's
# `workstream`, a slug). Its identity is the composite <slug>/<LABEL>/<login>: the key of the seat map, of
# seats.sh list, of ~/.beast/sessions.json and of the BEAST-ADDRESS comment. Inside one workstream's own
# artifacts (row labels seat:<login>/<LABEL>, acks, BEAST-STATUS, the `## Seats` table) the short id
# <login>/<LABEL> abbreviates it, resolved through the roster row's `workstream`. The same login and label in
# two workstreams are two identities. Every script that takes <SEAT> accepts LABEL, login/LABEL or the composite.
# Nothing stores the composite in the roster: it is derived here from the row's github, label and workstream.
SEAT_LOGIN_PART='[A-Za-z0-9-]+'
SEAT_LABEL_PART='[A-Z0-9_-]+'
WS_SLUG_PART='[a-z0-9][a-z0-9-]*'
SEAT_ID_RE="^${SEAT_LOGIN_PART}/${SEAT_LABEL_PART}\$"
SEAT_LABEL_RE="^${SEAT_LABEL_PART}\$"
SEAT_IDENTITY_RE="^${WS_SLUG_PART}/${SEAT_LABEL_PART}/${SEAT_LOGIN_PART}\$"
WS_SLUG_RE="^${WS_SLUG_PART}\$"
# A seat as written in a comment (ack, status, close): a qualified id, or a bare label resolved through seat_id.
SEAT_TOKEN_RE="(${SEAT_LOGIN_PART}/)?${SEAT_LABEL_PART}"
# A role: an agent name (<repo>/.claude/agents/<name>.md), or daita-beast:<name> (the plugin's own agents/<name>.md).
AGENT_NAME_RE='^(daita-beast:)?[A-Za-z0-9][A-Za-z0-9_-]*$'
ROSTER_DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

# roster_check_unique [roster]: the one check of the roster's seat rows; every script that reads them calls it
# (via roster_seat_ids). A row is {github, label, repo, lane?, agent, workstream, home?, retired?}. Dies naming the
# row and the key when: github/label is not <login>/<LABEL>; two rows share one (github, label) pair; the row
# carries `role` or `tracking` (deleted: the agent file is the role, the workstream issue is found by its labels);
# `agent` is absent or not an agent name; `workstream` is absent or not a slug; `lane` (optional: the repo
# CLAUDE.md's LANE: line when it has one) is present and not a name; `retired` is not YYYY-MM-DD; or
# the row's `repo` is not the roster's own (a peer row): peers live on the workstream issue's `## Seats` table.
roster_check_unique() {
  local r="${1:-}" bad
  [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  bad="$(jq -r --arg re "$SEAT_ID_RE" '[.seats[]? | "\(.github // "")/\(.label // "")" | select(test($re) | not)] | join(", ")' "$r")"
  [[ -z "$bad" ]] || die "roster $r: seat row(s) whose github/label is not <login>/<LABEL>: $bad"
  bad="$(jq -r '[.seats[]? | "\(.github)/\(.label)"] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' "$r")"
  [[ -z "$bad" ]] || die "roster $r: two seat rows share the id $bad (a label is unique per login)"
  bad="$(jq -r --arg a "$AGENT_NAME_RE" --arg w "$WS_SLUG_RE" --arg d "$ROSTER_DATE_RE" '
    (.repo // "") as $own | ($own | ascii_downcase) as $mine
    | [.seats[]? | "\(.github)/\(.label)" as $id
        | if has("role") then "\($id): key \"role\" is deleted (the role is the agent file: \"agent\": \"<name>\")"
          elif has("tracking") then "\($id): key \"tracking\" is deleted (the workstream issue is found by its labels: \"workstream\": \"<slug>\")"
          elif ((.agent // "") | type) != "string" or ((.agent // "") | test($a) | not) then "\($id): key \"agent\" is required (an agent name, or daita-beast:seat), got \(.agent | tojson)"
          elif ((.workstream // "") | type) != "string" or ((.workstream // "") | test($w) | not) then "\($id): key \"workstream\" is required (a slug: a-z, 0-9, -), got \(.workstream | tojson)"
          elif has("lane") and (((.lane | type) != "string") or (.lane | test("^[a-z][a-z0-9-]*$") | not)) then "\($id): key \"lane\" is optional, and when present a name (a-z, 0-9, -), got \(.lane | tojson)"
          elif has("retired") and ((.retired | type) != "string" or (.retired | test($d) | not)) then "\($id): key \"retired\" is a date YYYY-MM-DD, got \(.retired | tojson)"
          elif ((.repo // "" | ascii_downcase) != $mine) then "\($id): a peer row (repo \(.repo | tojson), not this roster'"'"'s own \($own | tojson)): peers live on the workstream issue (workstream.sh seat-add)"
          else empty end] | first // empty' "$r")"
  [[ -z "$bad" ]] || die "roster $r: seat row $bad"
}

# roster_seat_ids [roster]: every seat id of the roster, one per line, roster order.
roster_seat_ids() {
  local r="${1:-}"
  [[ -n "$r" ]] || r="$(roster_path)"
  roster_check_unique "$r"
  jq -r '.seats[]? | "\(.github)/\(.label)"' "$r"
}

# roster_row <id> [roster]: the seat's roster row as JSON, or nothing when the roster has no such row.
roster_row() {
  local r="${2:-}"; [[ -n "$r" ]] || r="$(roster_path)"
  jq -c --arg g "${1%%/*}" --arg l "${1#*/}" '.seats[]? | select(.github == $g and .label == $l)' "$r"
}

# roster_field <id> <key> [roster]: one string field of the seat's row (empty when absent).
roster_field() { roster_row "$1" "${3:-}" | jq -r --arg k "$2" '.[$k] // empty'; }

# seat_short <short | composite>: the short id <login>/<LABEL> of a seat written in either form; dies on any other shape.
seat_short() {
  local x="${1:-}"
  if [[ "$x" =~ $SEAT_IDENTITY_RE ]]; then local s="${x#*/}"; echo "${s#*/}/${s%%/*}"
  elif [[ "$x" =~ $SEAT_ID_RE ]]; then echo "$x"
  else die "seat '$x' is neither <login>/<LABEL> nor <slug>/<LABEL>/<login>"; fi
}

# seat_identity_of <short id> <slug>: the composite, from its parts.
seat_identity_of() {
  [[ "${1:-}" =~ $SEAT_ID_RE ]] || die "seat_identity_of: '${1:-}' is not a seat id"
  [[ "${2:-}" =~ $WS_SLUG_RE ]] || die "seat_identity_of: '${2:-}' is not a workstream slug"
  echo "$2/${1#*/}/${1%%/*}"
}

# seat_id_local <LABEL | login/LABEL | composite>: the short id, resolved through this repo's roster only (no
# network). A short id is validated and returned as written (self-describing). A composite must agree with the
# roster row's workstream when the row is here. A bare LABEL resolves to exactly one row of this roster; several
# dies naming their composites; none dies naming the roster's seats (status 1, so a caller can fall through).
seat_id_local() {
  local x="${1:-}" short slug row ws ids hits
  [[ -n "$x" ]] || die "no seat given (a LABEL, <login>/<LABEL> or <slug>/<LABEL>/<login>)"
  if [[ "$x" =~ $SEAT_IDENTITY_RE ]]; then
    short="$(seat_short "$x")"; slug="${x%%/*}"
    row="$(roster_row "$short")"
    if [[ -n "$row" ]]; then
      ws="$(jq -r '.workstream // empty' <<< "$row")"
      [[ "$ws" == "$slug" ]] || die "seat $short of $(roster_path) is in workstream '$ws', not '$slug' (you named $x)"
    fi
    echo "$short"; return 0
  fi
  if [[ "$x" == */* ]]; then
    [[ "$x" =~ $SEAT_ID_RE ]] || die "seat id '$x' is not <login>/<LABEL> nor <slug>/<LABEL>/<login> (login: letters, digits, -; LABEL: A-Z, 0-9, _, -; slug: a-z, 0-9, -)"
    echo "$x"; return 0
  fi
  [[ "$x" =~ $SEAT_LABEL_RE ]] || die "seat label '$x' must be upper-case letters, digits, _ or -"
  ids="$(roster_seat_ids)" || exit 1
  hits="$(printf '%s\n' "$ids" | awk -F/ -v l="$x" '$2 == l')"
  if [[ -z "$hits" ]]; then echo "daita-beast: seat '$x' is not in $(roster_path) (its seats: $(printf '%s' "$ids" | tr '\n' ' '))" >&2; return 1; fi
  [[ "$hits" != *$'\n'* ]] || die "seat label '$x' names several seats in $(roster_path): $(while IFS= read -r h; do seat_identity_of "$h" "$(roster_field "$h" workstream)"; done <<< "$hits" | tr '\n' ' ')— name one by its id"
  echo "$hits"
}

# seat_id <LABEL | login/LABEL | composite>: the short id. A bare LABEL that this roster does not hold resolves
# through every workstream's `## Seats` table (ws_seats_all): exactly one seat of that label, else dies naming the
# composites (the same label in two workstreams is two identities).
seat_id() {
  local x="${1:-}" short hits
  if short="$(seat_id_local "$x" 2>/dev/null)"; then echo "$short"; return 0; fi
  [[ "$x" =~ $SEAT_LABEL_RE ]] || { seat_id_local "$x"; exit 1; }
  hits="$(ws_seats_all | awk -F'\t' -v l="$x" 'substr($2, index($2, "/") + 1) == l {print $1 "/" l "/" substr($2, 1, index($2, "/") - 1)}')" || exit 1
  [[ -n "$hits" ]] || die "seat '$x' is not in $(roster_path) and no open workstream's \`## Seats\` table among $(workstream_user_terms) lists it; $WORKSTREAM_OWNERS_HINT"
  [[ "$hits" != *$'\n'* ]] || die "seat label '$x' names several seats: $(tr '\n' ' ' <<< "$hits")— name one by its id"
  seat_short "$hits"
}

# seat_identity <LABEL | login/LABEL | composite>: the composite. A composite is validated and returned as written
# (and must agree with this roster's row when the row is here). A short id (or a bare LABEL, resolved by seat_id)
# takes its slug from this roster's row, else from the one workstream whose `## Seats` table lists it (ws_seats_all);
# several dies naming them.
seat_identity() {
  local x="${1:-}" short ws hits
  if [[ "$x" =~ $SEAT_IDENTITY_RE ]]; then seat_id_local "$x" >/dev/null || exit 1; echo "$x"; return 0; fi
  short="$(seat_id "$x")" || exit 1
  ws="$(roster_field "$short" workstream)"
  if [[ -n "$ws" ]]; then seat_identity_of "$short" "$ws"; return 0; fi
  hits="$(ws_seats_all | awk -F'\t' -v s="$short" '$2 == s {print $1}')" || exit 1
  [[ -n "$hits" ]] || die "seat $short is not in $(roster_path) and no open workstream's \`## Seats\` table among $(workstream_user_terms) lists it; $WORKSTREAM_OWNERS_HINT"
  [[ "$hits" != *$'\n'* ]] || die "seat $short is in several workstreams: $(while IFS= read -r w; do seat_identity_of "$short" "$w"; done <<< "$hits" | tr '\n' ' ')— name one by its composite id"
  seat_identity_of "$short" "$hits"
}

seat_login() { local s; s="$(seat_short "${1:-}")" || exit 1; echo "${s%%/*}"; }
seat_label() { local s; s="$(seat_short "${1:-}")" || exit 1; echo "${s#*/}"; }

# seat_rostered <LABEL | id | composite>: the short id, dying unless it is a seat of this repo's roster.
seat_rostered() {
  local id; id="$(seat_id_local "${1:-}")" || exit 1
  roster_seat_ids | grep -qxF -- "$id" || die "seat $id is not in $(roster_path)"
  echo "$id"
}

# seat_display <id> <viewer-login>: LABEL when the seat is the viewer's own, else the id.
seat_display() { if [[ "$(seat_login "$1")" == "$2" ]]; then seat_label "$1"; else echo "$1"; fi; }

# seat_resolve <token>: a parser's resolution of a seat written in a comment or a row label (without
# "seat:"): the short id, or (a bare label that does not resolve to one seat of this roster) named on stderr and
# status 1. A qualified id in a comment (login/LABEL, or the composite) is self-describing and is read as written:
# a row in one repo is acked by seats this checkout's roster may not list. Only a bare LABEL (comments from before
# the relabel) needs the roster, and is dropped, named, when it does not resolve to exactly one seat. No network:
# a parser runs over many comments.
seat_resolve() {
  local id
  if [[ "$1" =~ $SEAT_ID_RE || "$1" =~ $SEAT_IDENTITY_RE ]]; then seat_short "$1"; return 0; fi
  id="$(seat_id_local "$1" 2>/dev/null)" || { echo "daita-beast: seat '$1' does not resolve to one seat of $(roster_path); dropped" >&2; return 1; }
  echo "$id"
}

# seat_tracking <seat>: owner/repo#N of the seat's workstream tracking issue, found by the labels of the row's
# workstream (workstream_issue); dies when the roster has no row for the seat.
seat_tracking() {
  local id ws
  id="$(seat_rostered "${1:-}")" || exit 1
  ws="$(roster_field "$id" workstream)"
  [[ -n "$ws" ]] || die "seat $id has no \"workstream\" in $(roster_path)"
  workstream_issue "$ws"
}

# ---- workstreams: the one owner of "which issue tracks workstream <slug>" and "which seats are in it" --------
# A workstream has a slug. Its tracking issue carries the labels `workstream` and `ws:<slug>`, in the master repo
# (the issue's repo: nothing stores the master or the issue number). Discovery is deterministic: exactly one open
# issue with both labels across the workstream owners (workstream_user_terms: the roster's owners plus its "workstream_owners"). The issue's `## Seats` table is the one owner of which seats
# are in the workstream, with their repo, home and agent; every other copy (the master's CLAUDE.md block, each
# home's Beast block, seats.sh list) is rendered from it.

# workstream_label_ensure <repo> <slug>: the `ws:<slug>` label, created or updated in <repo>; the one owner of its definition.
workstream_label_ensure() {
  [[ "${2:-}" =~ $WS_SLUG_RE ]] || die "'${2:-}' is not a workstream slug (a-z, 0-9, -)"
  label_ensure "$1" "ws:$2" 1D76DB "Tracking issue of workstream $2 (one per slug, open)"
}

# workstream_candidates [<slug>]: the open workstream issues among the workstream owners (workstream_user_terms) (all, or the slug's), one TSV
# line each: slug, repo, number, title, html_url. The search names candidates (its index lags a write by seconds to
# minutes); each is re-read live and kept only when open and labelled `workstream` and exactly one `ws:<slug>`;
# a dropped candidate is named on stderr. An open `workstream` issue with no `ws:` label is not a workstream of
# this model: named on stderr, never listed.
workstream_candidates() {
  local slug="${1:-}" q terms found r n info labels ws title url
  [[ -z "$slug" || "$slug" =~ $WS_SLUG_RE ]] || die "'$slug' is not a workstream slug (a-z, 0-9, -)"
  terms="$(workstream_user_terms)" || exit 1
  q="is:open is:issue label:workstream${slug:+ label:\"ws:$slug\"} $terms"
  # One search per run: a slug's lookup is a subset of the all-workstreams search, so when that result is already
  # memoized in the run cache (ws_seats_all ran) it is read instead of a second search; the live re-read below filters.
  if [[ -n "$slug" && -f "$BEAST_WS_CACHE/search-$(beast_sha "is:open is:issue label:workstream $terms")" ]]; then q="is:open is:issue label:workstream $terms"; fi
  found="$(search_issues "$q")" || die "cannot search the workstream issues: $q"
  while IFS=$'\t' read -r r n; do
    [[ -n "$r" ]] || continue
    info="$(issue_get "$r" "$n")" || exit 1
    labels="$(jq -r '[.labels[].name] | join(" ")' <<< "$info")"
    if [[ "$(jq -r .state <<< "$info")" != open ]]; then echo "daita-beast: $r#$n is closed (the search index lagged); not a workstream" >&2; continue; fi
    if [[ " $labels " != *" workstream "* ]]; then echo "daita-beast: $r#$n is not labelled workstream (the search index lagged); not a workstream" >&2; continue; fi
    ws="$(jq -r '[.labels[].name | select(startswith("ws:")) | ltrimstr("ws:")] | join(" ")' <<< "$info")"
    if [[ -z "$ws" ]]; then echo "daita-beast: $r#$n is labelled workstream but carries no ws:<slug> label: not a workstream of this model (workstream.sh new --slug makes one); skipped" >&2; continue; fi
    [[ "$ws" != *" "* ]] || die "$r#$n carries several ws: labels ($ws): a tracking issue is one workstream; remove the extra label(s)"
    [[ "$ws" =~ $WS_SLUG_RE ]] || die "$r#$n carries the label ws:$ws, which is not a slug (a-z, 0-9, -)"
    [[ -z "$slug" || "$ws" == "$slug" ]] || { echo "daita-beast: $r#$n is workstream $ws, not $slug (the search index lagged); skipped" >&2; continue; }
    title="$(jq -r '.title // ""' <<< "$info" | tr '\t\n' '  ')"; url="$(jq -r .html_url <<< "$info")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$ws" "$r" "$n" "$title" "$url"
  done < <(jq -r '.[] | select(.pull_request == null) | [(.repository_url | sub(".*/repos/"; "")), .number] | @tsv' <<< "$found")
}

# workstream_issue <slug>: owner/repo#N of the one open issue labelled workstream and ws:<slug> among the roster's
# owners; 0 or several dies naming them.
workstream_issue() {
  local slug="${1:-}" rows n
  [[ "$slug" =~ $WS_SLUG_RE ]] || die "'$slug' is not a workstream slug (a-z, 0-9, -)"
  rows="$(workstream_candidates "$slug")" || exit 1
  n="$(printf '%s' "$rows" | grep -c . || true)"
  [[ "$n" -ne 0 ]] || die "no open issue labelled workstream and ws:$slug among $(workstream_user_terms): workstream.sh new --slug $slug … opens one; $WORKSTREAM_OWNERS_HINT"
  [[ "$n" -eq 1 ]] || die "workstream $slug has $n open tracking issues, one is the rule: $(cut -f5 <<< "$rows" | tr '\n' ' ')— close the extra one(s)"
  awk -F'\t' '{print $2 "#" $3}' <<< "$rows"
}

# workstream_master <slug>: the master repo of the workstream: the repo of its tracking issue.
workstream_master() { local ref; ref="$(workstream_issue "$1")" || exit 1; echo "${ref%%#*}"; }

# ---- the `## Seats` table: one parser, one renderer -----------------------------------------------------
# | Seat | Repo | Home | Agent | Account | Address | Seen |
# The first four cells define a seat: Seat <login>/<LABEL> (the slug is the issue's), Repo owner/repo (private and
# not public-intended), Home in seat_home_path_of's vocabulary (`checkout`, `worktree <branch>`, `wrapper`, `subdir
# <dir>`), Agent an agent name. Account, Address and Seen are RENDERED from the seats' BEAST-ADDRESS comments on the
# same issue (seat_address_read): the parser reads only the first four cells as the definition and ignores the other
# three, so a hand edit of an address in the table edits nothing (the comment stays the owner).
WS_SEATS_HEADER='| Seat | Repo | Home | Agent | Account | Address | Seen |'
WS_SEATS_SEP='|---|---|---|---|---|---|---|'
WS_HOME_RE='^(checkout|wrapper|worktree [^ 	]+|subdir [^ 	]+)$'   # a bash ERE and a Python regex alike

# ws_home_word <kind> [<branch | dir>]: the Home cell of a seat: the one formula, inverse of ws_home_parse.
ws_home_word() {
  case "${1:-}" in
    checkout|wrapper) [[ -z "${2:-}" ]] || die "home kind $1 takes no argument (got '$2')"; echo "$1" ;;
    worktree) [[ -n "${2:-}" ]] || die "home kind worktree needs its branch"; echo "worktree $2" ;;
    subdir) [[ -n "${2:-}" ]] || die "home kind subdir needs its dir"; echo "subdir $2" ;;
    *) die "home kind '${1:-}' is not checkout, worktree, wrapper or subdir" ;;
  esac
}

# ws_home_parse <word>: "<kind>\t<arg>" of a Home cell; dies naming the vocabulary.
ws_home_parse() {
  [[ "${1:-}" =~ $WS_HOME_RE ]] || die "home '${1:-}' is not one of: checkout, worktree <branch>, wrapper, subdir <dir>"
  printf '%s\t%s\n' "${1%% *}" "$([[ "$1" == *" "* ]] && echo "${1#* }")"
}

# ws_seats_table_parse <who> <text>: the rows of a `## Seats` table (the section's text), one TSV line each:
# seat (short id), repo, home, agent. Parsed by shape; dies naming <who> and the line on: a missing or other
# header, a missing separator, a row that is not exactly 7 cells, a Seat that is not <login>/<LABEL>, a Repo that
# is not owner/repo, a Home outside the vocabulary, an Agent that is not an agent name, a duplicate seat, or a
# non-blank line that is not a table row. An empty table (header and separator only) is fine.
ws_seats_table_parse() {
  local who="$1"
  printf '%s\n' "$2" | WHO="$who" HDR="$WS_SEATS_HEADER" ID_RE="$SEAT_ID_RE" HOME_RE="$WS_HOME_RE" AGENT_RE="$AGENT_NAME_RE" python3 -I -c "$(cat <<'PY'
import os, re, sys
who, hdr = os.environ["WHO"], os.environ["HDR"]
id_re, home_re, agent_re = (re.compile(os.environ[k]) for k in ("ID_RE", "HOME_RE", "AGENT_RE"))
repo_re = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
def die(m): sys.exit("daita-beast: %s: `## Seats` %s" % (who, m))
def norm(l): return re.sub(r"\s*\|\s*", "|", l.strip())
lines = [l.rstrip("\r") for l in sys.stdin.read().split("\n")]
rows = [(i + 1, l) for i, l in enumerate(lines) if l.strip()]
if not rows: die("has no table: the first line must be exactly `%s`" % hdr)
if norm(rows[0][1]) != norm(hdr): die("line %d `%s`: the header must be exactly `%s`" % (rows[0][0], rows[0][1], hdr))
if len(rows) < 2 or not re.fullmatch(r"\|(:?-+:?\|){7}", norm(rows[1][1])): die("line %d `%s`: the separator row `|---|---|---|---|---|---|---|` must follow the header" % ((rows[1][0], rows[1][1]) if len(rows) > 1 else (rows[0][0] + 1, "")))
seen = {}
for n, l in rows[2:]:
    s = l.strip()
    if not (s.startswith("|") and s.endswith("|")): die("line %d `%s`: not a table row" % (n, l))
    cells = [c.strip() for c in s[1:-1].split("|")]
    if len(cells) != 7: die("line %d `%s`: %d cell(s), a row has 7 (Seat, Repo, Home, Agent, Account, Address, Seen)" % (n, l, len(cells)))
    seat, repo, home, agent = cells[:4]
    if not id_re.match(seat): die("line %d `%s`: Seat `%s` is not <login>/<LABEL> (LABEL: A-Z, 0-9, _, -)" % (n, l, seat))
    if not repo_re.match(repo): die("line %d `%s`: Repo `%s` is not owner/repo" % (n, l, repo))
    if not home_re.match(home): die("line %d `%s`: Home `%s` is not one of: checkout, worktree <branch>, wrapper, subdir <dir>" % (n, l, home))
    if not agent_re.match(agent): die("line %d `%s`: Agent `%s` is not an agent name (<name> in the repo's .claude/agents, or daita-beast:seat)" % (n, l, agent))
    if seat in seen: die("line %d `%s`: seat %s is already on line %d" % (n, l, seat, seen[seat]))
    seen[seat] = n
    print("\t".join([seat, repo, home, agent]))
PY
)" || exit 1
}

# ws_seats_parse <slug>: the `## Seats` table of the workstream's tracking issue (ws_seats_table_parse), one TSV
# line per seat: seat, repo, home, agent.
ws_seats_parse() {
  local ref r n body
  ref="$(workstream_issue "$1")" || exit 1
  r="${ref%%#*}"; n="${ref#*#}"
  body="$(issue_get "$r" "$n" | jq -r '.body // ""')" || exit 1
  ws_seats_table_parse "$ref" "$(printf '%s\n' "$body" | section Seats)"
}

# ws_seats_render <slug> <tsv>: the table, one renderer: the definition rows as given, Account, Address and Seen
# from the seats' BEAST-ADDRESS comments on the issue (seat_addresses_of). Writes nothing.
ws_seats_render() {
  local slug="$1" tsv="$2" addrs seat repo home agent a
  addrs="$(seat_addresses_of "$slug")" || exit 1
  printf '%s\n%s\n' "$WS_SEATS_HEADER" "$WS_SEATS_SEP"
  while IFS=$'\t' read -r seat repo home agent; do
    [[ -n "$seat" ]] || continue
    a="$(jq -c --arg s "$(seat_identity_of "$seat" "$slug")" 'select(.seat == $s)' <<< "$addrs" | head -1)"
    printf '| %s | %s | %s | %s | %s | %s | %s |\n' "$seat" "$repo" "$home" "$agent" \
      "$([[ -n "$a" ]] && jq -r .account <<< "$a" | cell || echo "—")" "$([[ -n "$a" ]] && jq -r .address <<< "$a" | cell || echo "—")" "$([[ -n "$a" ]] && jq -r .at <<< "$a" || echo "—")"
  done <<< "$tsv"
}

# ws_seats_write <slug> <tsv>: replaces the `## Seats` section of the tracking issue with the rendered table
# (section_replace + issue_edit_body), behind coord_write_guard. Prints the issue ref.
ws_seats_write() {
  local slug="$1" tsv="$2" ref r n body table tmp
  ref="$(workstream_issue "$slug")" || exit 1
  r="${ref%%#*}"; n="${ref#*#}"
  coord_write_guard "$r"
  body="$(issue_get "$r" "$n" | jq -r '.body // ""')" || exit 1
  table="$(ws_seats_render "$slug" "$tsv")" || exit 1
  tmp="$(mktemp)"
  printf '%s\n' "$body" | section_replace Seats "$table" > "$tmp"
  issue_edit_body "$r" "$n" "$tmp"; rm -f "$tmp"
  rm -f "$BEAST_WS_CACHE/ws-seats.tsv"   # the table changed: the run's memo of it is stale
  echo "$ref"
}

# ws_seats_all: every seat of every open workstream among the workstream owners (workstream_user_terms), one TSV line each: slug, seat
# (short id), repo, home, agent, tracking (owner/repo#N), title. The one enumeration of "all seats" (seats.sh list,
# seat_id's bare-label fallback, seat_repo for a seat of another repo): the workstream issues replace any roster as
# an index of other repos' seats. Computed once per run ($BEAST_WS_CACHE/ws-seats.tsv; one search, one read per
# workstream issue) and served from there after; ws_seats_write, the table's one writer, forgets it.
ws_seats_all() {
  local slug r n title url body rows cands err memo="$BEAST_WS_CACHE/ws-seats.tsv"
  if [[ -f "$memo" ]]; then cat "$memo"; return 0; fi
  # The candidates first, as a value: a search that fails (a rate limit, GitHub down) fails this enumeration loud,
  # never an empty seat list a caller would take for "no seats".
  cands="$(workstream_candidates)" || exit 1
  while IFS=$'\t' read -r slug r n title url; do
    [[ -n "$slug" ]] || continue
    if ! body="$(issue_get "$r" "$n" 2>"$BEAST_WS_CACHE/ws-read.err")"; then
      err="$(cat "$BEAST_WS_CACHE/ws-read.err")"
      # A rate limit is everyone's, not this workstream's: the enumeration fails. Any other unreadable issue is skipped, named.
      ! rate_limit_text "$err" || { echo "$err" >&2; exit 1; }
      fault_once "ws-read:$r#$n" "daita-beast: workstream $slug ($r#$n): its tracking issue cannot be read; skipped by ws_seats_all ($(tr '\n' ' ' <<< "${err#daita-beast: }"))"; continue
    fi
    cat "$BEAST_WS_CACHE/ws-read.err" >&2
    body="$(jq -r '.body // ""' <<< "$body")" || exit 1
    if ! rows="$(ws_seats_table_parse "$r#$n" "$(printf '%s\n' "$body" | section Seats)" 2>&1)"; then
      # one repo's malformed table never blinds every seat on the machine: named, skipped (once per distinct message where
      # the caller keeps a fault ledger, fault_once); ws_seats_parse <slug> still dies on it
      fault_once "ws-seats:$r#$n" "daita-beast: workstream $slug ($r#$n): its \`## Seats\` table does not parse; skipped by ws_seats_all (${rows#daita-beast: })"; continue
    fi
    fault_clear "ws-seats:$r#$n" "daita-beast: workstream $slug ($r#$n): its \`## Seats\` table parses again"
    fault_clear "ws-read:$r#$n" ""
    [[ -z "$rows" ]] || awk -F'\t' -v s="$slug" -v t="$r#$n" -v ti="$title" 'NF {print s "\t" $0 "\t" t "\t" ti}' <<< "$rows"
  done <<< "$cands" > "$memo.tmp" || { rm -f "$memo.tmp"; exit 1; }
  mv -f "$memo.tmp" "$memo"
  cat "$memo"
}

# ---- faults named once: a scheduled caller's ledger ------------------------------------------------------------
# A job that runs every tick (the relay's watch.sh) would otherwise write the same skipped-workstream line 720 times a
# day. Such a caller exports BEAST_FAULT_LEDGER=<file> (JSON {key: {sha, first, last, n}}); fault_once then prints a
# fault on stderr the first time it is seen and again only when its message changes, and counts the repeats; without
# the variable (a person's run) every fault is printed. fault_clear forgets a key whose fault is gone, saying so once.
fault_once() {
  local key="$1" msg="$2" f="${BEAST_FAULT_LEDGER:-}" sha t
  if [[ -z "$f" ]]; then printf '%s\n' "$msg" >&2; return 0; fi
  sha="$(beast_sha "$msg")"; mkdir -p "$(dirname "$f")"; [[ -s "$f" ]] || echo '{}' > "$f"
  if [[ "$(jq -r --arg k "$key" '.[$k].sha // ""' "$f" 2>/dev/null)" == "$sha" ]]; then
    t="$(mktemp "$f.XXXXXX")"; jq --arg k "$key" --arg at "$(utc_now)" '.[$k].n += 1 | .[$k].last = $at' "$f" > "$t" && mv -f "$t" "$f"
    return 0
  fi
  t="$(mktemp "$f.XXXXXX")"
  jq --arg k "$key" --arg s "$sha" --arg at "$(utc_now)" '.[$k] = {sha: $s, first: $at, last: $at, n: 1}' "$f" > "$t" 2>/dev/null \
    || { rm -f "$t"; echo "daita-beast: the fault ledger $f is not JSON; fix or delete it" >&2; printf '%s\n' "$msg" >&2; return 0; }
  mv -f "$t" "$f"
  printf '%s (named once; repeats are counted in %s)\n' "$msg" "$f" >&2
}
fault_clear() {
  local key="$1" msg="${2:-}" f="${BEAST_FAULT_LEDGER:-}" t
  [[ -n "$f" && -s "$f" ]] || return 0
  [[ "$(jq -r --arg k "$key" 'has($k)' "$f" 2>/dev/null)" == true ]] || return 0
  t="$(mktemp "$f.XXXXXX")"; jq --arg k "$key" 'del(.[$k])' "$f" > "$t" && mv -f "$t" "$f"
  [[ -z "$msg" ]] || printf '%s\n' "$msg" >&2
}

# rate_limit_text "<stderr text>": status 0 when GitHub's answer was a rate limit (the primary quota, which gh_request
# names "quota: resets at", or the secondary burst limit, or a 429), 1 otherwise. The one reader of that fact.
rate_limit_text() { grep -qiE 'quota: resets at|secondary rate limit|rate limit exceeded|HTTP 429' <<< "${1:-}"; }

# ---- a seat's address: the one owner is its BEAST-ADDRESS comment on its workstream tracking issue -------------
# BEAST-ADDRESS seat=<composite> account=<claude account> address="<name>[ [ref]]" machine=<hostname> at=<UTC>
# One comment per seat, by the seat's login, edited in place (seats.sh record, seats.sh touch); ~/.beast/sessions.json
# is a machine-local cache of it, keyed by the composite, never the owner. address_header writes the line,
# seat_addresses_of reads every seat's on one issue, seat_address_read one seat's. A SendMessage address is minted per
# session on one machine, so it reaches a seat only from the same machine and the same Claude account: seats.sh address
# says which path applies (direct, or the recipient's desk).
ADDRESS_HEADER_RE='^BEAST-ADDRESS seat=(?<seat>[a-z0-9][a-z0-9-]*/[A-Z0-9_-]+/[A-Za-z0-9-]+) account=(?<account>[^ ]+) address="(?<address>[^"]+)" machine=(?<machine>[^ ]+) at=(?<at>[^ ]+)$'
ADDRESS_FRESH_S=86400   # "fresh" approximates "recorded after the recipient's newest SessionStart" as "within 24h"

# The address itself: the session's ListAgents name, optionally followed by " [<ref>]" (6 hex digits) as ListAgents
# prints it. The name is the `name` of the session's ~/.claude/sessions file (claude_session_of), which carries no ref;
# SendMessage takes the bare name when it is unique among the live sessions. A name may hold spaces and slashes, never
# a bracket, a double quote or a control character, and starts and ends with a non-space. ADDRESS_RE is the one owner
# of the shape (an Oniguruma regex, read through jq): address_parse, address_header and seat_addresses_at use it.
ADDRESS_RE='^(?<name>[^\s\[\]"\x00-\x1f](?:[^\[\]"\x00-\x1f]*[^\s\[\]"\x00-\x1f])?)(?: \[(?<ref>[0-9a-f]{6})\])?$'

# address_parse <address>: "<name>\t<ref or empty>"; dies naming the shape.
address_parse() {
  local p
  p="$(jq -rn --arg a "${1:-}" --arg re "$ADDRESS_RE" '$a | capture($re) // empty | "\(.name)\t\(.ref // "")"')" || die "address_parse: jq failed on '${1:-}'"
  [[ -n "$p" ]] || die "address '${1:-}' is not of the shape 'name' or 'name [ref]' (the session's ListAgents name, optionally with the 6-hex ref ListAgents prints; no bracket, double quote or control character in the name)"
  printf '%s\n' "$p"
}
# address_name <address>: the name part (what SendMessage is sent to, and what a live session's name is compared with).
address_name() { local p; p="$(address_parse "${1:-}")" || exit 1; printf '%s\n' "${p%%$'\t'*}"; }

# ---- Claude Code's session files: the one reader ------------------------------------------------------------------
# Claude Code writes one file per running session, ~/.claude/sessions/<pid>.json (measured 2026-10-21):
#   {"pid":34914,"sessionId":"17efc626-…","cwd":"/Users/…","name":"unkamon-14","nameSource":"derived","status":"idle",…}
# `name` is the session's ListAgents name. This is an undocumented Claude Code internal, so it is read here only, and
# every field used is shape-checked on every read: a file that is not JSON, or lacks pid (a positive integer),
# sessionId, name, cwd (an absolute path) or status (non-empty strings), dies naming the file and the field.
# A file whose pid is dead is a leftover of a killed session; claude_sessions_live drops it (kill -0).
claude_sessions_dir() { echo "$HOME/.claude/sessions"; }

# claude_sessions_read: every session file, one JSON object per line {session, name, pid, cwd, status, file, alive}.
claude_sessions_read() {
  local d f o bad
  d="$(claude_sessions_dir)"
  [[ -d "$d" ]] || die "no $d: Claude Code writes one file per running session there; this Claude Code writes none (its session files are an undocumented internal: the address cannot be read)"
  for f in "$d"/*.json; do
    [[ -e "$f" ]] || continue
    o="$(jq -c --arg f "$f" '
      if type != "object" then {bad: "not a JSON object"}
      elif ((.pid | type) != "number") or (.pid < 1) or (.pid != (.pid | floor)) then {bad: "field pid (a positive integer) missing or of another shape"}
      elif ((.sessionId | type) != "string") or (.sessionId == "") then {bad: "field sessionId (a string) missing or of another shape"}
      elif ((.name | type) != "string") or (.name == "") then {bad: "field name (a string) missing or of another shape"}
      elif ((.cwd | type) != "string") or ((.cwd | startswith("/")) | not) then {bad: "field cwd (an absolute path) missing or of another shape"}
      elif ((.status | type) != "string") or (.status == "") then {bad: "field status (a string) missing or of another shape"}
      else {session: .sessionId, name, pid, cwd, status, file: $f} end' "$f" 2>/dev/null)" || die "the Claude Code session file $f is not JSON: its shape changed, or it is being written (an undocumented internal; the address cannot be read)"
    bad="$(jq -r '.bad // empty' <<< "$o")"
    [[ -z "$bad" ]] || die "the Claude Code session file $f: $bad (an undocumented internal whose shape changed; the address cannot be read)"
    if kill -0 "$(jq -r .pid <<< "$o")" 2>/dev/null; then jq -c '. + {alive: true}' <<< "$o"; else jq -c '. + {alive: false}' <<< "$o"; fi
  done
}

# claude_sessions_live: claude_sessions_read, only the entries whose pid is alive.
claude_sessions_live() { local all; all="$(claude_sessions_read)" || exit 1; [[ -z "$all" ]] || jq -c 'select(.alive)' <<< "$all"; }

# claude_session_of <session id>: that session's {session, name, pid, cwd, status, file, alive} as one JSON line; dies
# when no file names it, or when two live files do. A file whose pid is dead is returned (alive false) only when no live
# one names the session: the caller decides what a dead session means.
claude_session_of() {
  local sid="${1:-}" all hits n
  [[ -n "$sid" ]] || die "claude_session_of: no session id"
  all="$(claude_sessions_read)" || exit 1
  hits="$( [[ -z "$all" ]] || jq -c --arg s "$sid" 'select(.session == $s)' <<< "$all")"
  [[ -n "$hits" ]] || die "no Claude Code session file in $(claude_sessions_dir) names session $sid"
  n="$(jq -s 'map(select(.alive)) | length' <<< "$hits")"
  [[ "$n" -le 1 ]] || die "$n live Claude Code session files in $(claude_sessions_dir) name session $sid: $(jq -rs 'map(select(.alive) | .file) | join(" and ")' <<< "$hits")"
  jq -sc 'sort_by(if .alive then 0 else 1 end) | .[0]' <<< "$hits"
}

# claude_name_holders <name>: how many live sessions carry the name (1 is a unique, sendable address; more is
# ambiguous: SendMessage to the bare name cannot tell them apart).
claude_name_holders() { local l; l="$(claude_sessions_live)" || exit 1; [[ -z "$l" ]] && echo 0 || jq -s --arg n "$1" 'map(select(.name == $n)) | length' <<< "$l"; }

# claude_account: the Claude account this machine's sessions run as: oauthAccount.emailAddress of ~/.claude.json
# (BEAST_CLAUDE_JSON moves the file); dies naming the file when it or the field is absent.
claude_account() {
  local f="${BEAST_CLAUDE_JSON:-$HOME/.claude.json}" a
  [[ -f "$f" ]] || die "no $f: the Claude account (oauthAccount.emailAddress) is read from it; sign in to Claude Code on this machine first"
  a="$(jq -r '.oauthAccount.emailAddress // empty' "$f" 2>/dev/null)" || die "$f is not JSON"
  [[ -n "$a" && "$a" != *" "* ]] || die "$f has no oauthAccount.emailAddress: sign in to Claude Code on this machine first"
  echo "$a"
}

# address_header <composite> <account> <address> <machine> <at>: the first line of a BEAST-ADDRESS comment.
address_header() {
  [[ "${1:-}" =~ $SEAT_IDENTITY_RE ]] || die "address_header: '${1:-}' is not <slug>/<LABEL>/<login>"
  address_parse "${3:-}" >/dev/null || exit 1
  local l="BEAST-ADDRESS seat=$1 account=$2 address=\"$3\" machine=$4 at=$5"
  jq -en --arg l "$l" --arg re "$ADDRESS_HEADER_RE" '$l | test($re)' >/dev/null || die "address_header: '$l' is not the BEAST-ADDRESS shape"
  printf '%s\n' "$l"
}

# address_age <at>: "<n>s|m|h|d ago" and, after a tab, fresh|stale, for an ISO time.
address_age() {
  local t s
  t="$(jq -rn --arg a "$1" '$a | fromdate' 2>/dev/null)" || die "address_age: '$1' is not an ISO time"
  s=$(( $(date -u +%s) - t ))
  printf '%s\t%s\n' "$( if (( s < 60 )); then echo "${s}s ago"; elif (( s < 3600 )); then echo "$((s/60))m ago"; elif (( s < 86400 )); then echo "$((s/3600))h ago"; else echo "$((s/86400))d ago"; fi)" "$( (( s <= ADDRESS_FRESH_S )) && echo fresh || echo stale)"
}

# seat_addresses_of <slug>: every well-formed BEAST-ADDRESS comment on the workstream's tracking issue, one JSON
# object per line {seat, account, address, name, ref, machine, at, url, id, by} (name and ref from ADDRESS_RE; ref null
# for a bare name), in comment order; a comment whose first line starts with BEAST-ADDRESS and is not the shape (its
# address included), or that names a seat whose login is not its author, is named on stderr and dropped.
seat_addresses_of() {
  local ref
  ref="$(workstream_issue "$1")" || exit 1
  seat_addresses_at "$ref"
}

# seat_addresses_at <owner/repo#N>: seat_addresses_of for a tracking issue already known (one comments read, no search).
seat_addresses_at() {
  local ref="$1" r n
  [[ "$ref" =~ ^[^/#]+/[^/#]+#[0-9]+$ ]] || die "seat_addresses_at: '$ref' is not owner/repo#N"
  r="${ref%%#*}"; n="${ref#*#}"
  local cs; cs="$(issue_comments "$r" "$n")" || die "cannot read the comments of $ref (named above)"
  jq -c --arg re "$ADDRESS_HEADER_RE" --arg are "$ADDRESS_RE" '
    .[] | . as $c | ((.body // "") | split("\n")[0] | sub("\\s+$"; "")) as $f
    | select($f | startswith("BEAST-ADDRESS"))
    | ($f | capture($re) // null) as $h
    | (if $h == null then null else ($h.address | capture($are) // null) as $n | if $n == null then null else $h + {name: $n.name, ref: $n.ref} end end) as $a
    | if $a == null then {bad: "malformed BEAST-ADDRESS line (the header, or an address that is not name or name [ref]): \($c.html_url)"}
      elif ($a.seat | split("/")[2]) != $c.user.login then {bad: "BEAST-ADDRESS for \($a.seat) by \($c.user.login), not the seat'"'"'s login: \($c.html_url)"}
      else $a + {url: $c.html_url, id: $c.id, by: $c.user.login} end' <<< "$cs" \
    | while IFS= read -r o; do
        if [[ "$(jq -r '.bad // empty' <<< "$o")" != "" ]]; then echo "daita-beast: $ref: $(jq -r .bad <<< "$o"); dropped" >&2; else printf '%s\n' "$o"; fi
      done
}

# seat_address_read <composite>: the seat's one BEAST-ADDRESS comment as JSON, or nothing when none; two dies naming them.
seat_address_read() {
  local id="$1" slug got n
  [[ "$id" =~ $SEAT_IDENTITY_RE ]] || die "seat_address_read takes a composite id, not '$id'"
  slug="${id%%/*}"
  got="$(seat_addresses_of "$slug" | jq -c --arg s "$id" 'select(.seat == $s)' | jq -sc .)" || exit 1
  n="$(jq length <<< "$got")"
  [[ "$n" -le 1 ]] || die "$id has $n BEAST-ADDRESS comments: $(jq -r '[.[].url] | join(" and ")' <<< "$got") — delete all but one by hand"
  [[ "$n" -eq 0 ]] || jq -c '.[0]' <<< "$got"
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

# seat_repo <LABEL | id | composite>: the owner/repo the seat works in, where its desk and milestones are: this
# roster's row when the seat is rostered here (no network), else the Repo cell of its row in its workstream's
# `## Seats` table (ws_seats_all). A seat of another repo is found there, never in this roster; dies when neither
# has it. A caller that means its OWN seat resolves it with seat_rostered first.
seat_repo() {
  local x="${1:-}" id r identity slug
  id="$(seat_id "$x")" || exit 1
  r="$(roster_field "$id" repo)"
  if [[ -n "$r" ]]; then
    [[ "$r" =~ ^[^/]+/[^/]+$ ]] || die "seat $id: roster row has no \"repo\" (owner/repo), got '$r'"
    echo "$r"; return 0
  fi
  identity="$(seat_identity "$x")" || exit 1; slug="${identity%%/*}"
  r="$(ws_seats_all | awk -F'\t' -v s="$slug" -v i="$id" '$1 == s && $2 == i {print $3}')" || exit 1
  [[ -n "$r" ]] || die "seat $identity is in no \`## Seats\` table of an open workstream among $(workstream_user_terms) (workstream.sh seat-add $slug $id … adds it; $WORKSTREAM_OWNERS_HINT)"
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

# ---- seats on this machine: the one owner of finding a seat from any directory -------------------
# A session starts in its launch folder (the folder the window was launched in) and its shell returns there after
# every command. Seating sets the root: a seat is found from wherever the session runs, through the checkouts this
# machine can name (beast_checkouts), and its home is then derived as above from the checkout of its own repo.

# The machine-local index of checkouts with a roster (never committed): { "<main checkout>": {recorded_at} }.
checkouts_path() { echo "${BEAST_CHECKOUTS_FILE:-$HOME/.beast/checkouts.json}"; }

# checkouts_record <main checkout>: adds it to the index (seat.sh new, join.sh and bootstrap.sh call this).
checkouts_record() {
  local p f t
  p="$(cd "$1" 2>/dev/null && pwd -P)" || die "checkouts_record: $1 is not a directory"
  f="$(checkouts_path)"; mkdir -p "$(dirname "$f")"
  [[ -s "$f" ]] || echo '{}' > "$f"
  t="$(mktemp "$f.XXXXXX")"
  jq --arg p "$p" --arg at "$(utc_now)" '.[$p] = {recorded_at:$at}' "$f" > "$t" || { rm -f "$t"; die "the checkout index $f is not JSON; fix or delete it"; }
  mv -f "$t" "$f"
}

# The machine-local record of the installed plugin (never committed): ~/.beast/plugin.json {root, version, recorded_at},
# written by the install skill through plugin_root_record and read through plugin_root_recorded, nowhere else.
plugin_json_path() { echo "${BEAST_PLUGIN_FILE:-$HOME/.beast/plugin.json}"; }

# plugin_root_recorded: the plugin directory ~/.beast/plugin.json records (the one reader of that file); dies naming
# the install skill when the file is absent, and naming the file when it is not JSON or names no plugin directory.
plugin_root_recorded() {
  local f r
  f="$(plugin_json_path)"
  [[ -s "$f" ]] || die "no plugin root: CLAUDE_PLUGIN_ROOT is unset and $f is absent: run the install skill (/daita-beast:install)"
  r="$(jq -r '.root // empty' "$f" 2>/dev/null)" || die "$f is not JSON: fix or delete it, then run the install skill (/daita-beast:install)"
  [[ -n "$r" && -d "$r/scripts" ]] || die "$f names no plugin directory with a scripts/ folder (got '$r'): run the install skill (/daita-beast:install)"
  echo "$r"
}

# plugin_root: the plugin directory this machine runs Beast from: $CLAUDE_PLUGIN_ROOT when set (the running plugin,
# a --plugin-dir checkout included), else the recorded one. The relay plist, install-relay.sh, permit.sh and
# seat-hello.sh consume it; nothing else derives the path.
plugin_root() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then echo "$CLAUDE_PLUGIN_ROOT"; return 0; fi
  plugin_root_recorded
}

# plugin_root_record <plugin dir>: the one writer of ~/.beast/plugin.json. The dir must be the plugin
# (.claude-plugin/plugin.json with a version, and scripts/); prints the file, root and version written.
plugin_root_record() {
  local d f t v
  d="$(cd "${1:-}" 2>/dev/null && pwd -P)" || die "plugin_root_record: '${1:-}' is not a directory"
  [[ -f "$d/.claude-plugin/plugin.json" && -d "$d/scripts" ]] || die "plugin_root_record: $d is not the daita-beast plugin (needs .claude-plugin/plugin.json and scripts/)"
  v="$(jq -r '.version // empty' "$d/.claude-plugin/plugin.json" 2>/dev/null)" || die "plugin_root_record: $d/.claude-plugin/plugin.json is not JSON"
  [[ -n "$v" ]] || die "plugin_root_record: $d/.claude-plugin/plugin.json has no version"
  f="$(plugin_json_path)"; mkdir -p "$(dirname "$f")"
  t="$(mktemp "$f.XXXXXX")"
  jq -n --arg r "$d" --arg v "$v" --arg at "$(utc_now)" '{root:$r, version:$v, recorded_at:$at}' > "$t"
  mv -f "$t" "$f"
  echo "$f: root $d, version $v"
}

# vscode_workspace_folders <launch dir>: the folders (real paths, one per line, deduplicated) of every *.code-workspace
# file found walking up from the launch dir to $HOME (to / when the launch dir is not under $HOME) whose folders[] list
# contains the launch dir in ANY position (each path resolved against the file's directory); nothing when none.
# Every listing file contributes: the launch dir alone cannot tell which window opened it, and the hook claims no seat.
# A workspace file that is not JSONC dies naming it.
vscode_workspace_folders() {
  python3 - "$1" <<'PY'
import glob, json, os, re, sys
launch = os.path.realpath(sys.argv[1])
home = os.path.realpath(os.path.expanduser("~"))
def jsonc(s):
    out, i, n, ins = [], 0, len(s), False
    while i < n:
        c = s[i]
        if ins:
            out.append(c)
            if c == "\\" and i + 1 < n: out.append(s[i + 1]); i += 2; continue
            if c == '"': ins = False
            i += 1; continue
        if c == '"': ins = True; out.append(c); i += 1; continue
        if s.startswith("//", i): j = s.find("\n", i); i = n if j < 0 else j; continue
        if s.startswith("/*", i): j = s.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        out.append(c); i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))
seen = []
d = launch
while True:
    for f in sorted(glob.glob(os.path.join(d, "*.code-workspace"))):
        try: w = json.loads(jsonc(open(f).read()))
        except Exception as e: sys.exit("daita-beast: cannot read the VS Code workspace %s: %s" % (f, e))
        fs = [os.path.realpath(os.path.join(os.path.dirname(f), os.path.expanduser(x["path"])))
              for x in w.get("folders", []) if isinstance(x, dict) and "path" in x]
        if launch in fs:
            for x in fs:
                if x not in seen: seen.append(x); print(x)
    if d == home or os.path.dirname(d) == d: break
    d = os.path.dirname(d)
PY
}

# beast_checkouts <launch dir> [workspace|machine|all]: the main checkouts carrying .beast/roster.json, real paths,
# one per line, deduplicated: the launch dir's own checkout, then the VS Code workspace's folders (workspace, all)
# and the machine index (machine, all). Default all. A folder that is not a checkout is not one.
beast_checkouts() {
  local launch="$1" scope="${2:-all}" d ws="" ix="" out=""
  if [[ "$scope" != machine ]]; then ws="$(vscode_workspace_folders "$launch")" || exit 1; fi
  if [[ "$scope" != workspace && -s "$(checkouts_path)" ]]; then
    ix="$(jq -r 'keys[]' "$(checkouts_path)")" || die "the checkout index $(checkouts_path) is not JSON; fix or delete it"
  fi
  while IFS= read -r d; do
    [[ -n "$d" && -d "$d" ]] || continue
    d="$(cd "$d" && repo_main_root 2>/dev/null)" || continue
    [[ -f "$d/.beast/roster.json" ]] || continue
    out+="$(cd "$d" && pwd -P)"$'\n'
  done < <(printf '%s\n%s\n%s\n' "$launch" "$ws" "$ix")
  printf '%s' "$out" | awk 'NF && !seen[$0]++'
}

# seat_homes_on_machine <launch dir> [scope]: one TSV line per seat whose row sits in the roster of the checkout of
# its own repo (a row with a home, or a row written before homes): id, checkout, home, kind, workstream, retired
# (a date, or empty). The home is seat_home_path_of, the one formula. A row is read only from a roster that passes
# roster_check_unique (so every row carries a workstream slug and an identity can be built from it); a checkout
# whose roster fails it is named once on stderr and not searched: an old-shape roster (no workstream) yields no
# identity, never one with an empty slug.
seat_homes_on_machine() {
  local c slug g l k dir ws ret cs rows h why
  cs="$(beast_checkouts "$1" "${2:-all}")" || exit 1
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    slug="$(repo_slug "$c" 2>/dev/null)" || continue
    if ! why="$(roster_check_unique "$c/.beast/roster.json" 2>&1)"; then
      echo "daita-beast: $c: roster fails the 1.5.0 check: ${why#daita-beast: }; not searched" >&2; continue
    fi
    # Fields split on US (0x1f): a tab is IFS whitespace, so an empty dir would shift the later fields into it.
    rows="$(jq -r --arg s "$slug" '.seats[]? | select(.repo == $s and ((has("home") | not) or (.home | type) == "object"))
      | [.github, .label, (if has("home") then (.home.kind // "MISSING") else "checkout" end), (.home.dir? // ""), ((.workstream // "") | tostring), ((.retired // "") | tostring)] | join("\u001f")' "$c/.beast/roster.json")" \
      || die "cannot read the roster $c/.beast/roster.json"
    while IFS=$'\x1f' read -r g l k dir ws ret; do
      [[ -n "$g" ]] || continue
      h="$(seat_home_path_of "$k" "$g" "$l" "$c" "$dir")" || die "seat $g/$l in $c/.beast/roster.json: no home path (named above)"
      printf '%s/%s\t%s\t%s\t%s\t%s\t%s\n' "$g" "$l" "$c" "$h" "$k" "$ws" "$ret"
    done <<< "$rows"
  done <<< "$cs"
}

# seat_home_on_machine <identity>: the home path on this machine of the seat <slug>/<LABEL>/<login> (seat_homes_on_machine
# over every checkout the machine index names, the one formula), or nothing when no roster here names it.
seat_home_on_machine() {
  [[ "${1:-}" =~ $SEAT_IDENTITY_RE ]] || die "seat_home_on_machine takes <slug>/<LABEL>/<login>, not '${1:-}'"
  local short; short="$(seat_short "$1")" || exit 1
  seat_homes_on_machine "$PWD" machine | awk -F'\t' -v s="$short" -v w="${1%%/*}" '$1 == s && $5 == w && !d {print $3; d = 1}'
}

# seat_locate <LABEL | login/LABEL | composite> <launch dir>: "<id>\t<main checkout>" of the one seat it names on this
# machine; when there is none, dies naming the rosters it searched and the seat skill that creates it, or, for a seat
# some roster here names for a repo with no checkout on this machine, the clone and seat.sh new steps; dies naming
# the candidates' composites when a bare LABEL or a short id names several seats (the same label in two
# workstreams is two identities) or a seat is rostered in two checkouts.
seat_locate() {
  local want="$1" launch="$2" rows hits ids repo seen c slug="" name
  if [[ "$want" =~ $SEAT_IDENTITY_RE ]]; then slug="${want%%/*}"; want="$(seat_short "$want")"; fi
  [[ "$want" =~ $SEAT_LABEL_RE || "$want" =~ $SEAT_ID_RE ]] || die "seat '$want' is not a LABEL (A-Z, 0-9, _, -), <login>/<LABEL> nor <slug>/<LABEL>/<login>"
  rows="$(seat_homes_on_machine "$launch")" || exit 1
  hits="$(printf '%s\n' "$rows" | awk -F'\t' -v w="$want" -v s="$slug" 'NF && ($1 == w || (w !~ /\// && substr($1, index($1, "/") + 1) == w)) && (s == "" || $5 == s) {print $1 "\t" $2 "\t" $5}')"
  if [[ -z "$hits" ]]; then
    seen="$(beast_checkouts "$launch")" || exit 1
    repo="$(while IFS= read -r c; do [[ -z "$c" ]] || jq -r --arg w "$want" '.seats[]? | select("\(.github)/\(.label)" == $w or .label == $w) | .repo // empty' "$c/.beast/roster.json"; done <<< "$seen" | sort -u | head -1)"
    name="${slug:+$slug/${want#*/}/}${slug:+${want%%/*}}${slug:-$want}"
    [[ -z "$repo" ]] || die "seat $name is rostered for $repo, but no checkout of $repo on this machine carries its row (checkouts read: $(paste -sd ' ' - <<< "$seen")): clone it (git clone https://github.com/$repo <path>) and run $BEAST_SCRIPTS/seat.sh new $(printf '%s' "${want#*/}") --repo-path <path>, which makes the home the roster records"
    seen="$(awk 'NF {print $0 "/.beast/roster.json"}' <<< "$seen" | paste -sd ' ' -)"
    die "no seat $name in any roster this machine can name (searched: ${seen:-none}); to create it: /daita-beast:seat $(printf '%s' "${want#*/}")"
  fi
  ids="$(awk -F'\t' '{print $3 "/" substr($1, index($1, "/") + 1) "/" substr($1, 1, index($1, "/") - 1)}' <<< "$hits" | sort -u)"
  [[ "$ids" != *$'\n'* ]] || die "seat '${1}' names several seats on this machine: $(tr '\n' ' ' <<< "$ids")— name one by its composite id"
  [[ "$hits" != *$'\n'* ]] || die "seat $ids is rostered in several checkouts on this machine: $(cut -f2 <<< "$hits" | tr '\n' ' ')— one checkout per repo, or remove the extra one from $(checkouts_path)"
  cut -f1,2 <<< "$hits"
}

# ---- auto-memory: the one owner of "which memory folder this session loads" and "what in it restates seat state" --
# Claude Code keeps a session's transcript and auto-memory under ~/.claude/projects/<encoded launch folder>/, the
# launch folder's path with every character but A-Z, a-z, 0-9 and - replaced by -. Every seat started in one folder
# shares it, so it holds only lessons true for all of them and short pointers; a seat's state lives on GitHub.

# claude_project_dir <dir>: Claude Code's project folder for sessions started in <dir> (their transcripts, <id>.jsonl).
claude_project_dir() { echo "$HOME/.claude/projects/$(printf '%s' "$1" | sed 's#[^A-Za-z0-9-]#-#g')"; }
# automemory_dir <dir>: Claude Code's auto-memory directory for sessions started in <dir>.
automemory_dir() { echo "$(claude_project_dir "$1")/memory"; }

# session_memory_dir <launch dir>: "<dir>\t<how it was found>" of the auto-memory THIS session loads: the project
# folder holding this session's transcript ($CLAUDE_CODE_SESSION_ID.jsonl), else, outside a Claude Code session or
# before its transcript exists, automemory_dir of the launch dir, saying so. Two folders holding the transcript dies.
session_memory_dir() {
  local sid="${CLAUDE_CODE_SESSION_ID:-}" hits n
  if [[ -n "$sid" ]]; then
    hits="$(find "$HOME/.claude/projects" -mindepth 2 -maxdepth 2 -name "$sid.jsonl" 2>/dev/null || true)"
    n="$(printf '%s' "$hits" | grep -c . || true)"
    [[ "$n" -le 1 ]] || die "session $sid has a transcript in $n project folders: $(tr '\n' ' ' <<< "$hits")— cannot tell which memory it loads"
    if [[ "$n" -eq 1 ]]; then printf '%s\t%s\n' "$(dirname "$hits")/memory" "the project folder of this session ($sid)"; return 0; fi
  fi
  printf '%s\t%s\n' "$(automemory_dir "$1")" "the launch folder $1 (${sid:+no transcript of session $sid under $HOME/.claude/projects; }derived as Claude Code encodes it)"
}

# MEMORY_POINTER_MAX: the body size (bytes, after the frontmatter) up to which a memory file citing a tracking issue
# (owner/repo#N) is a pointer, kept; one index line of MEMORY.md is always under it.
MEMORY_POINTER_MAX=1200

# memory_triage <memory dir> <joining seat id> [<other seat id>]...: one TSV line per memory file and per MEMORY.md
# index line: verdict, name (the file, or MEMORY.md:<line>), detail. The verdicts, in this order:
#   lesson   the file's frontmatter type (else its name prefix) is feedback, user or reference; an index line
#            linking such a file. Never flagged.
#   owned    names another seat and not the joining seat: its login/LABEL or composite, "<LABEL> seat" or "seat
#            <LABEL>", or its LABEL in the file's name (the index line's link); detail is that seat. It is never the
#            joining seat's to delete.
#   pointer  cites a tracking issue (owner/repo#N) within MEMORY_POINTER_MAX bytes. Kept.
#   state    restates seat STATE (a handoff, a recorded address, branch or worktree state, inbox items, a next act):
#            detail is what matched. The only verdict join tells the seat to act on.
#   clean    none of the above.
memory_triage() {
  MEMORY_POINTER_MAX="$MEMORY_POINTER_MAX" python3 -I - "$@" <<'PY'
import os, re, sys
d, me, others = sys.argv[1], sys.argv[2], sys.argv[3:]
cap = int(os.environ["MEMORY_POINTER_MAX"])
LESSON = {"feedback", "user", "reference"}
REF = re.compile(r"\b[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+\b")
STATE = [("handoff", r"\bhandoff\b|BEAST-STATUS|state=handoff"), ("next act", r"\bnext act\b|\bnext step\b"),
         ("inbox", r"\binbox\b"), ("address", r"BEAST-ADDRESS|ListAgents|\[[0-9a-f]{6,}\]"),
         ("branch/worktree", r"\bworktree\b|\b(on|at) (the )?branch\b|\bbranch [A-Za-z0-9._-]+/|\buncommitted\b|\bunpushed\b")]
def names(text, title, sid):
    login, label = sid.split("/", 1); L = re.escape(label); w = r"(?<![A-Za-z0-9_/-])%s(?![A-Za-z0-9_-])" % L
    if re.search(re.escape(sid), text) or re.search(r"[a-z0-9][a-z0-9-]*/%s/%s" % (L, re.escape(login)), text): return True
    if re.search(r"%s(?:'s)? seat\b|\bseats? %s" % (w, w), text): return True
    t = "-" + re.sub(r"[^a-z0-9]+", "-", title.lower()) + "-"
    return ("-" + re.sub(r"[^a-z0-9]+", "-", label.lower()) + "-") in t
def split(text):
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
    return (m.group(1), m.group(2)) if m else ("", text)
def ftype(name, front):
    m = re.search(r"^\s*type:\s*([A-Za-z]+)\s*$", front, re.M)
    if m: return m.group(1).lower()
    p = name.split("_", 1)[0].lower()
    return p if p in LESSON else ""
def verdict(text, title, is_lesson):
    if is_lesson: return "lesson", ""
    own = [o for o in others if o != me and names(text, title, o)]
    if own and not names(text, title, me): return "owned", " ".join(own)
    if REF.search(text) and len(text.encode()) <= cap: return "pointer", REF.search(text).group(0)
    hit = [k for k, r in STATE if re.search(r, text, re.I)]
    return ("state", ", ".join(hit)) if hit else ("clean", "")
types = {}
for f in sorted(os.listdir(d)):
    if not f.endswith(".md") or f == "MEMORY.md": continue
    front, body = split(open(os.path.join(d, f), encoding="utf-8", errors="replace").read())
    types[f] = ftype(f, front)
    nm = re.search(r"^name:\s*(.+)$", front, re.M)
    v, why = verdict(body.strip(), f[:-3] + " " + (nm.group(1) if nm else ""), types[f] in LESSON)
    print("%s\t%s\t%s" % (v, f, why))
idx = os.path.join(d, "MEMORY.md")
if os.path.exists(idx):
    for n, line in enumerate(open(idx, encoding="utf-8", errors="replace").read().split("\n"), 1):
        if not line.lstrip().startswith(("-", "*")): continue
        link = re.search(r"\]\(([^)]+\.md)\)", line)
        tgt = os.path.basename(link.group(1)) if link else ""
        v, why = verdict(line.strip(), tgt[:-3], types.get(tgt, "") in LESSON)
        print("%s\tMEMORY.md:%d\t%s" % (v, n, why))
PY
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

# seat_agent_path <repo> <agent>: where the seat's role is read: daita-beast:<name> is the plugin's own agents/<name>.md
# (an absolute path); <name> is <repo>/.claude/agents/<name>.md, in the local checkout of <repo> when this machine
# has one (beast_checkouts), else read through the contents API and printed as <repo>:.claude/agents/<name>.md.
# Dies naming the .claude/agents/<name>.md that does not exist. seat_agent_check is the same, printing nothing.
seat_agent_path() {
  local repo="$1" agent="$2" rel co c err
  [[ "$agent" =~ $AGENT_NAME_RE ]] || die "agent '$agent' is not an agent name (<name>, or daita-beast:<name>)"
  if [[ "$agent" == daita-beast:* ]]; then
    rel="$BEAST_SCRIPTS/../agents/${agent#daita-beast:}.md"
    [[ -f "$rel" ]] || die "the plugin has no agent $agent: $(cd "$BEAST_SCRIPTS/.." && pwd)/agents/${agent#daita-beast:}.md does not exist"
    echo "$(cd "$(dirname "$rel")" && pwd -P)/$(basename "$rel")"; return 0
  fi
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "seat_agent_path: '$repo' is not owner/repo"
  rel=".claude/agents/$agent.md"
  co=""
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    [[ "$(repo_slug "$c" 2>/dev/null | tr 'A-Z' 'a-z')" == "$(tr 'A-Z' 'a-z' <<< "$repo")" ]] || continue
    co="$c"; break
  done < <(beast_checkouts "$PWD")
  if [[ -n "$co" ]]; then
    [[ -f "$co/$rel" ]] || die "agent '$agent' of $repo: $co/$rel does not exist (the role is that file in the repo of the seat)"
    echo "$co/$rel"; return 0
  fi
  err="$(mktemp)"
  if gh_get "repos/$repo/contents/$(jq -rn --arg p "$rel" '$p | split("/") | map(@uri) | join("/")')" >/dev/null 2>"$err"; then rm -f "$err"; echo "$repo:$rel"; return 0; fi
  c="$(head -1 "$err")"; rm -f "$err"
  die "agent '$agent' of $repo: $rel does not exist in $repo (no local checkout; $c)"
}
seat_agent_check() { seat_agent_path "$1" "$2" >/dev/null; }

# fill_template <template file> <FIELD=value>...: the file with every @@FIELD@@ replaced; dies on a field left unfilled.
# An empty TWIN removes its paragraph line ("@@TWIN@@" followed by a blank line).
fill_template() {
  local t="$1"; shift
  python3 -I - "$t" "$@" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
kv = dict(a.split("=", 1) for a in sys.argv[2:])
if "@@TWIN@@\n\n" in s and not kv.get("TWIN", ""): s = s.replace("@@TWIN@@\n\n", "")
for k, v in kv.items(): s = s.replace("@@%s@@" % k, v)
if "@@" in s: sys.exit("daita-beast: unfilled field in %s: %s" % (sys.argv[1], s[s.index("@@"):].split("\n")[0]))
sys.stdout.write(s)
PY
}

# claude_block_render <seat>: the Beast block of one seat's home, from templates/claude-block.md: the seat's identity,
# its role (the agent file), and its workstream's `## Seats` table rendered from the tracking issue (the one owner).
claude_block_render() {
  local seat id slug short roster board pub twin="" proto decider decider_name agent apath ref r n title table
  seat="${1:-}"; [[ -n "$seat" ]] || die "claude_block_render takes a seat"
  id="$(seat_identity "$seat")" || exit 1
  short="$(seat_short "$id")"; slug="${id%%/*}"
  roster="$(roster_path)"
  [[ -n "$(roster_row "$short")" ]] || die "seat $short is not in $roster: a home's block is rendered from the seat's own roster"
  agent="$(roster_field "$short" agent)"
  apath="$(seat_agent_path "$(roster_field "$short" repo)" "$agent")" || exit 1
  ref="$(workstream_issue "$slug")" || exit 1
  r="${ref%%#*}"; n="${ref#*#}"
  title="$(issue_get "$r" "$n" | jq -r '.title // ""')" || exit 1
  table="$(ws_seats_render "$slug" "$(ws_seats_parse "$slug")")" || exit 1
  pub="$(roster_pair_check "$roster")" || exit 1
  proto="$(protocol_repo)" || exit 1
  [[ -z "$pub" ]] || twin="**This repo is the private twin of \`$pub\`.** All work and coordination happen here: decision rows, desks, tracking issues, status, notes, acks and the decider's words. \`$pub\` receives only publishes and never a coordination comment: the scripts refuse every coordination write to a public or public-intended repo, and \`publish.sh\` is the only writer to \`$pub\`. To publish: (1) \`publish.sh prepare <slug> --paths <path>… | --commits <sha>… --message-file <f>\` cuts \`publish/<slug>\` from \`$pub\`'s default branch with ONE new commit, its message written for outside readers, never this repo's history; (2) the scrub gate runs in prepare and again before every push and merge (\`publish.sh scrub <slug>\`), naming each hit: a private repo's slug or name, a local path, a \`BEAST-\` line, a record path, words from a closed row here, a roster \`scrub\` pattern, a secret-shaped file name; a branch that is not exactly one commit on the public base is refused; (3) \`publish.sh request <slug> --seat <SEAT> --body-file <f>\` pushes the branch, opens the PR on \`$pub\` with an outside-reader description and files the approval row HERE, approved with \`publish <slug>\`; the decider answers on the row, nothing of theirs goes on the PR; (4) on the word, \`publish.sh merge <slug> --words \"<verbatim>\" --by <SEAT>\` squash-merges, deletes the branch and closes the row; (5) \`publish.sh pull\` brings outside contributions merged on \`$pub\` into this repo's default branch."
  board="$(jq -r '.board // .repo' "$roster")"
  # the decider: the roster's one owner (roster_decider dies naming the roster when there is not exactly one); the
  # name shown is that people[] row's "name", required
  decider="$(roster_decider)" || exit 1
  decider_name="$(jq -r --arg g "$decider" '[.people[] | select(.github == $g) | .name // empty] | first // empty' "$roster")"
  [[ -n "$decider_name" ]] || die "roster $roster: the owner $decider has no \"name\" in people[]: the CLAUDE.md block names the decider"
  fill_template "$BEAST_SCRIPTS/../templates/claude-block.md" "TWIN=$twin" "IDENTITY=$id" "SEAT=$short" "AGENT=$agent" "AGENT_PATH=$apath" \
    "SLUG=$slug" "WS_TITLE=$title" "MASTER=$r" "TRACKING=https://github.com/$r/issues/$n" "SEATS=$table" \
    "BOARD=$board" "PROTOCOL=$proto" "DECIDER_NAME=$decider_name" "DECIDER=$decider"
}

# block_replace <begin regex> <end regex> <block>: stdin text with its first begin…end stretch (Python regexes,
# DOTALL, the end's trailing newline included) replaced by the block, or the block appended; on stdout. The one
# replace shape of every generated block (the Beast block, the workstream blocks of a master's CLAUDE.md).
block_replace() {
  BEGIN_RE="$1" END_RE="$2" BLOCK="$3" python3 -I -c "$(cat <<'PY'
import os, re, sys
s = sys.stdin.read(); b = os.environ["BLOCK"].rstrip("\n") + "\n"
pat = re.compile(os.environ["BEGIN_RE"] + r".*?" + os.environ["END_RE"] + r"\n?", re.S)
if pat.search(s): new = pat.sub(lambda m: b, s, count=1)
else: new = s.rstrip("\n") + ("\n\n" if s.strip() else "") + b
sys.stdout.write(new)
PY
)"
}

# block_write <file> <begin regex> <end regex> <block>: block_replace on the file, in place; prints "block
# unchanged|written in <file>". The rest of the file is kept.
block_write() {
  local f="$1" old new
  [[ -f "$f" ]] || die "no $f to write the block into"
  old="$(cat "$f"; printf x)"; old="${old%x}"
  new="$(printf '%s' "$old" | block_replace "$2" "$3" "$4"; printf x)"; new="${new%x}"
  if [[ "$new" == "$old" ]]; then echo "block unchanged in $f"; else printf '%s' "$new" > "$f"; echo "block written in $f"; fi
}

CLAUDE_BLOCK_BEGIN_RE='<!-- beast:begin'
CLAUDE_BLOCK_END_RE='<!-- beast:end -->'

# claude_block_write <CLAUDE.md> <seat>: replaces the file's Beast block (or appends it) with the seat's.
claude_block_write() {
  local block
  block="$(claude_block_render "${2:-}")" || die "cannot render the CLAUDE.md block"
  block_write "$1" "$CLAUDE_BLOCK_BEGIN_RE" "$CLAUDE_BLOCK_END_RE" "$block"
}

# ---- the master's workstream block: one per workstream in the master repo's CLAUDE.md ----------------------------
# ws_block_markers <slug>: "<begin regex>\t<end regex>" of the workstream's block (markers carry the slug, so one
# CLAUDE.md holds several).
ws_block_markers() {
  local e; e="$(python3 -I -c 'import re, sys; print(re.escape(sys.argv[1]))' "$1")"
  printf '%s\t%s\n' "<!-- beast:workstream begin $e -->" "<!-- beast:workstream end $e -->"
}

# ws_block_render <slug>: the block, from templates/workstream-block.md: the tracking issue, the master, the table.
ws_block_render() {
  local slug="$1" ref r n title table
  ref="$(workstream_issue "$slug")" || exit 1
  r="${ref%%#*}"; n="${ref#*#}"
  title="$(issue_get "$r" "$n" | jq -r '.title // ""')" || exit 1
  table="$(ws_seats_render "$slug" "$(ws_seats_parse "$slug")")" || exit 1
  fill_template "$BEAST_SCRIPTS/../templates/workstream-block.md" "SLUG=$slug" "TITLE=$title" "MASTER=$r" "TRACKING=https://github.com/$r/issues/$n" "SEATS=$table"
}

# ws_block_write_local <CLAUDE.md> <slug>: the workstream's block written into a local checkout's CLAUDE.md.
ws_block_write_local() {
  local m block
  m="$(ws_block_markers "$2")"
  block="$(ws_block_render "$2")" || exit 1
  block_write "$1" "${m%%$'\t'*}" "${m#*$'\t'}" "$block"
}

# ws_homes_render <slug>: the Beast block of every home on this machine of a seat in the workstream's `## Seats` table
# (seat_homes_on_machine: rows not retired whose home holds its own .beast/seat.json), re-rendered from the table, so
# a seat added or removed reaches every home here as well as the master. A home whose CLAUDE.md carries no block yet
# is named and left to its join. Prints one line per home.
ws_homes_render() {
  local slug="$1" rows id c h k ws ret
  rows="$(ws_seats_parse "$slug")" || exit 1
  while IFS=$'\t' read -r id c h k ws ret; do
    [[ -n "$id" && "$ws" == "$slug" && -z "$ret" ]] || continue
    grep -q "^$id	" <<< "$rows" || continue
    [[ -d "$h" && "$(seat_json_id "$h")" == "$id" ]] || { echo "home of $id: not on this machine ($h)"; continue; }
    if [[ ! -f "$h/CLAUDE.md" ]] || ! grep -q "$CLAUDE_BLOCK_BEGIN_RE" "$h/CLAUDE.md"; then echo "home of $id: $h/CLAUDE.md has no Beast block yet (join.sh writes it)"; continue; fi
    ( cd "$c" && claude_block_write "$h/CLAUDE.md" "$(seat_identity_of "$id" "$slug")" ) || die "the Beast block of $id in $h/CLAUDE.md was not re-rendered (named above)"
  done < <(seat_homes_on_machine "$PWD")
}

# ws_block_write_remote <repo> <slug> [pr]: the block written into <repo>'s CLAUDE.md through the contents API on
# the default branch (a PUT with the sha read first: a file that changed meanwhile is a 409, exit 1, nothing
# written), or, with pr, on the branch beast/workstream-<slug> with a pull request opened once. Prints the commit
# or the PR URL, or "unchanged".
ws_block_write_remote() {
  local repo="$1" slug="$2" how="${3:-}" m block db enc st sha old new br head msg out url
  m="$(ws_block_markers "$slug")"
  block="$(ws_block_render "$slug")" || exit 1
  coord_write_guard "$repo"
  db="$(default_branch "$repo")" || exit 1
  br="$db"
  if [[ "$how" == pr ]]; then
    br="beast/workstream-$slug"
    if [[ "$(gh_status_of "repos/$repo/git/ref/heads/$(uri "$br")")" != 200 ]]; then
      head="$(gh_get "repos/$repo/git/ref/heads/$(uri "$db")" | jq -r .object.sha)" || die "cannot read the head of $repo $db"
      gh_send POST "repos/$repo/git/refs" -f ref="refs/heads/$br" -f sha="$head" >/dev/null
    fi
  fi
  enc="CLAUDE.md"
  st="$(gh_status_of "repos/$repo/contents/$enc?ref=$(uri "$br")")" || exit 1
  sha=""; old=""
  if [[ "$st" == 200 ]]; then
    out="$(gh_get "repos/$repo/contents/$enc?ref=$(uri "$br")")" || exit 1
    sha="$(jq -r .sha <<< "$out")"
    old="$(jq -r '.content // ""' <<< "$out" | base64 -d; printf x)"; old="${old%x}"
  elif [[ "$st" != 404 ]]; then die "cannot read CLAUDE.md of $repo at $br (HTTP $st)"; fi
  new="$(printf '%s' "$old" | block_replace "${m%%$'\t'*}" "${m#*$'\t'}" "$block"; printf x)"; new="${new%x}"
  if [[ "$new" == "$old" ]]; then echo "unchanged"; return 0; fi
  msg="CLAUDE.md: workstream $slug block (daita-beast workstream.sh render)"
  out="$(gh_send_try PUT "repos/$repo/contents/$enc" -f message="$msg" -f branch="$br" -f content="$(printf '%s' "$new" | base64 | tr -d '\n')" ${sha:+-f sha="$sha"})" \
    || die "CLAUDE.md of $repo at $br was not written (named above${sha:+; HTTP 409 = it changed since it was read: rerun render})"
  url="$(jq -r '.commit.html_url // empty' <<< "$out")"
  [[ -n "$url" ]] || die "GitHub answered the PUT of CLAUDE.md without a commit"
  if [[ "$how" != pr ]]; then echo "$url"; return 0; fi
  out="$(gh_get "repos/$repo/pulls?state=open&head=$(uri "${repo%%/*}:$br")&base=$(uri "$db")")" || exit 1
  if [[ "$(jq length <<< "$out")" -gt 0 ]]; then jq -r '.[0].html_url' <<< "$out"; return 0; fi
  gh_send POST "repos/$repo/pulls" -f title="$msg" -f head="$br" -f base="$db" -f body="The seat map of workstream $slug, rendered from its tracking issue's \`## Seats\` table by daita-beast \`workstream.sh render $slug --pr\`." | jq -r .html_url
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

# section_replace "<heading>" "<content>": stdin body on stdout with the text under "## <heading>" (up to the next
# "## ") replaced by the content; a body without the section gets it appended. The heading line is kept as is.
section_replace() {
  HEADING="## $1" CONTENT="$2" python3 -I -c "$(cat <<'PY'
import os, sys
h, c = os.environ["HEADING"], os.environ["CONTENT"].rstrip("\n")
lines = sys.stdin.read().split("\n")
out, i, done = [], 0, False
while i < len(lines):
    if lines[i].rstrip() == h and not done:
        out.append(lines[i]); out.extend(c.split("\n")); out.append(""); i += 1; done = True
        while i < len(lines) and not lines[i].startswith("## "): i += 1
        continue
    out.append(lines[i]); i += 1
if not done:
    while out and not out[-1].strip(): out.pop()
    out.extend(["", h] + c.split("\n") + [""])
s = "\n".join(out).rstrip("\n") + "\n"
sys.stdout.write(s)
PY
)"
}

# ROW_SECTIONS: a decision row's six body sections, in order (decision.sh new and revise, board.sh). One owner of the list.
ROW_SECTIONS=("Decision" "Unblocks" "Waits" "Recommendation" "Approve with" "Record")
# PR_ROW_SECTIONS: the sections a PR on the board carries in its body, written by pr.sh request (--unblocks,
# --recommendation) and read by board.sh; the page's PR_SECTIONS is held equal to it (plugin/tests/board-page.test.mjs).
PR_ROW_SECTIONS=("Unblocks" "Recommendation")

# Same, but exits 1 naming the issue when the section is absent or empty.
section_required() {
  local heading="$1" body="$2" who="$3" out
  out=$(printf '%s\n' "$body" | section "$heading" | sed '/^[[:space:]]*$/d')
  [[ -n "$out" ]] || die "$who: body has no non-empty '## $heading' section (parse by shape; fix the issue body)"
  printf '%s\n' "$out"
}

# One-line cell for a markdown table: join lines, escape pipes, trim.
cell() { tr '\n' ' ' | sed -e 's/|/\\|/g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//'; }

# award_policy <repo> [<token>]: the repo's award policy, `.beast/award-policy.md` at the root of the current checkout,
# the one parser of it. Required by award.sh and bounty.sh. Prints "<TOKEN> <community owner/repo>": its `Token: <SYMBOL>`
# line and its `Community: <owner/repo>` line, the repo that holds the token's community and its awarders file
# (community_awarders). Fails loud when absent, when it names another repo, when it still carries a fill field
# (`<owner/repo>`, `<TOKEN>` or `<COMMUNITY>`), when a line is missing or malformed, or when its token is not <token>.
award_policy() {
  local repo="$1" want="${2:-}" f tok com
  f="$(repo_root)/.beast/award-policy.md"
  [[ -f "$f" ]] || die "no award policy at $f — write one first: init-repo.sh $repo --path <checkout> --token <TOKEN> --community <owner/repo> (a repo that takes no outside contributions has no policy and awards nothing)"
  head -1 "$f" | grep -q -- "— $repo\$" || die "$f is the policy of '$(head -1 "$f" | sed 's/^# Award policy — //')', not of $repo"
  ! grep -q -e '<owner/repo>' -e '<TOKEN>' -e '<COMMUNITY>' "$f" || die "$f still carries a fill field: $(grep -o -e '<owner/repo>' -e '<TOKEN>' -e '<COMMUNITY>' "$f" | head -1) — set it, a placeholder policy awards nothing"
  tok="$(sed -n 's/^Token: \([A-Z0-9]\{2,12\}\).*/\1/p' "$f" | head -1)"
  [[ -n "$tok" ]] || die "$f has no 'Token: <SYMBOL>' line"
  [[ -z "$want" || "$want" == "$tok" ]] || die "token $want is not this repo's award token $tok (one owner: $f)"
  com="$(sed -n 's/^Community: \([^ ]*\).*/\1/p' "$f" | head -1)"
  [[ -n "$com" ]] || die "$f has no 'Community: <owner/repo>' line: the repo that holds the $tok community and its .beast/awarders.json (the repos that may award $tok); add it"
  [[ "$com" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "$f: 'Community: $com' is not owner/repo"
  echo "$tok $com"
}

# The token's authority: the community repo of a token (an award policy's `Community:` line) commits `.beast/awarders.json`,
# the one owner of which repos may award its token: {"token": "<SYMBOL>", "awarders": ["<owner/repo>", ...]}. Read from the
# community repo's default branch through GitHub, never from a local copy. A missing file refuses every award (no open default).
AWARDERS_PATH=".beast/awarders.json"

# community_awarders <community repo> <token>: the repos that may award <token>, one per line, as the file lists them. Dies
# naming the community repo and the file when the file is absent (naming the file to create and its shape), unreadable,
# not the shape above (an unknown key, a token that is not a symbol, an empty list, an entry that is not owner/repo, an
# entry listed twice), or for another token.
community_awarders() {
  local c="$1" tok="$2" st got body bad
  [[ "$c" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "community repo '$c' is not owner/repo"
  st="$(gh_status_of "repos/$c/contents/$AWARDERS_PATH")" || exit 1
  [[ "$st" != 404 ]] || die "refused: the community repo $c carries no $AWARDERS_PATH, so no repo may award $tok. Its owner commits $AWARDERS_PATH on its default branch: {\"token\": \"$tok\", \"awarders\": [\"<owner/repo>\", ...]}, listing every repo that may award $tok"
  [[ "$st" == 200 ]] || die "cannot read $AWARDERS_PATH of the community repo $c (HTTP $st)"
  got="$(gh_get "repos/$c/contents/$AWARDERS_PATH")" || die "cannot read $AWARDERS_PATH of the community repo $c (named above)"
  body="$(python3 -I -c 'import base64, json, sys
d = json.load(sys.stdin)
if d.get("encoding") != "base64": sys.exit("encoding %r, not base64" % d.get("encoding"))
sys.stdout.write(base64.b64decode(d.get("content") or "").decode("utf-8"))' <<< "$got")" || die "cannot decode $AWARDERS_PATH of the community repo $c (named above)"
  bad="$(jq -r --arg t "$tok" '
    if type != "object" then "is not an object {\"token\", \"awarders\"}"
    elif (keys - ["awarders", "token"]) != [] then "unknown key(s) \(keys - ["awarders", "token"] | join(", ")); the keys are token and awarders"
    elif ((.token | type) != "string") or (.token | test("^[A-Z0-9]{2,12}$") | not) then "\"token\" \(.token | tojson) is not a symbol such as ACME"
    elif .token != $t then "is the awarders file of token \(.token), not \($t)"
    elif ((.awarders | type) != "array") or (.awarders | length) == 0 then "\"awarders\" is a non-empty list of owner/repo, got \(.awarders | tojson)"
    elif ([.awarders[] | select(type != "string" or (test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") | not))] | length) > 0 then "\"awarders\" entry \([.awarders[] | select(type != "string" or (test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") | not))][0] | tojson) is not owner/repo"
    elif (.awarders | map(ascii_downcase) | unique | length) != (.awarders | length) then "\"awarders\" lists a repo twice"
    else empty end' <<< "$body" 2>/dev/null)" || die "the community repo $c: $AWARDERS_PATH is not JSON"
  [[ -z "$bad" ]] || die "the community repo $c: $AWARDERS_PATH $bad"
  jq -r '.awarders[]' <<< "$body"
}

# award_authority_check <repo> <token> <community repo>: dies unless the community repo's awarders file lists <repo>
# (case-insensitively, as GitHub compares names), naming the community repo, the file and the missing entry.
award_authority_check() {
  local repo="$1" tok="$2" c="$3" list
  list="$(community_awarders "$c" "$tok")" || exit 1
  grep -qixF -- "$repo" <<< "$list" || die "refused: $repo may not award $tok. The community repo $c lists the repos that may award $tok in $AWARDERS_PATH ($(paste -sd, - <<< "$list")), and \"$repo\" is not among them: the owner of $c adds \"$repo\" to its \"awarders\""
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
  local dir="$1" path="$2" f="" key raw err rc=0 t l1 l2 status hdrs body etag lm resource reset args=() c_etag="" c_lm="" bad=""
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
      # A 403 with no quota left is the quota, not the request: say when it resets (X-RateLimit-Reset, epoch seconds),
      # here, the one place that sees the headers. The search quota (30 a minute per login) is the one a seat hits.
      if [[ "$status" == 403 && "$(awk -F': ' 'tolower($1)=="x-ratelimit-remaining" {print $2}' <<< "$hdrs")" == 0 ]]; then
        reset="$(awk -F': ' 'tolower($1)=="x-ratelimit-reset" {print $2}' <<< "$hdrs")"
        echo "daita-beast: gh GET $path failed (HTTP 403): ${resource:-core} quota: resets at $(jq -rn --argjson t "${reset:-0}" '$t | todate'), $(( ${reset:-0} - $(date -u +%s) )) s" >&2
      else
        echo "daita-beast: gh GET $path failed (exit $rc, HTTP ${status:-none}): $(tr '\n' ' ' < "$err")" >&2
      fi
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

# roster_workstream_owners [roster]: the one parser of the roster's top-level "workstream_owners": GitHub owners, beyond
# the ones the roster names (roster_owners), whose `workstream` + `ws:<slug>` tracking issues this repo's seats may join.
# One per line; nothing when the field is absent. Dies naming the field when it is not a list of owner names (letters,
# digits, -), lists one twice, or lists one the roster already names (searched already).
roster_workstream_owners() {
  local r="${1:-}" bad
  [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  bad="$(jq -r '
    if has("workstream_owners") | not then empty
    elif (.workstream_owners | type) != "array" then "is a list of GitHub owners ([\"<owner>\", ...]), got \(.workstream_owners | tojson)"
    else ([.repo, .board, (.seats[]?.repo)] | map(select(type == "string" and contains("/")) | split("/")[0] | ascii_downcase)) as $own
      | [.workstream_owners | to_entries[] | .key as $i | .value
          | if (type != "string") or (test("^[A-Za-z0-9-]+$") | not) then "[\($i)] \(tojson) is not a GitHub owner name (letters, digits, -)"
            elif (ascii_downcase | IN($own[])) then "[\($i)] \(tojson) is already an owner the roster names (repo, board, seats[].repo), searched without it"
            else empty end] + [.workstream_owners | map(ascii_downcase? // .) | group_by(.) | map(select(length > 1) | .[0]) | .[] | "lists \(tojson) twice"]
      | first // empty end' "$r")" || die "roster $r: cannot read \"workstream_owners\""
  [[ -z "$bad" ]] || die "roster $r: \"workstream_owners\" $bad"
  jq -r '(.workstream_owners // [])[]' "$r"
}

# workstream_user_terms: the one owner of where workstreams are searched: the roster's owners (roster_owners) plus its
# declared "workstream_owners", as search terms "user:a user:b". An undeclared owner is never searched.
workstream_user_terms() {
  local t o extra
  t="$(roster_user_terms)" || exit 1
  extra="$(roster_workstream_owners)" || exit 1
  while IFS= read -r o; do [[ -n "$o" ]] && t="$t user:$o"; done <<< "$extra"
  printf '%s' "$t"
}

# WORKSTREAM_OWNERS_HINT: the line a "not found among the owners" refusal ends with, naming the field that widens the search.
WORKSTREAM_OWNERS_HINT='a tracking issue under another owner is searched only when this roster'"'"'s "workstream_owners" lists that owner (docs/protocol.md, Roster)'

user_login() { gh_login; }

user_exists() { gh_get "users/$1" >/dev/null 2>&1; }

# repo_permission <repo> <login>: admin|maintain|write|triage|read|none, as GitHub answers it. Dies naming the repo,
# the login and GitHub's answer when the role cannot be read (a 403: the caller lacks push access to <repo>): an
# unread role is never taken for "none".
repo_permission() {
  local p err first; err="$(mktemp)"
  if p="$(gh_get "repos/$1/collaborators/$2/permission" 2>"$err")"; then
    rm -f "$err"; jq -er '.permission | select(type == "string")' <<< "$p" || die "GitHub answered the role of $2 on $1 without a permission"
    return 0
  fi
  first="$(grep -m1 . "$err" || true)"; rm -f "$err"
  die "cannot read the role of $2 on $1: ${first#daita-beast: } (a 403 means the gh login lacks push access to $1 and may not read its collaborators' roles; run with a login that has it)"
}

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

# comment_delete <repo> <comment-id>: deletes one issue comment.
comment_delete() { gh_send DELETE "repos/$1/issues/comments/$2" >/dev/null; }

# contents_path <path>: a repo path for the contents API (each segment percent-encoded).
contents_path() { jq -rn --arg p "$1" '$p | split("/") | map(@uri) | join("/")'; }

# default_branch <repo>
default_branch() { gh_get "repos/$1" | jq -er '.default_branch' || die "cannot read the default branch of $1"; }

# gh_status_of <path>: "200" when the GET answers, else the HTTP status GitHub gave (404, 410, …), for an existence check.
gh_status_of() {
  local err; err="$(mktemp)"
  if gh_get "$1" >/dev/null 2>"$err"; then rm -f "$err"; echo 200; return 0; fi
  sed -nE 's/.*HTTP ([0-9]{3}).*/\1/p' "$err" | head -1 | grep . || { cat "$err" >&2; rm -f "$err"; die "GET $1 failed without an HTTP status (named above)"; }
  rm -f "$err"
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
# carries `is:issue` or `is:pr` and the `user:<owner>` scope (roster_user_terms). One search per query per run:
# the result is memoized in the run cache ($BEAST_WS_CACHE/search-<digest of q>) and served from there to every
# later call of the run, in this script or one it starts. An exhausted quota is named by gh_request with its reset time.
search_issues() {
  local q="$1" page=1 acc='[]' got n total memo
  [[ $# -eq 1 ]] || die "search_issues takes one query; a result cap would drop rows silently"
  memo="$BEAST_WS_CACHE/search-$(beast_sha "$q")"
  if [[ -f "$memo" ]]; then cat "$memo"; return 0; fi
  while :; do
    got="$(gh_request "" "search/issues?q=$(uri "$q")&per_page=100&page=$page&sort=updated&order=desc")" || return 1
    total="$(jq .total_count <<< "$got")"
    [[ "$total" -le 1000 ]] || { echo "daita-beast: search '$q' matches $total items; the search API serves at most 1000: narrow the query (nothing is dropped silently)" >&2; return 1; }
    acc="$(jq -s '.[0] + .[1].items' <(printf '%s\n' "$acc") <(printf '%s\n' "$got"))"
    n="$(jq '.items | length' <<< "$got")"
    [[ "$n" -eq 100 ]] || break
    page=$((page+1))
  done
  printf '%s\n' "$acc" > "$memo.tmp" && mv -f "$memo.tmp" "$memo"
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

# answer_kind "<body>" "<phrase>": approve | revise | reject | "" — the decider's answer forms, read on the first line
# (right-trimmed): the phrase, "<phrase> — <comment>", a bare approve/approved, "revise: <what>", "reject: <why>". Any
# other comment is not an answer, whoever wrote it: it never takes a row out of the decider's turn. An empty phrase (a
# row without one) matches only the bare forms. The page's answerKind is held to this by plugin/tests/board-page.test.mjs.
answer_kind() {
  local b; b="$(printf '%s' "$1" | sed -n '1p' | sed 's/[[:space:]]*$//')"
  local phrase="$2"
  if [[ -n "$phrase" && ( "$b" == "$phrase" || "$b" == "$phrase — "* ) ]] || [[ "$b" =~ ^[Aa]pproved?$ ]]; then echo approve
  elif [[ "$b" =~ ^reject:[[:space:]]*[^[:space:]] ]]; then echo reject
  elif [[ "$b" =~ ^revise:[[:space:]]*[^[:space:]] ]]; then echo revise
  else echo ""; fi
}

# ---- seat tags: the one reader of the seat a comment names as its writer --------------------------------------
# Every seat posts as the same GitHub login, so a comment's author never says which seat wrote it; its tagged line does.
# SEAT_TAG_JQ is the jq library of those readers (run through tag_jq, which binds $seatre, $askre and $msgre):
#   tag_ack(l)       a well-formed `BEAST-ACK seat=<token> at=<UTC> state=seen|executed|blocked` line, or null
#   tag_closer(b)    the "Closed by seat <token> at <UTC>." of a close comment (row_close_comment), or null
#   close_of(b)      of a comment body: the close comment it is (row_close_comment's shape, CLOSE_LINE_RE), as
#                    {kind: closed|rejected|latitude, words, record, seat, line}, or null. words: the verbatim words of a
#                    closed or rejected row (null on a latitude close, which quotes none); record: its record (a latitude
#                    close's is the link in its close line); seat: the closer; line: the close line
#   close_text(c)    of a close_of result: the one line a reader shows for it (the quoted words; a latitude close as
#                    "no words: merged under standing latitude by <seat>, record <link>")
#   close_last(cs)   of a comment list: the newest close comment's close_of, plus its url, or null
#   tag_actor(desk)  of a comment: the seat id that wrote it, or null (an untagged comment, a BEAST-ANSWER: the decider's).
#                    In order: the closer; a BEAST-ACK first line, or last line (a seat's own reply on a row ends with
#                    it); a BEAST-STATUS or BEAST-NOTES header; a BEAST-ASK header; a BEAST-MSG sender (from=); on a
#                    desk (desk = the desk's seat id, else ""), a BEAST-WITHDRAW, which only the desk's seat posts. A
#                    bare label (a comment written before the 2026-10-15 relabel) is read as <the comment's login>/<LABEL>.
SEAT_TAG_JQ='
def tag_first: (split("\n")[0] // "");
def tag_last: (split("\n") | map(select(test("\\S"))) | last // "");
def tag_ack(l): (l | capture("^BEAST-ACK seat=(?<seat>" + $seatre + ") at=(?<at>[^ ]+) state=(?<state>seen|executed|blocked)") // null);
def tag_closer(b): (b | capture("Closed by seat (?<seat>" + $seatre + ") at (?<at>[0-9T:Z-]+)\\.") // null);
def close_of(b):
  ((b // "") | gsub("\r"; "")) as $b | ($b | tag_first | sub("\\s+$"; "")) as $f
  | (first($f | capture($closere)) // null) as $m
  | if $m == null then null
    elif ($m.record // "") != "" then {kind: "latitude", words: null, record: $m.record, seat: $m.seat, line: $f}
    else {kind: (if $m.verdict == "Rejected" then "rejected" else "closed" end),
          words: (first($b | capture("^(Closed|Rejected) on the word, verbatim: \"(?<w>.*)\"\n\nRecord: "; "p") | .w) // null),
          record: (first($b | capture("\nRecord: (?<r>.*)\\. Closed by seat ") | .r) // null),
          seat: (tag_closer($b) | .seat?), line: $f} end;
def close_text(c): if c.kind == "latitude" then "no words: merged under standing latitude by \(c.seat), record \(c.record)" elif c.words != null then "\"\(c.words)\"" else c.line end;
def close_last(cs): ([cs[]? | . as $c | close_of($c.body) | select(. != null) | . + {url: $c.html_url}] | last // null);
def tag_actor(desk):
  . as $c | (($c.body // "") | gsub("\r"; "")) as $b | ($b | tag_first | sub("\\s+$"; "")) as $f
  | ((tag_closer($b) // tag_ack($f) // tag_ack($b | tag_last)
      // ($f | capture("^BEAST-(STATUS|NOTES) seat=(?<seat>" + $seatre + ")( |$)"))
      // ($f | capture($askre))
      // ($f | capture($msgre) | {seat: (.from | split("/") | "\(.[2])/\(.[1])")})
      // (if desk != "" and ($f | test("^BEAST-WITHDRAW n=[0-9]+$")) then {seat: desk} else null end)) | .seat?) as $s
  | if $s == null then null elif ($s | contains("/")) then $s else "\($c.user.login // "")/\($s)" end;
'

# tag_jq [jq options...] '<program>': jq with SEAT_TAG_JQ prepended to the program and its regexes bound.
tag_jq() {
  [[ $# -ge 1 ]] || die "tag_jq takes [jq options...] '<program>'"
  local prog="${*: -1}"
  jq --arg seatre "$SEAT_TOKEN_RE" --arg askre "$ASK_HEADER_RE" --arg msgre "$MSG_HEADER_RE" --arg closere "$CLOSE_LINE_RE" "${@:1:$#-1}" "$SEAT_TAG_JQ $prog"
}

# close_of_comments <comments-json>: the newest close comment of a row's comments (close_last), JSON, or null.
close_of_comments() { tag_jq -c 'close_last(.)' <<< "$1"; }

# ack_line <id> seen|executed|blocked "<next>": the one writer of a seat's ack line, stamped now (ack.sh, the close
# comment's last line, the filer's ack of decision.sh new and pr.sh request).
ack_line() {
  [[ $# -eq 3 && "$1" =~ $SEAT_ID_RE ]] || die "ack_line takes <seat id> <state> \"<next>\", not $*"
  case "$2" in seen|executed|blocked) ;; *) die "ack_line: state is seen, executed or blocked, not '$2'" ;; esac
  [[ -n "$3" && "$3" != *$'\n'* ]] || die "ack_line: next is one line"
  printf 'BEAST-ACK seat=%s at=%s state=%s next=%s' "$1" "$(utc_now)" "$2" "$3"
}

# seat_acks <row>: (a row_read result) one line per seat id, "<id>\t<at>\t<state>\t<url>", the NEWEST well-formed BEAST-ACK
# by that seat (first line, or the last non-empty line of a close comment). The seat is a qualified id, or a
# bare label (comments written before the 2026-10-15 relabel), read as <the comment author's login>/<LABEL>:
# a comment is posted by the seat's own login, so it names its seat without any roster. A line that starts
# with BEAST-ACK and does not match the shape is named on stderr and dropped.
seat_acks() {
  [[ $# -eq 1 ]] || die "seat_acks takes one row (row_read), not $*"
  local closed_at; closed_at="$(jq -r '.issue.closed_at // ""' <<< "$1")"
  jq '.comments' <<< "$1" | tag_jq -r --arg closed "$closed_at" '
    # A close comment names its closer: "Closed by seat X at T" is X'"'"'s seen ack at T (the same fact, the shape the close has always carried).
    # The close comment is the closer'"'"'s seen ack AT THE CLOSE: its time is the issue'"'"'s closed_at (the comment lands seconds before the close).
    def closer(b): (tag_closer(b) | if . == null then null else {seat:.seat, at:(if $closed != "" then $closed else .at end), state:"seen"} end);
    .[] | . as $c | ((.body // "") | tag_first) as $f | ((.body // "") | tag_last) as $l
      | (closer(.body // "") // tag_ack($f) // tag_ack($l)) as $a
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

# event_actors NEW|DECIDED|UPDATED <delta> <comments-json> <desk seat | "">: the seats whose acts make up one watch.sh
# event on a row, one per line, "-" for an act no seat tag names (the decider's: an untagged comment, a BEAST-ANSWER).
#   NEW      the filer (the seat of the row's first BEAST-ACK comment: the filer's ack, which decision.sh new and pr.sh
#            request post), then the writer of every comment that is not bookkeeping
#   DECIDED  the closer (the newest comment, when it is a close comment), then the writer of every newer comment that is
#            not bookkeeping
#   UPDATED  the writer of every newer comment that is not bookkeeping (nothing: no news, no event)
# <delta> is how many comments are newer than the seat's snapshot; bookkeeping is BOOKKEEPING_FIRST_LINE_RE. The relay
# sends a seat an event only when one of its actors is not that seat: a seat never hears its own act back.
event_actors() {
  [[ $# -eq 4 && "$2" =~ ^[0-9]+$ ]] || die "event_actors takes NEW|DECIDED|UPDATED <delta> <comments-json> <desk seat | \"\">, not $*"
  case "$1" in NEW|DECIDED|UPDATED) ;; *) die "event_actors: kind is NEW, DECIDED or UPDATED, not '$1'" ;; esac
  tag_jq -r --arg kind "$1" --argjson d "$2" --arg desk "$4" --arg bk "$BOOKKEEPING_FIRST_LINE_RE" '
    def news: .[] | select((((.body // "") | gsub("\r"; "") | tag_first) | test($bk)) | not) | (tag_actor($desk) // "-");
    def newer: if $d > 0 then .[-$d:] else [] end;
    if $kind == "NEW" then
      ((first(.[] | select((.body // "") | startswith("BEAST-ACK "))) // null) as $c | if $c != null then ($c | tag_actor($desk) // "-") else "-" end), news
    elif $kind == "DECIDED" then
      ((.[-1] // null) as $c | if $c != null and tag_closer($c.body // "") != null then ($c | tag_actor($desk) // "-") else "-" end), (newer | news)
    else newer | news end' <<< "$3"
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

# The amend line: the first line of the comment that says a row changed after it was filed: decision.sh revise (the body
# revised after a revise:) and publish.sh request --amend (the PR branch force-updated) post it. One owner of its shape:
# amend_line writes it, row_amended_at reads it, the board page mirrors AMEND_LINE_RE (plugin/tests/regex-mirror.test.mjs).
#   Amended at <UTC>: <what changed, one line>
AMEND_LINE_RE='^Amended at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z: '

# amend_line "<what changed>": the line, stamped now.
amend_line() {
  [[ $# -eq 1 && -n "$1" && "$1" != *$'\n'* ]] || die "amend_line takes one line saying what changed, not $*"
  printf 'Amended at %s: %s' "$(utc_now)" "$1"
}

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

# row_revise_pending <row>: (a row_read result) the URL of the decider's revise: comment when it is their standing answer
# (row_answer_url) and no amend line (row_amended_at) is newer than it, else nothing: the decider asked for a revision and
# the row was not revised. While it holds no approval closes the row (decision.sh close, pr.sh close --merge, publish.sh
# merge); decision.sh revise (or publish.sh request --amend) ends it. A reject still closes.
row_revise_pending() {
  [[ $# -eq 1 ]] || die "row_revise_pending takes one row (row_read), not $*"
  local row="$1" phrase u at amended
  phrase="$(row_phrase "$(jq -r '"\(.issue.repository_url | sub(".*/repos/"; ""))#\(.issue.number)"' <<< "$row")" "$(jq '.issue' <<< "$row")" 2>/dev/null)"
  u="$(row_answer_url "$row" "$phrase" revise)" || exit 1
  [[ -n "$u" ]] || return 0
  at="$(jq -r --arg u "$u" '.comments[] | select(.html_url == $u) | .created_at' <<< "$row")"
  amended="$(row_amended_at "$row")"
  [[ -n "$amended" && "$amended" > "$at" ]] || echo "$u"
}

# revise_pending_refusal <url>: the one wording of the refusal while row_revise_pending holds.
revise_pending_refusal() { die "the decider asked for a revision at $1 and the row was not revised: the seat runs decision.sh revise first"; }

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
# skips exactly it. A "scrub_allow_words" entry is a phrase of closed-row words that may publish, one word or more: a phrase
# of WORDS_MIN words or more drops every stretch inside it; a shorter phrase adds its words to the common words (they no
# longer count toward WORDS_MIN_RARE), so a stretch that still carries WORDS_MIN_RARE other uncommon words still hits; nothing
# else (the rule lives in scrub_scan). Dies naming the first malformed entry: another type, another key, an empty pattern
# or paths list, a regex Python cannot compile, an allow entry that is not a bare repo name, an allowed phrase that is not
# one line carrying at least one word.
roster_scrub() {
  local r="${1:-}"; [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  python3 -I - "$r" "$WORDS_TOKEN_RE" <<'PY' || exit 1
import json, re, sys
r, tok_re = sys.argv[1], re.compile(sys.argv[2])
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
    if not tok_re.findall(p): die("%s: the phrase carries no word" % where)
    out["allow_words"].append(p)
print(json.dumps(out))
PY
}

# roster_vendored [roster]: the one parser of the roster's top-level "vendored": directories (plain paths relative to a
# repo's root) holding byte-exact copies of upstream packages, whose bytes are the upstream's, not ours. Prints them as a
# compact JSON list, trailing "/" dropped ([] when absent). license.sh skips their manifests; the scrub skips its
# private-repo, private-name, words and roster-scrub classes on their files (scrub_scan). Dies naming a malformed entry
# or one listed twice.
roster_vendored() {
  local r="${1:-}"; [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  python3 -I - "$r" <<'PY' || exit 1
import json, sys
r = sys.argv[1]
V = json.load(open(r, encoding="utf-8")).get("vendored", [])
if not isinstance(V, list): sys.exit("daita-beast: roster %s: \"vendored\" is a list of directory paths, got %s" % (r, json.dumps(V)))
out = []
for i, v in enumerate(V):
    ok = isinstance(v, str) and v.strip() == v and v and "\n" not in v and not v.startswith("/") and not any(p in ("", ".", "..") for p in v.rstrip("/").split("/"))
    if not ok: sys.exit("daita-beast: roster %s: vendored[%d] %s: a plain directory path relative to a repo's root (no leading /, no . or .. part), e.g. \"site/vendor\"" % (r, i, json.dumps(v)))
    v = v.rstrip("/")
    if v in out: sys.exit("daita-beast: roster %s: vendored lists %s twice" % (r, json.dumps(v)))
    out.append(v)
print(json.dumps(out))
PY
}

# roster_license [roster]: the one parser of the roster's "license": the license every public repo of the roster's owners
# carries. Prints it as compact JSON {"name", "file", "manifest", "source": {"repo", "path", "render" | null, "checkout" |
# null}, "exempt": [...]}, or nothing when the roster has no "license". Dies naming the first malformed part: not an object,
# an unknown key ("vendored" is the roster's top-level field, roster_vendored), a missing or empty string, a name that
# cannot sit in one HTML comment line, a file that is not a plain relative path, a source repo that is not owner/repo, a
# checkout that is not an absolute path, an exempt entry that is not owner/repo or is listed twice.
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
if "vendored" in L: die("\"vendored\" moved to the roster's top level: \"vendored\": [<dir>, ...] serves both the license check and the scrub (docs/protocol.md, Roster); move the list there and delete license.vendored")
keys(L, ["name", "file", "manifest", "source", "exempt"], "")
name, f, man = text(L, "name", ""), text(L, "file", ""), text(L, "manifest", "")
if "--" in name: die("name %s: it sits in one HTML comment line, so it may not carry \"--\"" % json.dumps(name))
if f.startswith("/") or any(p in ("", ".", "..") for p in f.split("/")): die("file %s: a plain path relative to a repo's root" % json.dumps(f))
S = L.get("source")
if not isinstance(S, dict): die("source is an object {\"repo\", \"path\", \"render\"?, \"checkout\"?}, got %s" % json.dumps(S))
keys(S, ["repo", "path", "render", "checkout"], "source")
repo, path = text(S, "repo", "source"), text(S, "path", "source")
SLUG = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
if not SLUG.fullmatch(repo): die("source.repo %s: owner/repo" % json.dumps(repo))
if path.startswith("/") or any(p in ("", ".", "..") for p in path.split("/")): die("source.path %s: a plain path relative to the source repo's root" % json.dumps(path))
render, co = text(S, "render", "source", False), text(S, "checkout", "source", False)
if co is not None and not co.startswith("/"): die("source.checkout %s: an absolute path (a checkout of %s on this machine)" % (json.dumps(co), repo))
X = L.get("exempt", [])
if not isinstance(X, list) or not all(isinstance(x, str) and SLUG.fullmatch(x) for x in X):
    die("exempt is a list of owner/repo (public repos under their own license, e.g. a fork of an upstream project), got %s" % json.dumps(X))
dup = sorted({x for x in X if [y.lower() for y in X].count(x.lower()) > 1})
if dup: die("exempt lists %s more than once" % ", ".join(dup))
print(json.dumps({"name": name, "file": f, "manifest": man, "source": {"repo": repo, "path": path, "render": render, "checkout": co}, "exempt": X}))
PY
}

# ---- the scrub gate: the one owner of what may not leave a private twin ----------------------------
# scrub_patterns derives the facts, scrub_scan matches them; publish.sh (a publish's commit, body, release notes) and
# license.sh (a license file's header) both run them. The classes are listed in docs/protocol.md, Publishing.

# roster_repo_owners [roster]: every owner of a repo the roster names (repo, publishes_to, board, seat repos),
# one per line, each once (case-insensitively). The scrub lists their private repos.
roster_repo_owners() {
  local r="${1:-}"; [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  jq -r '[.repo, .publishes_to, .board, (.seats[]?.repo)] | map(select(. != null and contains("/")) | split("/")[0]) | unique_by(ascii_downcase) | .[]' "$r"
}

# roster_public_owners [roster]: the owners whose PUBLIC repos carry the roster's license, license.sh audit's set:
# roster_repo_owners (repo, publishes_to, board, seat repos) plus the owner of every public_intended entry (an owner,
# or owner/repo). The scrub keeps roster_repo_owners: it lists private repos, and a public-intended org's private
# repos are not this twin's to list.
roster_public_owners() {
  local r="${1:-}"; [[ -n "$r" ]] || r="$(roster_path)"
  [[ -f "$r" ]] || die "no roster at $r — run init-repo.sh for this repo first"
  { roster_repo_owners "$r"; jq -r '(.public_intended // [])[] | split("/")[0]' "$r"; } | awk 'NF { k = tolower($0); if (!(k in seen)) { seen[k] = 1; print } }'
}

# scrub_owner_refusal <roster> <owner> <login> <why>: the one refusal of a publish whose roster names an owner the gh login
# cannot list the private repos of (the scrub would pass them). It states the publishing rule and names the owner and the login.
scrub_owner_refusal() {
  die "refused: the roster $1 names the owner $2 (its repo, publishes_to, board or a seat repo), and the gh login $3 cannot list $2's private repos ($4), so the scrub cannot cover them. The rule: each organization publishes its own public repos from its own twin, with a login that can list that owner's private repos. Publish $2's public repos from $2's own twin, as a login that can list $2's private repos"
}

# scrub_patterns [roster]: the pattern bag, JSON {bag, slugs: [...], names: [...], skipped: [...], words: [{url, words}],
# allow_words: [...], roster: [{pattern, paths}], vendored: [<dir>, ...], record_re}: the facts the scanner matches, derived
# from the roster (the repo's own by default) and GitHub (every read through gh_get, so a warm cache costs no quota). names are the bare names
# checked (exact case, 5 characters or more, not in the roster's scrub_allow); skipped the bare names left out, whose slug
# form is still checked. words are the verbatim close words of the twin's closed rows, except a row whose close words are
# exactly its own approving phrase (its '## Approve with', approve_phrase): that phrase is the protocol's, not the decider's.
scrub_patterns() {
  local roster="${1:-}" twin pub slugs="" names="" r o type me words rows n body excl priv lab rs vend list phrase
  [[ -n "$roster" ]] || roster="$(roster_path)"
  [[ -f "$roster" ]] || die "no roster at $roster"
  twin="$(jq -r '.repo // empty' "$roster")"
  [[ "$twin" =~ ^[^/]+/[^/]+$ ]] || die "roster $roster has no \"repo\" (owner/repo), got '$twin'"
  pub="$(jq -r '.publishes_to // empty' "$roster")"
  rs="$(roster_scrub "$roster")" || exit 1
  vend="$(roster_vendored "$roster")" || exit 1
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
  # A listing that cannot be made refuses with the publishing rule (scrub_owner_refusal), naming the owner and the login.
  # An org's listing is trusted only from an active member (user/memberships/orgs/<o>): GitHub answers a non-member's
  # listing with 200 and an empty list, which would pass the scrub with no private names to check.
  local lst mem
  while IFS= read -r o; do
    [[ -n "$o" ]] || continue
    type="$(gh_get "users/$o" | jq -r .type)" || die "cannot read the GitHub account $o (named above)"
    if [[ "$type" == Organization ]]; then
      mem="$(gh_get "user/memberships/orgs/$o" | jq -r '.state // empty')" || mem=""
      [[ "$mem" == active ]] || scrub_owner_refusal "$roster" "$o" "$me" "$me is not an active member of the organization $o (user/memberships/orgs/$o: ${mem:-not a member, or the read failed, named above}), and GitHub answers a non-member's private repo listing with an empty list"
      lst="$(gh_get_all "orgs/$o/repos?type=private")" || scrub_owner_refusal "$roster" "$o" "$me" "the org's private repo listing failed (named above)"
    elif [[ "$(tr 'A-Z' 'a-z' <<< "$o")" == "$(tr 'A-Z' 'a-z' <<< "$me")" ]]; then lst="$(gh_get_all "user/repos?visibility=private&affiliation=owner")" || scrub_owner_refusal "$roster" "$o" "$me" "the login's private repo listing failed (named above)"
    else scrub_owner_refusal "$roster" "$o" "$me" "$o is another user's account, whose private repos no other login can list"; fi
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
      body="$(issue_comments "$twin" "$n" | tag_jq -c --arg u "https://github.com/$twin/issues/$n" --arg p "$phrase" '
        [.[] | close_of(.body) | select(. != null and .words != null) | select($p == "" or .words != $p) | {url: $u, words: .words}]')" \
        || die "cannot read the comments of $twin#$n"
      words="$(jq -c -s 'add' <(printf '%s\n' "$words") <(printf '%s\n' "$body"))"
    done
  done
  jq -n --arg s "$slugs" --arg nm "$names" --argjson w "$words" --argjson rs "$rs" --argjson v "$vend" --arg rec "$RECORD_PATH_RE" '
    ($nm | split("\n") | map(select(length > 0)) | unique) as $all
    | ($all | map(select(length >= 5 and (. as $n | $rs.allow | index($n) | not)))) as $chk
    | {bag: "beast-scrub-patterns/1", slugs: ($s | split("\n") | map(select(length > 0))), names: $chk, skipped: ($all - $chk),
       words: ($w | unique_by(.words)), allow_words: $rs.allow_words, roster: $rs.scrub, vendored: $v, record_re: $rec}'
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
SHAPE = {"slugs": list, "names": list, "skipped": list, "words": list, "allow_words": list, "roster": list, "vendored": list, "record_re": str}
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
    # the roster's scrub_allow_words, one rule: a phrase shorter than WMIN words adds its words to COMMON (they no longer
    # count toward WRARE), and nothing else; a phrase of WMIN words or more drops every stretch inside it (below)
    long_allow = []
    for a in P["allow_words"]:
        aw = words(a)
        if len(aw) < WMIN: COMMON.update(aw)
        else: long_allow.append(aw)
    def grams(ws, rare=True):
        for i in range(len(ws) - WMIN + 1):
            g = tuple(ws[i:i + WMIN])
            if not rare or sum(1 for w in g if w not in COMMON) >= WRARE: yield g
    windows = {}
    for w in P["words"]:
        for g in grams(words(w["words"])): windows.setdefault(g, w["url"])
    for aw in long_allow:
        for g in grams(aw, rare=False): windows.pop(g, None)
    # the roster's vendored directories: byte-exact upstream copies; their content skips the classes of private names
    VENDORED = [v.strip("/") for v in P["vendored"]]
    UPSTREAM_SKIP = {"private-repo", "private-name", "words", "roster-scrub"}
    def vendored(path): return path is not None and any(path == v or path.startswith(v + "/") for v in VENDORED)
    hits = []   # (where, line or None, class id, class text, match); where is a file, "commit <sha>" or "body"
    def scan(where, lineno, line, path=None, kind="file"):
        up = vendored(path)
        for cid, cls, rx, globs in rules:
            if not applies(globs, path) or (up and cid in UPSTREAM_SKIP): continue
            m = rx.search(line)
            if m: hits.append((kind, where, lineno, cid, cls, m.group(0)))
        if beast_line.search(line) and not re.search(r"[<$]", line):
            hits.append((kind, where, lineno, "beast-line", "BEAST- line", line.strip()[:80]))
        for g in ([] if up else grams(words(line))):
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

# repo_public_why <repo> [roster | -]: one line saying why <repo> is public ("listed in the roster's public_intended
# (<entry>)" or "public on GitHub"), or nothing when it is private and not public-intended. The roster is read
# first (a repo that does not exist yet is public-intended by its owner's entry); then GitHub's visibility. "-" is
# no roster (repo_public_why_at, for a checkout that has none): GitHub's visibility only. Names compare
# case-insensitively, as GitHub's do. Dies when <repo> is not owner/repo or its visibility cannot be read.
repo_public_why() {
  local r="$1" roster="${2:-}" hit="" priv
  [[ "$r" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "'$r' is not owner/repo"
  [[ -n "$roster" ]] || roster="$(roster_path)"
  if [[ "$roster" != - ]]; then
    hit="$(jq -r --arg r "$r" '($r | ascii_downcase) as $lr | ($lr | split("/")[0]) as $lo
      | [(.public_intended // [])[] | select((ascii_downcase == $lr) or (ascii_downcase == $lo))] | first // empty' "$roster")" \
      || die "cannot read \"public_intended\" of the roster $roster"
  fi
  if [[ -n "$hit" ]]; then echo "listed in the roster's public_intended ($hit)"; return 0; fi
  priv="$(gh_get "repos/$r" | jq -r .private)" || die "cannot read the visibility of $r (named above)"
  [[ "$priv" == true || "$priv" == false ]] || die "GitHub answered repos/$r without a boolean \"private\""
  [[ "$priv" == true ]] || echo "public on GitHub"
}

# repo_public_why_at <repo> <dir>: repo_public_why with the roster of the checkout <dir> is in when it has one
# (.beast/roster.json at its root), else (no roster, or <dir> in no checkout) GitHub's visibility only. For scripts whose
# target is a checkout that may carry no roster yet (init-repo.sh, bootstrap.sh) or a community repo's (ledger.sh --out).
repo_public_why_at() {
  local root roster=-
  if root="$(checkout_root "$2" 2>/dev/null)" && [[ -f "$root/.beast/roster.json" ]]; then roster="$root/.beast/roster.json"; fi
  repo_public_why "$1" "$roster"
}

# The label sets of templates/labels.json, the one owner: a public or public-intended repo carries only the labels marked
# "public" (the bounty and award flow); every other fixed label, and every seat:* and ws:* label, is coordination and
# lives only in a private repo. labels_public / labels_coordination: the fixed names, one per line.
# label_is_coordination <name>: status 0 for a coordination label.
labels_public() { jq -r '.[] | select(.public == true) | .name' "$BEAST_SCRIPTS/../templates/labels.json"; }
labels_coordination() { jq -r '.[] | select(.public != true) | .name' "$BEAST_SCRIPTS/../templates/labels.json"; }
label_is_coordination() { [[ "$1" == seat:* || "$1" == ws:* ]] || labels_coordination | grep -qxF -- "$1"; }

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

# ---- the close comment: the one owner of its shape (row_close_comment writes it; close_of, SEAT_TAG_JQ, reads it) ------
# The one comment that closes a row. Its first line, the close line, is of one of three kinds:
#   Closed on the word, verbatim: "<words>"                       closed    the decider's words (decision.sh close,
#   Rejected on the word, verbatim: "<words>"                     rejected  pr.sh close, publish.sh merge --words)
#   Merged under standing latitude <<record link>> by <seat id>  latitude  publish.sh merge --latitude: quotes no words;
#                                                                           the record is the decider's standing word, a
#                                                                           file at a commit in the seat's own private repo
# then "Record: <record>. Closed by seat <id> at <UTC>." ("Closed by seat <id> at <UTC>." on a latitude close, whose record
# is in its close line), then the closer's BEAST-ACK (state=seen). A close line is never an answer form (answer_kind): it
# never stands as the decider's answer. CLOSE_LINE_RE reads the close line (jq, and the page's CLOSE_RE alike:
# plugin/tests/regex-mirror.test.mjs); "Closed on the decider's word" is the old pointer close, read with no words.
CLOSE_LINE_RE='^(?:(?<verdict>Closed|Rejected) on the (?:word, verbatim: |decider.s word)|Merged under standing latitude <(?<record>https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/blob/[0-9a-f]{40}/[^ <>]+)> by (?<seat>[A-Za-z0-9-]+/[A-Z0-9_-]+)$)'

# row_close_comment <repo> <N> "<words>" "<record>" <by-id> "<next>" closed|rejected|latitude: posts the close comment,
# the one writer of its shape for a decision issue and a pull request alike. A latitude close takes no words ("") and its
# record is the link latitude_record verified; its close line is checked against CLOSE_LINE_RE before it is posted. The
# caller closes, merges or labels (row_close does it for an issue).
row_close_comment() {
  local repo="$1" n="$2" words="$3" rec="$4" by="$5" next="$6" first tail
  [[ "$by" =~ $SEAT_ID_RE ]] || die "row_close_comment: --by '$by' is not a seat id"
  [[ "$next" != *$'\n'* ]] || die "--next is one line"
  case "$7" in
    closed) first="Closed on the word, verbatim: \"$words\""; tail="Record: $rec. Closed by seat $by at $(utc_now)." ;;
    rejected) first="Rejected on the word, verbatim: \"$words\""; tail="Record: $rec. Closed by seat $by at $(utc_now)." ;;
    latitude)
      [[ -z "$words" ]] || die "row_close_comment: a latitude close quotes no words"
      first="Merged under standing latitude <$rec> by $by"; tail="Closed by seat $by at $(utc_now)."
      jq -en --arg l "$first" --arg re "$CLOSE_LINE_RE" '$l | test($re)' >/dev/null \
        || die "row_close_comment: the latitude close line '$first' does not read back as one (CLOSE_LINE_RE): the record is not a blob link at a full sha" ;;
    *) die "row_close_comment: the kind is closed, rejected or latitude, not '$7'" ;;
  esac
  local ack; ack="$(ack_line "$by" seen "$next")" || exit 1
  issue_comment "$repo" "$n" "$first

$tail

$ack" >/dev/null
}

# row_close <repo> <N> "<words>" "<record>" <by-id> "<next>" closed|rejected|latitude <board repo>: closes a decision issue:
# the close comment (row_close_comment), the issue closed (not_planned and labelled rejected on a reject), then
# row_after_close. The caller has refused a public repo (coord_write_guard) and a pending revise (row_revise_pending).
row_close() {
  [[ $# -eq 8 ]] || die "row_close takes <repo> <N> <words> <record> <by> <next> <kind> <board>, not $*"
  row_close_comment "$1" "$2" "$3" "$4" "$5" "$6" "$7"
  if [[ "$7" == rejected ]]; then row_mark_rejected "$1" "$2"; issue_close "$1" "$2" not_planned
  else issue_close "$1" "$2" completed; fi
  echo "closed $1#$2"
  row_after_close "$1" "$2" "$5" "$8"
}

# latitude_record "<owner/repo> <commit> — <path>" <seat id>: the record of a seat's standing latitude (the decider's word
# letting the seat close its own rows of a kind), verified through GitHub before anything is written: <owner/repo> is the
# seat's own repo (seat_repo), private and not public-intended (repo_public_why), <commit> a commit of it and <path> a file
# at that commit. Prints its link, https://github.com/<owner/repo>/blob/<full sha>/<path>. Which acts fall inside the
# latitude is the seat's own repo's rule, never the plugin's.
latitude_record() {
  [[ $# -eq 2 ]] || die "latitude_record takes \"<owner/repo> <commit> — <path>\" <seat id>, not $*"
  local re='^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+) ([0-9a-fA-F]{7,40}) — ([^[:space:]<>]+)$' r c p own why sha t
  [[ "$1" =~ $re ]] || die "--latitude '$1' is not '<owner/repo> <commit> — <path>' (an em dash between the commit and a path with no space)"
  r="${BASH_REMATCH[1]}"; c="${BASH_REMATCH[2]}"; p="${BASH_REMATCH[3]}"
  [[ "$p" != /* && "/$p/" != */../* && "/$p/" != */./* ]] || die "--latitude path '$p' is not a plain path relative to the repo's root"
  own="$(seat_repo "$2")" || exit 1
  [[ "$(tr 'A-Z' 'a-z' <<< "$r")" == "$(tr 'A-Z' 'a-z' <<< "$own")" ]] \
    || die "refused: the latitude record is in $r, not in $own, the own repo of $2: a seat's standing latitude is recorded in its own private repo"
  why="$(repo_public_why "$r")" || exit 1
  [[ -z "$why" ]] || die "refused: the latitude record's repo $r is $why: the decider's standing word is recorded in a private repo"
  sha="$(gh_get "repos/$r/commits/$c" | jq -er '.sha')" || die "refused: $r has no commit $c (named above): the latitude record is a file at a commit"
  t="$(gh_get "repos/$r/contents/$(contents_path "$p")?ref=$sha" | jq -r 'if type == "object" then .type else "dir" end')" \
    || die "refused: $r has no $p at ${sha:0:12} (named above): the latitude record is a file at that commit"
  [[ "$t" == file ]] || die "refused: $p at ${sha:0:12} in $r is a $t, not a file: the latitude record is a file"
  echo "https://github.com/$r/blob/$sha/$p"
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
    addr="$("$BEAST_SCRIPTS/seats.sh" address "$s" 2>/dev/null | sed -n '1p;/^path:/p' | paste -sd ' ' - || true)"
    echo "  $s -> unacked; ${addr:-no live address recorded (seats.sh address $s)}"
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

# ---- the seat-to-seat tag: the one owner (the page's MSG_RE is the JS twin) ----
# BEAST-MSG from=<composite> to=<composite> re=<ref|none> blocking=no at=<UTC>   the first line of every direct line
# one seat sends another by SendMessage, and of the durable copy desk.sh msg writes on the recipient's desk; then the
# body. <ref> is what it is about (owner/repo#N, a URL, or none). It never names the decider's board, never waits on
# the decider and is never shown on the board: a seat that needs his word files a row. msg_header writes it,
# desk_parse reads it (the comment's own time, not the tag's, orders a desk).
MSG_HEADER_RE='^BEAST-MSG from=(?<from>[a-z0-9][a-z0-9-]*/[A-Z0-9_-]+/[A-Za-z0-9-]+) to=(?<to>[a-z0-9][a-z0-9-]*/[A-Z0-9_-]+/[A-Za-z0-9-]+) re=(?<re>[^ ]+) blocking=no at=(?<at>[^ ]+)$'

# msg_header <from composite> <to composite> [<ref>]: the tag line, stamped now (ref defaults to none).
msg_header() {
  local l="BEAST-MSG from=$1 to=$2 re=${3:-none} blocking=no at=$(utc_now)"
  jq -en --arg l "$l" --arg re "$MSG_HEADER_RE" '$l | test($re)' >/dev/null || die "msg_header: '$l' is not BEAST-MSG from=<slug>/<LABEL>/<login> to=<slug>/<LABEL>/<login> re=<ref|none> blocking=no at=<UTC>"
  printf '%s\n' "$l"
}

# ---- bookkeeping comments: the one list of first lines the relay never reports as news -------------------------
# A comment whose first line is a seat's or a tool's own bookkeeping (an ack, a status, the notes, an address, the
# Cowork tick's stamp, the machine watchdog's lines and its notes, a close line (CLOSE_LINE_RE), a publish amend line) is not an UPDATED
# event for a seat (watch.sh); edits never bump a comment count, so an edited one fires nothing either. One owner:
# comment_is_bookkeeping is the test.
BOOKKEEPING_FIRST_LINE_RE="^(BEAST-ACK|BEAST-STATUS|BEAST-NOTES|BEAST-ADDRESS|BEAST-COWORK|BEAST-WATCHDOG|BEAST-WATCHDOG-NOTES)( |\$)|$CLOSE_LINE_RE|$AMEND_LINE_RE"

# comment_is_bookkeeping "<first line>": status 0 when the line is bookkeeping, 1 when it is news.
comment_is_bookkeeping() { jq -en --arg l "$1" --arg re "$BOOKKEEPING_FIRST_LINE_RE" '$l | test($re)' >/dev/null; }

# ask_header <n> <id> <at> [<milestone title>]: the header line of an ask.
ask_header() {
  local n="$1" id="$2" at="$3" ms="${4:-}"
  [[ "$n" =~ ^[0-9]+$ ]] || die "ask_header: n '$n' is not a number"
  [[ "$id" =~ $SEAT_ID_RE ]] || die "ask_header: '$id' is not a seat id"
  [[ -z "$ms" ]] || milestone_title_check "$ms"
  printf 'BEAST-ASK n=%s seat=%s at=%s%s\n' "$n" "$id" "$at" "${ms:+ milestone=\"$ms\"}"
}

# ask_inline_check <what> <text>: dies when a question for the decider points elsewhere for its substance: a session ("see
# session", "see my session", "as discussed", "per our chat") or a path on one machine (/Users/…, /home/…, ~/…). The decider
# reads only the row: its content is inline, or a URL to a file or diff at a commit. decision.sh new (record files through
# it) and desk.sh ask run it before anything is written.
ask_inline_check() {
  local what="$1" hit
  hit="$(printf '%s' "$2" | python3 -I -c '
import re, sys
t = sys.stdin.read()
for rx, fl in ((r"\bsee (?:the |my |our |this )?session\b", re.I), (r"\bas (?:we )?discussed\b", re.I),
               (r"\bper our (?:chat|conversation|discussion|session)\b", re.I),
               (r"(?<![A-Za-z0-9_.~/-])/(?:Users|home)/[^\s/]+", 0), (r"(?<![^\s(\[\x27\"`=:,])~/", 0)):
    m = re.search(rx, t, fl)
    if m: print(m.group(0)); break
')" || die "$what: cannot read the question text"
  [[ -z "$hit" ]] || die "$what: the question points elsewhere for its substance (\"$hit\"), and the decider reads only the row. The rule: the content inline, or a URL to a file or diff at a commit (https://github.com/<owner>/<repo>/blob/<sha>/<path>, …/commit/<sha>), never a session or a local path"
}

# ask_next_n <comments-json>: the n of a desk's next ask: the highest n of every comment whose first line opens as an
# ask header (a malformed one included, so no n is reused), plus one.
ask_next_n() {
  jq -r '[.[] | (.body // "") | split("\n")[0] | capture("^BEAST-ASK n=(?<n>[0-9]+) ") | .n | tonumber] | (max // 0) + 1' <<< "$1" \
    || die "cannot read the ask numbers of a desk"
}

# desk_find <id> <repo>: "<repo> <number> <state>" of the seat's desk in <repo> (seat_repo: the seat's own repo, this
# roster's or the table's), or nothing; dies when there are two. The list API, not search: search lags a create by
# seconds and would mint a second desk.
desk_find() {
  [[ $# -eq 2 ]] || die "desk_find takes <id> <repo> (the seat's repo, seat_repo), not $*"
  local id="$1" repo="$2" got n
  [[ "$repo" =~ ^[^/]+/[^/]+$ ]] || die "desk_find: '$repo' is not owner/repo"
  got="$(issues_list "$repo" -f labels="desk,seat:$id" -f state=all | jq -c '[.[] | select(.pull_request == null) | {number, state, html_url}]')" \
    || die "cannot list the issues of $repo (403 = repo not attached to this session or no access)"
  n="$(jq length <<< "$got")"
  [[ "$n" -le 1 ]] || die "$repo has $n desks for $id: $(jq -r '[.[].html_url] | join(" and ")' <<< "$got") — close all but one by hand"
  [[ "$n" -eq 1 ]] || return 0
  echo "$repo $(jq -r '.[0].number, .[0].state' <<< "$got" | tr '\n' ' ')"
}

# desk_parse <id> <row>: (a row_read of the desk) the desk's comments read into {asks:[…], messages:[…], dropped:[…],
# history: <n>}, in comment order. Each ask: {n, url, at, milestone (null on an ask without one), waits_on:[refs],
# question:[lines], options, default, state: open|answered|withdrawn, answer:{text, url, at, by}}. The question lines
# are the ask's lines other than `options:`, `default:` and the `Waits on: <ref>` lines (waits_on_parse's shape). Each
# message: {from, at, url, text}. The dropped lines are printed on stderr here. A BEAST-MSG line that is not the shape
# (the pre-1.5.0 `from=<login>/<LABEL> to=<login>/<LABEL> at=<UTC>` tag) is dropped loud only inside the seat's inbox
# window, newer than its last ack on the desk (seat_acks); older ones are dated history the seat acted on: counted
# in `history` and named once in one stderr line, never listed. With no ack every comment is in the window.
desk_parse() {
  local id="$1" row="$2" parsed ack
  ack="$(seat_acks "$row" | awk -F'\t' -v s="$id" '$1 == s {print $2}')"
  parsed="$(jq '.comments' <<< "$row" | jq -c --arg seat "$id" --arg ack "$ack" --arg askre "$ASK_HEADER_RE" --arg wre "$WAITS_ON_RE" --arg msgre "$MSG_HEADER_RE" --argjson as "$(jq -c '[.issue.assignees[].login]' <<< "$row")" '
    def m(re): [capture(re)] | .[0];
    def short: split("/") | if length == 3 then "\(.[2])/\(.[1])" else join("/") end;
    ("(words typed to " + $seat + "'"'"'s session, verbatim)") as $typed |
    reduce (.[] | {url: .html_url, at: .created_at, by: .user.login, lines: ((.body // "") | gsub("\r"; "") | split("\n"))}) as $c
      ({asks: {}, order: [], messages: [], dropped: [], history: 0};
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
           ($f | m($msgre)) as $a
           | if $a == null and $ack != "" and $c.at <= $ack then .history += 1
             elif $a == null then .dropped += ["malformed BEAST-MSG line (BEAST-MSG from=<composite> to=<composite> re=<ref|none> blocking=no): \($c.url)"]
             elif ($a.to | short) != $seat then .dropped += ["a message to \($a.to) on the desk of \($seat): \($c.url)"]
             else .messages += [{from: $a.from, re: $a.re, at: $c.at, url: $c.url, text: ([$rest[] | select(test("\\S"))] | join("\n"))}] end
         elif ($f | test("^BEAST-WATCHDOG(-NOTES)?( |$)")) then .dropped += ["a BEAST-WATCHDOG line is the machine watchdog'"'"'s, never an answer or a message (the watchdog posts only on the plugin twin): \($c.url)"]
         elif ($f | startswith("BEAST-")) then .
         elif ($as | index($c.by)) != null then .messages += [{from: "@\($c.by)", at: $c.at, url: $c.url, text: ($c.lines | map(select(test("\\S"))) | join("\n"))}]
         else .dropped += ["a plain comment by \($c.by), not an assignee of the desk, is neither an answer nor a message: \($c.url)"] end)
    | {asks: [.order[] as $k | .asks[$k]], messages, dropped, history}')" || die "cannot read the desk of $id"
  jq -r '.dropped[] | "daita-beast: desk of '"$id"': dropped: \(.)"' <<< "$parsed" >&2
  jq -r 'select(.history > 0) | "daita-beast: desk of '"$id"': \(.history) pre-1.5.0 message line(s) older than the last ack ('"$ack"'): history, not read"' <<< "$parsed" >&2
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
      words="$(tag_jq -r 'close_last(.comments) | if . == null then "" else close_text(.) end' <<< "$row")" \
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
  id="$(seat_id "$ref")" || exit 1   # a dependency names ANOTHER seat, in this repo or not: its home is seat_repo's
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
  f="$(desk_find "$id" "$home")" || exit 1
  if [[ -n "$f" ]]; then
    read -r repo n state <<< "$f"
    parsed="$(desk_parse "$id" "$(row_read "$repo" "$n")")" || exit 1
    jq -r '.asks[] | select(.state == "open") | .url as $u | .waits_on[] | "\(.)\t\($u)"' <<< "$parsed"
  fi
}
