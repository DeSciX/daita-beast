#!/usr/bin/env bash
# join.sh — take a seat, or retake it after a reload or compaction, from ANY directory. Seating sets the root.
#   join.sh <LABEL | login/LABEL | slug/LABEL/login> [--address "<name>"] [--agent <name>] [--workstream <slug>]
# The seat is found on this machine (seat_locate, lib.sh: the launch folder's checkout, the folders of its VS Code
# workspace, the machine index ~/.beast/checkouts.json) and every step runs against the seat's home (seat_home_path):
# 1 roster: the seat's row in the roster of the checkout of its own repo; --agent changes its role (the agent file
#   must exist), --workstream moves it to another workstream (whose tracking issue must exist); its tracking issue is
#   found by the workstream's labels (workstream_issue). Refused only when the home does not exist here, naming the
#   clone and seat.sh new steps. The first line printed is "SEATED <id> at <home>"; then "role: <agent> at <path>";
#   then the session claim (sessions_claim, lib.sh: this session holds the seat, read by the SessionStart hook to rejoin).
# 2 address: recorded by seats.sh record (the BEAST-ADDRESS comment on the tracking issue): this session's name, read
#   from its Claude Code session file (claude_session_of $CLAUDE_CODE_SESSION_ID, lib.sh), or --address when given.
#   When the name cannot be read, one line "address: not recorded — <the failure>" and the manual record line.
# 3 CLAUDE.md: the block between <!-- beast:begin --> and <!-- beast:end --> in the home's CLAUDE.md is regenerated
#   from templates/claude-block.md for this seat (its identity, its role, its workstream's seat map).
# 4 memory: the auto-memory folder this session loads (session_memory_dir, lib.sh), triaged by memory_triage: the
#   files and MEMORY.md lines that restate seat state are listed to act on, another seat's are named as theirs,
#   lessons and pointers are kept (never edits them). 5 resume: resume.sh <id> (handoff, notes, inbox).
# 6 the home's CLAUDE.md path, to read now: it does not load by itself in a session started elsewhere.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq git
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
seat="${1:-}"; shift || true
[[ -n "$seat" && "$seat" != -* ]] || die "usage: join.sh <LABEL | login/LABEL | slug/LABEL/login> [--address \"<name>\"] [--agent <name>] [--workstream <slug>]"
address=""; ws=""; agent=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --address) address="$2"; shift 2 ;;
    --workstream) ws="$2"; shift 2 ;;
    --agent) agent="$2"; shift 2 ;;
    --role|--tracking) die "$1 is gone: the role is an agent file (--agent <name>) and the tracking issue is found by its labels (--workstream <slug>)" ;;
    *) die "unknown argument $1" ;;
  esac
done
launch="$PWD"; launch_p="$(pwd -P)"

# Locate, then work in the checkout of the seat's own repo: every later step reads its roster.
loc="$(seat_locate "$seat" "$launch")" || exit 1
seat="${loc%%$'\t'*}"; root="${loc#*$'\t'}"
cd "$root"
roster="$(roster_path)"; remote="$(repo_slug "$root")" || exit 1
roster_check_unique "$roster"
login="$(seat_login "$seat")"; label="$(seat_label "$seat")"
sel='.seats[] | select(.github == $g and .label == $l)'
kind="$(seat_home_kind "$seat")" || exit 1
home="$(seat_home_path "$seat")" || exit 1
home_p="$(cd "$home" 2>/dev/null && pwd -P)" || home_p=""
notes=()
# A worktree seat in a cloud session runs in the repo itself at the seat's branch (a cloud session opens a repo
# and a branch; the local worktree path does not exist there).
branch="$(jq -r --arg g "$login" --arg l "$label" "$sel | .home.branch // empty" "$roster")"
if [[ "$kind" == worktree && -z "$home_p" && -n "$branch" && "$(git -C "$root" branch --show-current 2>/dev/null)" == "$branch" && "$launch_p" == "$root" ]]; then
  notes+=("home: the repo at branch $branch (no local worktree here: a cloud session or a fresh clone)")
  home="$root"; home_p="$root"
  if [[ ! -f "$home/.beast/seat.json" ]]; then
    mkdir -p "$home/.beast"
    jq -n --arg id "$seat" '{id:$id, kind:"worktree"}' > "$home/.beast/seat.json"
    notes+=("seat.json written for this clone (gitignored)")
  fi
fi
[[ -n "$home_p" ]] || die "the home of $seat ($home, kind $kind) does not exist on this machine: create it with $here/seat.sh new $label --repo-path $root${branch:+, or in a cloud session open the repo at branch $branch}"
if [[ "$kind" == legacy ]]; then
  notes+=("seat $seat has no home recorded in $roster; read as a checkout home ($home). Record it: $here/seat.sh new $label --repo-path $root --kind checkout")
else
  sj="$(seat_json_id "$home")" || exit 1
  [[ -n "$sj" ]] || die "$home/.beast/seat.json is absent: the home of $seat is made by $here/seat.sh new $label --repo-path $root"
  [[ "$sj" == "$seat" ]] || die "$home/.beast/seat.json names $sj, not $seat: two seats never share a home"
