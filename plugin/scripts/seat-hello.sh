#!/usr/bin/env bash
# seat-hello.sh — SessionStart hook. In a seat's home (a $PWD/.beast/seat.json naming a roster seat whose derived
# home, seat_home_path, is $PWD, and whose row is not retired) it adds context naming the seat, its role, its first act and its tracking issue (the
# roster and the workstream issue, the owners), its recorded address and its age with the refresh line (ListAgents,
# then seats.sh record), and when other seats are listable too it names it as this folder's seat, not as certainly
# this session's. Anywhere else it lists the gh login's seats a session here can take (seat_homes_on_machine:
# those of the folders of every VS Code workspace file that lists $PWD, found walking up from it (vscode_workspace_folders),
# when there is one, else every rostered seat of the
# login on this machine; a retired seat is not one), each with its join.sh command; it claims none: the person or the
# session names the seat. With none, it prints nothing.
# Every context line opens with the scripts path (lib.sh plugin_root: $CLAUDE_PLUGIN_ROOT, else ~/.beast/plugin.json),
# or with the install hint when there is none; the committed CLAUDE.md block carries no machine path.
# After a compaction (input "source": "compact") it leads with the handoff, because PreCompact cannot add
# context (the hooks reference: "Claude Code discards a PreCompact hook's `systemMessage` and `continue` fields").
# A hook never fails the session: a fault is put into the context, named, and the hook exits 0.
set -u
input="$(cat)"
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"

# hello: the context line, or nothing. Runs in a subshell that sources lib.sh, whose die exits that subshell.
hello() {
  source "$scripts/lib.sh"
  local root="" roster here sid="" sret="" homeid="" homectx="" homeact="" compacted="" home tracking label login scope where_ list="" id c h k ws ret identity agent a age addr sline coord=""
  here="$(pwd -P)"
  # The scripts path, printed at every session start in a coordinated repo (the CLAUDE.md block says so): plugin_root
  # is $CLAUDE_PLUGIN_ROOT, else the root ~/.beast/plugin.json records, else the install hint (its die message).
  if sline="$(plugin_root 2>&1)"; then sline="scripts: $sline/scripts"; else sline="${sline#daita-beast: }"; fi
  if root="$(repo_root 2>/dev/null)"; then
    roster="$(roster_path)"
    [[ ! -f "$roster" ]] || coord=1
    sid="$(seat_json_id "$PWD")"
    [[ ! -f "$roster" || -z "$sid" ]] || sret="$(roster_field "$sid" retired)"
    if [[ -f "$roster" && -n "$sid" && -z "$sret" && $'\n'"$(roster_seat_ids "$roster")"$'\n' == *$'\n'"$sid"$'\n'* ]] \
       && home="$(seat_home_path "$sid" 2>/dev/null)" && [[ "$(cd "$home" 2>/dev/null && pwd -P)" == "$here" ]]; then
      homeid="$sid"; label="$(seat_label "$sid")"
      ws="$(roster_field "$sid" workstream)"; agent="$(roster_field "$sid" agent)"
      identity="$(seat_identity_of "$sid" "$ws")"
      tracking="$(workstream_issue "$ws")" || exit 1
      if a="$(seat_address_read "$identity")" && [[ -n "$a" ]]; then
        age="$(address_age "$(jq -r .at <<< "$a")")"
        addr="recorded address: $(jq -r .address <<< "$a") on $(jq -r .machine <<< "$a") as $(jq -r .account <<< "$a"), $(jq -r .at <<< "$a") (${age%%$'\t'*}, ${age#*$'\t'})."
      else addr="no address recorded (no BEAST-ADDRESS comment on $tracking)."; fi
      homeact="Role: $agent. First act: run $scripts/join.sh $label --address \"<your ListAgents name [ref]>\", then work the inbox it prints. Refresh your address: ListAgents, then \`seats.sh record $label \"<name [ref]>\"\` ($addr) Before any compaction or shutdown: $scripts/status.sh $tracking --seat $label --state handoff."
      [[ "$src" != compact ]] || compacted="This session was just compacted. If it is $identity, post the handoff on $tracking now, from the summary: $scripts/status.sh $tracking --seat $label --state handoff --next \"<next act>\" --text \"<state, waiting on, branches, gotchas>\". "
      homectx="${compacted}This session is the Beast seat $identity. $homeact"
    fi
  fi
  if [[ -n "$(vscode_workspace_folders "$PWD")" ]]; then scope=workspace; where_="in this VS Code workspace"
  else scope=machine; where_="rostered on this machine"; fi
  login="$(gh_login)"
  while IFS=$'\t' read -r id c h k ws ret; do
    [[ -n "$id" && "$id" != "$homeid" && "$(seat_login "$id")" == "$login" && -z "$ret" ]] || continue
    list="$list $ws/$(seat_label "$id")/$login (home $h): $scripts/join.sh $(seat_label "$id");"
  done < <(seat_homes_on_machine "$PWD" "$scope")
  local how="run that join.sh command from here (any directory works). It prints SEATED <id> at <home>, and from then on the home is the seat's root: every shell command starts with cd <home> &&, file edits use absolute paths under it, and <home>/CLAUDE.md is read then and after any compaction. Two seats never share a home; any number share a launch folder."
  if [[ -n "$homectx" ]]; then
    # This folder is a seat's home and also the launch folder of others: say both, claim neither for certain.
    if [[ -z "$list" ]]; then echo "$sline. $homectx"; return 0; fi
    echo "$sline. ${compacted}This folder is the home of the Beast seat $identity. If this session is that seat: $homeact Other seats of $login $where_ that a session here can take:${list%;}. When the person names one of them, $how"
    return 0
  fi
  [[ -n "$list" ]] || { [[ -z "$coord" ]] || echo "$sline."; return 0; }
  local why_not=""
  if [[ -n "$sret" ]]; then why_not=" (its .beast/seat.json names $sid, retired $sret)"
  elif [[ -n "$sid" ]]; then why_not=" (its .beast/seat.json names $sid, whose home is elsewhere)"; fi
  [[ "$src" != compact ]] || echo "This session was just compacted: if it holds a seat, post that seat's handoff now from the summary ($scripts/status.sh <tracking> --seat <LABEL> --state handoff --next \"<next act>\" --text \"<state, waiting on, branches, gotchas>\"), then rerun its join.sh and reread <home>/CLAUDE.md."
  echo "$sline. This session runs in $PWD, which is not the home of a Beast seat${why_not}. The seats of $login $where_:${list%;}. This session holds no seat until the person names one; then $how"
}

err="$(mktemp)"
ctx="$( (hello) 2>"$err" )" || true
if [[ -s "$err" && -z "$ctx" ]]; then
  ctx="The Beast SessionStart hook could not name this directory's seat or home: $(tr '\n' ' ' < "$err"). Tell the user."
fi
rm -f "$err"
[[ -n "$ctx" ]] || exit 0
jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
