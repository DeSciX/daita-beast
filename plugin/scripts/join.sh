#!/usr/bin/env bash
# join.sh — join or rejoin the Beast workflow as a seat, from the seat's home. Safe every session.
#   join.sh <LABEL | login/LABEL> [--address "<ListAgents name [ref]>"] [--tracking <owner/repo#N>] [--role "<text>"]
# 1 roster: the seat must be in this repo's .beast/roster.json (a new seat is created by seat.sh new); --role
#   updates its role; its tracking issue is stored (--tracking) or must already be there. The session must run
#   in the seat's home (seat_home_path: checkout, worktree, wrapper or subdir), else join stops naming the home:
#   one seat per directory, so a subdir seat never joins from the checkout root, nor a checkout seat from a subdir.
# 2 address: recorded when --address is given. 3 CLAUDE.md: the block between <!-- beast:begin --> and
#   <!-- beast:end --> in the CLAUDE.md the home loads is regenerated from templates/claude-block.md.
# 4 memory: lists the home's auto-memory files that duplicate GitHub state (never edits them).
# 5 resume: prints resume.sh <id> (handoff, notes, inbox).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq git
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat="${1:-}"; shift || true
[[ -n "$seat" && "$seat" != -* ]] || die "usage: join.sh <LABEL | login/LABEL> [--address \"name [ref]\"] [--tracking owner/repo#N] [--role \"text\"]"
address=""; tracking=""; role=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --address) address="$2"; shift 2 ;;
    --tracking) tracking="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
root="$(repo_root)"; roster="$(roster_path)"
[[ -f "$roster" ]] || die "no roster at $roster — set the repo up first: $here/bootstrap.sh --repo <owner/repo> --path $(repo_main_root) --seat $seat"
remote="$(repo_slug "$root")" || exit 1

echo "== 1. roster ($roster) and home"
seat="$(seat_id "$seat")" || exit 1
roster_seat_ids "$roster" | grep -qxF -- "$seat" || die "seat $seat is not in $roster: create it with $here/seat.sh new $(seat_label "$seat") --repo-path $root --role \"<what this seat owns>\" --tracking <owner/repo#N>"
login="$(seat_login "$seat")"; label="$(seat_label "$seat")"
sel='.seats[] | select(.github == $g and .label == $l)'
seat_repo="$(jq -r --arg g "$login" --arg l "$label" "$sel | .repo" "$roster")"
[[ "$seat_repo" == "$remote" ]] || die "seat $seat works in $seat_repo, but this directory is $remote — join from the seat's home in a checkout of $seat_repo"
kind="$(seat_home_kind "$seat")" || exit 1
home="$(seat_home_path "$seat")" || exit 1
here_p="$(pwd -P)"; home_p="$(cd "$home" 2>/dev/null && pwd -P)" || home_p=""
# A worktree seat in a cloud session runs in the repo itself at the seat's branch (a cloud session opens a repo
# and a branch; the local worktree path does not exist there).
branch="$(jq -r --arg g "$login" --arg l "$label" "$sel | .home.branch // empty" "$roster")"
if [[ "$kind" == worktree && -z "$home_p" && -n "$branch" && "$(git -C "$root" branch --show-current 2>/dev/null)" == "$branch" && "$here_p" == "$(cd "$root" && pwd -P)" ]]; then
  echo "home: the repo at branch $branch (no local worktree here: a cloud session or a fresh clone)"
  home="$root"; home_p="$here_p"
  if [[ ! -f "$home/.beast/seat.json" ]]; then
    mkdir -p "$home/.beast"
    jq -n --arg id "$seat" '{id:$id, kind:"worktree"}' > "$home/.beast/seat.json"
    echo "seat.json written for this clone (gitignored)"
  fi