fi
if [[ -n "$ws" ]]; then
  [[ "$ws" =~ $WS_SLUG_RE ]] || die "--workstream '$ws' is not a slug (a-z, 0-9, -)"
  workstream_issue "$ws" >/dev/null || exit 1
fi
[[ -z "$agent" ]] || seat_agent_check "$remote" "$agent" || exit 1

echo "SEATED $seat at $home"
checkouts_record "$root"
echo "== 1. roster ($roster) and home"
echo "home: $kind $home (launch folder: $launch)"
for n in "${notes[@]+"${notes[@]}"}"; do echo "$n"; done
if [[ -n "$agent" ]]; then
  jq --arg g "$login" --arg l "$label" --arg a "$agent" "($sel | .agent) = \$a" "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
  echo "agent of $seat set to $agent (commit the roster)"
fi
if [[ -n "$ws" ]]; then
  old="$(roster_field "$seat" workstream)"
  jq --arg g "$login" --arg l "$label" --arg w "$ws" "($sel | .workstream) = \$w" "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
  echo "workstream of $seat set to $ws (commit the roster${old:+; move its row in the seat maps: workstream.sh seat-remove $old $seat, then seat-add $ws $seat …, then render both})"
fi
roster_check_unique "$roster"
ws="$(roster_field "$seat" workstream)"; agent="$(roster_field "$seat" agent)"
identity="$(seat_identity_of "$seat" "$ws")"
tracking="$(workstream_issue "$ws")" || exit 1
apath="$(seat_agent_path "$remote" "$agent")" || exit 1
echo "$identity: repo $remote, workstream $ws, tracking $tracking"
echo "role: $agent at $apath"
if [[ "$agent" == daita-beast:* || "$apath" == /* ]]; then echo "  a terminal session runs the role with: cd $home && claude --agent $agent"; fi
sessions_claim "$identity" "$launch_p" "$tracking"

echo "== 2. address"
if ! rec="$("$here/seats.sh" record "$seat" ${address:+"$address"} 2>&1)"; then
  echo "address: not recorded — $(tail -1 <<< "$rec" | sed 's/^daita-beast: //'). Record it by hand: cd $home && $here/seats.sh record $seat \"<this session's ListAgents name>\""
else printf '%s\n' "$rec"; fi

echo "== 3. CLAUDE.md block (the home's CLAUDE.md)"
md="$home/CLAUDE.md"
if [[ ! -f "$md" ]]; then
  [[ "$kind" != wrapper ]] || die "$md is absent: the wrapper home's CLAUDE.md is written by $here/seat.sh new"
  [[ "$kind" != subdir ]] || die "$md is absent: a subdir home is a directory with its own CLAUDE.md (seat.sh new checked it); restore it"
  : > "$md"
fi
claude_block_write "$md" "$identity"

echo "== 4. memory: the auto-memory this session loads, shared by every seat started in that folder (never edited here)"
m="$(session_memory_dir "$launch")" || exit 1
memdir="${m%%$'\t'*}"; echo "$memdir (${m#*$'\t'})"
if [[ ! -d "$memdir" ]]; then echo "no auto-memory directory there yet: nothing to triage"
else
  ids="$(seat_homes_on_machine "$launch" | cut -f1 | sort -u)" || exit 1
  tri="$(memory_triage "$memdir" "$seat" $ids)" || exit 1
  echo "Lessons (frontmatter type feedback, user or reference) are never flagged. A short pointer to a seat's tracking issue, as a file or as one line of MEMORY.md, is allowed for any seat, this one or another."
  st="$(awk -F'\t' '$1 == "state" {print "  " $2 " (" $3 ")"}' <<< "$tri")"
  if [[ -n "$st" ]]; then
    echo "These restate seat state; working state lives in the handoff on $tracking, durable seat facts in notes.sh $seat. Delete each, or cut it to a pointer or a lesson true for every seat started there, and fix its MEMORY.md line (the seat-clerk agent drafts this triage):"
    printf '%s\n' "$st"
  else echo "Nothing restates seat state."; fi
  ow="$(awk -F'\t' '$1 == "owned" {print "  " $2 ": owned by " $3 "; leave it"}' <<< "$tri")"
  [[ -z "$ow" ]] || { echo "Another seat's (never this seat's to delete):"; printf '%s\n' "$ow"; }
  echo "Kept: $(awk -F'\t' '{n[$1]++} END {printf "%d lesson(s), %d pointer(s), %d other", n["lesson"], n["pointer"], n["clean"]}' <<< "$tri")."
fi

echo "== 5. resume"
"$here/resume.sh" "$seat"

echo "== 6. your root is $home"
if [[ "$launch_p" == "$home_p" ]]; then
  echo "This session started in the home, so $home/CLAUDE.md loaded at start; reread it after any compaction."
else
  echo "Read $home/CLAUDE.md now: this session started in $launch, so it did not load. Reread it after any compaction."
fi
echo "From here on: every shell command starts with cd $home && (or uses git -C $home and absolute paths), because the shell returns to $launch after each command; every file edit uses an absolute path under $home."