fi
[[ -n "$home_p" ]] || die "open the session in $home ($here/seat.sh where $seat) — that home does not exist on this machine: create it with $here/seat.sh new $label --repo-path <the main checkout>${branch:+, or in a cloud session open the repo at branch $branch}"
[[ "$here_p" == "$home_p" ]] || die "open the session in $home ($here/seat.sh where $seat; home kind $kind); this session runs in $PWD: one seat per directory, and a seat joins only from its own home"
if [[ "$kind" == legacy ]]; then
  echo "seat $seat has no home recorded in $roster; read as a checkout home ($home). Record it: $here/seat.sh new $label --repo-path $root --kind checkout"
else
  sj="$(seat_json_id "$home")" || exit 1
  [[ -n "$sj" ]] || die "$home/.beast/seat.json is absent: the home of $seat is made by $here/seat.sh new"
  [[ "$sj" == "$seat" ]] || die "$home/.beast/seat.json names $sj, not $seat"
  echo "home: $kind $home"
fi
if [[ -n "$role" ]]; then
  jq --arg g "$login" --arg l "$label" --arg r "$role" "($sel | .role) = \$r" "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
  echo "role of $seat updated"
fi
roster_check_unique "$roster"
if [[ -n "$tracking" ]]; then
  tracking="$(tracking_ref "$tracking")" || exit 1
  jq --arg g "$login" --arg l "$label" --arg t "$tracking" "($sel | .tracking) = \$t" "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
fi
tracking="$(jq -r --arg g "$login" --arg l "$label" "$sel | .tracking // empty" "$roster")"
if [[ -z "$tracking" ]]; then
  echo "no tracking issue stored for $seat. Open workstream issues among the roster's owners:" >&2
  search_issues "is:open is:issue label:workstream $(roster_user_terms)" | jq -r '.[] | "  \(.repository_url | sub(".*/repos/"; ""))#\(.number)  \(.title)"' >&2
  die "rerun with --tracking <owner/repo#N>, or open one: $here/workstream.sh new --owner <org> --title \"WS: …\" --repo $seat_repo --northstar-file <f> --seats $label"
fi
echo "$seat: repo $seat_repo, tracking $tracking"

echo "== 2. address"
if [[ -n "$address" ]]; then "$here/seats.sh" record "$seat" "$address"; else echo "(no --address: run seats.sh record $seat \"<your ListAgents name [ref]>\" or pass --address)"; fi

echo "== 3. CLAUDE.md block (the CLAUDE.md this home loads)"
md="$home/CLAUDE.md"
if [[ ! -f "$md" ]]; then
  [[ "$kind" != wrapper ]] || die "$md is absent: the wrapper home's CLAUDE.md is written by $here/seat.sh new"
  [[ "$kind" != subdir ]] || die "$md is absent: a subdir home is a directory with its own CLAUDE.md (seat.sh new checked it); restore it"
  : > "$md"
fi
claude_block_write "$md"

echo "== 4. memory (the home's auto-memory; never edited here)"
memdir="$HOME/.claude/projects/$(printf '%s' "$home" | sed 's#[^A-Za-z0-9-]#-#g')/memory"
if [[ -d "$memdir" ]]; then
  hits="$(grep -l -i -E 'BEAST-STATUS|seat state|seat_state|resume\.sh|seats\.sh|handoff|the board|board as|decision\.sh' "$memdir"/*.md 2>/dev/null | grep -v '/MEMORY.md$' || true)"
  if [[ -n "$hits" ]]; then
    echo "these files restate seat state or Beast rules; working state lives in the handoff on $tracking, durable seat notes in notes.sh $seat, and the rules in the CLAUDE.md block. Delete each, or cut it to lessons about the repo, and fix MEMORY.md's index (the seat-clerk agent drafts this triage):"
    printf '  %s\n' $hits
  else echo "nothing duplicates GitHub state in $memdir"; fi
else echo "no auto-memory directory at $memdir"; fi

echo "== 5. resume"
"$here/resume.sh" "$seat"
