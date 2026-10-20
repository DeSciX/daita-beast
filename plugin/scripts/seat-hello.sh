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
# Rejoin (rejoin, below): when this session (input "session_id") was seated on this machine and no session has claimed
# the seat since, the hook runs join.sh for it and the context carries the join output. The record is the session claim
# in ~/.beast/sessions.json (sessions_claim, lib.sh; written by join.sh and seats.sh record):
#   held      this session's id is the seat's current claim (a resume or a compaction keeps the id): rejoin.
#   taken     this session's id is in the seat's previous claims: another session on this machine claimed it since;
#             no rejoin, the context names that session and when, and the seats a session here can take.
#   restart   (source startup or clear: a new id) the seat whose current claim was made from this launch folder by a
#             session that has ENDED (the SessionEnd hook, seat-bye.sh, wrote ended_at): rejoin. A claim from this
#             folder whose session recorded no end may be a session still open (no liveness is readable without it;
#             an idle open session writes nothing to its transcript): no rejoin, the context gives the exact join line,
#             why, and when that session's transcript was last written. Several ended claims here: the join lines, no rejoin.
#   interim   before any rejoin, the seat's BEAST-ADDRESS comment on the tracking issue the claim recorded is read (one
#             gh call): one newer than the claim (session_at, or the address recorded_at) was recorded by another
#             session, on this machine or another, so no rejoin; the context names its address, machine and time.
#             A seat no longer rostered here, or retired, is never rejoined. With no claim for this session or folder
#             nothing is read and the context is as without a claim.
# A hook never fails the session: a fault is put into the context, named, and the hook exits 0; every fault is also one
# line in ~/.beast/hooks.log (lib.sh hook_log), which the machine watchdog reads. The watchdog's own session
# (BEAST_WATCHDOG=1) is not a seat: the hook says nothing there and never rejoins.
set -u
[[ "${BEAST_WATCHDOG:-}" != 1 ]] || exit 0
input="$(cat)"
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"

# scripts_line: "scripts: <plugin>/scripts", or the install hint (plugin_root's die message). Needs lib.sh.
scripts_line() { local l; if l="$(plugin_root 2>&1)"; then echo "scripts: $l/scripts"; else echo "${l#daita-beast: }"; fi; }

# rejoin: prints nothing (no claim), or a first line "joined" or "declined <short id or ->" and then the context.
rejoin() {
  source "$scripts/lib.sh"
  local f launch e id how="" row ret tracking at seen a short out rc label handoff=""
  [[ -n "$sid" ]] || return 0
  f="$(sessions_path)"; [[ -s "$f" ]] || return 0
  launch="$(pwd -P)"
  id="$(jq -r --arg s "$sid" '[to_entries[] | select(.value.session == $s)] | sort_by(.value.session_at) | last | .key // empty' "$f")"
  if [[ -n "$id" ]]; then how="this session ($sid, source $src)"
  else
    a="$(jq -r --arg s "$sid" '[to_entries[] | select((.value.previous // []) | map(.session) | index($s))] | sort_by(.value.session_at) | last // empty
      | "\(.key)\t\(.value.session)\t\(.value.session_at)\t\(.value.launch // "an unrecorded folder")"' "$f")"
    if [[ -n "$a" ]]; then
      IFS=$'\t' read -r id e at seen <<< "$a"
      printf 'declined %s\nNot rejoined: this session (%s) held the Beast seat %s, and session %s claimed it since, at %s, launched in %s. To take it back anyway: %s/join.sh %s.\n' "$(seat_short "$id")" "$sid" "$id" "$e" "$at" "$seen" "$scripts" "$id"
      return 0
    fi
    [[ "$src" == startup || "$src" == clear ]] || return 0
    local ended open
    ended="$(jq -r --arg l "$launch" --arg s "$sid" 'to_entries[] | select(.value.launch == $l and .value.session != $s and .value.ended_at != null) | .key' "$f")"
    open="$(jq -r --arg l "$launch" --arg s "$sid" 'to_entries[] | select(.value.launch == $l and .value.session != $s and .value.session != null and .value.ended_at == null) | "\(.key)\t\(.value.session)"' "$f")"
    if [[ -z "$ended" && -z "$open" ]]; then return 0; fi
    if [[ -n "$ended" && "$ended" == *$'\n'* ]]; then
      printf 'declined -\nNot rejoined: several Beast seats were last held from this folder by sessions that have ended: %s. Which one this session is cannot be told; when the person names one, run its line:%s\n' "$(paste -sd ' ' - <<< "$ended")" "$(while IFS= read -r e; do printf ' %s/join.sh %s;' "$scripts" "$e"; done <<< "$ended")"
      return 0
    fi
    if [[ -z "$ended" ]]; then
      out=""
      while IFS=$'\t' read -r e a; do
        local tp t="no transcript found"
        tp="$(claude_project_dir "$launch")/$a.jsonl"
        [[ ! -f "$tp" ]] || t="its transcript last written $(jq -rn --argjson t "$(stat -c %Y "$tp" 2>/dev/null || stat -f %m "$tp")" '$t | todate')"
        out+=" $e (session $a, $t): $scripts/join.sh $e;"
      done <<< "$open"
      e="-"; [[ "$open" == *$'\n'* ]] || e="$(seat_short "${open%%$'\t'*}")"
      printf 'declined %s\nNot rejoined automatically: the Beast seat last held from this folder is held by a session that recorded no end (the SessionEnd hook did not run: it may still be open, or it was killed), so taking it could seat two sessions at once.%s. If that session is closed and this one should hold the seat, run the line.\n' "$e" "${out%;}"
      return 0
    fi
    id="$ended"; how="session $(jq -r --arg k "$id" '.[$k].session' "$f"), launched in this folder and ended at $(jq -r --arg k "$id" '.[$k].ended_at' "$f"),"
  fi
  e="$(jq -c --arg k "$id" '.[$k]' "$f")"
  short="$(seat_short "$id")"; label="$(seat_label "$short")"
  row="$(seat_homes_on_machine "$launch" 2>/dev/null | awk -F'\t' -v s="$short" -v w="${id%%/*}" '$1 == s && $5 == w' | head -1)"
  if [[ -z "$row" ]]; then printf 'declined %s\nNot rejoined: %s held the Beast seat %s, which no roster on this machine names any more.\n' "$short" "$how" "$id"; return 0; fi
  ret="$(cut -f6 <<< "$row")"
  if [[ -n "$ret" ]]; then printf 'declined %s\nNot rejoined: %s held the Beast seat %s, which was retired %s.\n' "$short" "$how" "$id" "$ret"; return 0; fi
  tracking="$(jq -r '.tracking // empty' <<< "$e")"
  if [[ -z "$tracking" ]] && ! tracking="$(workstream_issue "${id%%/*}" 2>&1)"; then
    printf 'declined %s\nNot rejoined: %s held the Beast seat %s, but its tracking issue cannot be found to check that no other session claimed it since (%s). Rejoin by hand: %s/join.sh %s.\n' "$short" "$how" "$id" "$tracking" "$scripts" "$id"; return 0
  fi
  if ! a="$(seat_addresses_at "$tracking" 2>&1)"; then
    printf 'declined %s\nNot rejoined: %s held the Beast seat %s, but its address on %s cannot be read to check that no other session claimed it since (%s). Rejoin by hand: %s/join.sh %s.\n' "$short" "$how" "$id" "$tracking" "$(tr '\n' ' ' <<< "$a")" "$scripts" "$id"; return 0
  fi
  a="$(jq -c --arg s "$id" 'select(.seat? == $s)' <<< "$a" 2>/dev/null | tail -1)"
  at="$(jq -r '[.session_at, .recorded_at] | map(select(. != null)) | max // ""' <<< "$e")"
  if [[ -n "$a" && "$(jq -r .at <<< "$a")" > "$at" ]]; then
    printf 'declined %s\nNot rejoined: %s held the Beast seat %s (claimed %s), but another session claimed it since: its address %s was recorded on %s as %s at %s (%s). To take it back anyway: %s/join.sh %s.\n' "$short" "$how" "$id" "$at" "$(jq -r .address <<< "$a")" "$(jq -r .machine <<< "$a")" "$(jq -r .account <<< "$a")" "$(jq -r .at <<< "$a")" "$(jq -r .url <<< "$a")" "$scripts" "$id"
    return 0
  fi
  [[ "$src" != compact ]] || handoff="This session was just compacted: post the handoff on $tracking now, from the summary: $scripts/status.sh $tracking --seat $label --state handoff --next \"<next act>\" --text \"<state, waiting on, branches, gotchas>\". "
  rc=0; out="$(CLAUDE_CODE_SESSION_ID="$sid" "$scripts/join.sh" "$id" 2>&1)" || rc=$?
  if [[ $rc -ne 0 ]]; then
    printf 'declined %s\nThe automatic rejoin of the Beast seat %s failed (join.sh exit %s): %s Fix what it names, then run %s/join.sh %s.\n' "$short" "$id" "$rc" "$(tail -3 <<< "$out" | tr '\n' ' ')" "$scripts" "$id"
    return 0
  fi
  printf 'joined\n%s. %sThis session is the Beast seat %s again: %s held it and no session has claimed it since, so the SessionStart hook ran %s/join.sh %s. Its output follows; work from it (the home, the handoff, the inbox, and the CLAUDE.md it says to read). The hook cannot know this session'"'"'s ListAgents address: refresh it now with ListAgents, then %s/seats.sh record %s "<ListAgents name [ref]>".\n%s\n' \
    "$(scripts_line)" "$handoff" "$id" "$how" "$scripts" "$id" "$scripts" "$id" "$out"
}

# hello: the context line, or nothing. Runs in a subshell that sources lib.sh, whose die exits that subshell.
hello() {
  source "$scripts/lib.sh"
  local root="" roster here jid="" sret="" homeid="" homectx="" homeact="" compacted="" home tracking label login scope where_ list="" id c h k ws ret identity agent a age addr sline coord=""
  here="$(pwd -P)"
  # The scripts path, printed at every session start in a coordinated repo (the CLAUDE.md block says so): plugin_root
  # is $CLAUDE_PLUGIN_ROOT, else the root ~/.beast/plugin.json records, else the install hint (its die message).
  sline="$(scripts_line)"
  if root="$(repo_root 2>/dev/null)"; then
    roster="$(roster_path)"
    [[ ! -f "$roster" ]] || coord=1
    jid="$(seat_json_id "$PWD")"
    [[ ! -f "$roster" || -z "$jid" ]] || sret="$(roster_field "$jid" retired)"
    if [[ -f "$roster" && -n "$jid" && -z "$sret" && "$jid" != "$declined" && $'\n'"$(roster_seat_ids "$roster")"$'\n' == *$'\n'"$jid"$'\n'* ]] \
       && home="$(seat_home_path "$jid" 2>/dev/null)" && [[ "$(cd "$home" 2>/dev/null && pwd -P)" == "$here" ]]; then
      homeid="$jid"; label="$(seat_label "$jid")"
      ws="$(roster_field "$jid" workstream)"; agent="$(roster_field "$jid" agent)"
      identity="$(seat_identity_of "$jid" "$ws")"
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
    [[ -n "$id" && "$id" != "$homeid" && "$id" != "$declined" && "$(seat_login "$id")" == "$login" && -z "$ret" ]] || continue
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
  if [[ -n "$sret" ]]; then why_not=" (its .beast/seat.json names $jid, retired $sret)"
  elif [[ -n "$jid" && "$jid" == "$declined" ]]; then why_not=" for this session (its .beast/seat.json names $jid, not rejoined as said above)"
  elif [[ -n "$jid" ]]; then why_not=" (its .beast/seat.json names $jid, whose home is elsewhere)"; fi
  [[ "$src" != compact ]] || echo "This session was just compacted: if it holds a seat, post that seat's handoff now from the summary ($scripts/status.sh <tracking> --seat <LABEL> --state handoff --next \"<next act>\" --text \"<state, waiting on, branches, gotchas>\"), then rerun its join.sh and reread <home>/CLAUDE.md."
  echo "$sline. This session runs in $PWD, which is not the home of a Beast seat${why_not}. The seats of $login $where_:${list%;}. This session holds no seat until the person names one; then $how"
}

err="$(mktemp)"
declined=""; pre=""
rj="$( (rejoin) 2>"$err" )" || true
if [[ -s "$err" && -z "$rj" ]]; then pre="The Beast SessionStart hook could not decide whether to rejoin this session's seat: $(tr '\n' ' ' < "$err"). Tell the user. "; fi
: > "$err"
case "${rj%%$'\n'*}" in
  joined) ctx="${rj#*$'\n'}" ;;
  declined*)
    declined="$(sed -n '1s/^declined //p' <<< "$rj")"; [[ "$declined" != - ]] || declined=""
    pre="${rj#*$'\n'} "
    ctx="$( (hello) 2>"$err" )" || true ;;
  *) ctx="$( (hello) 2>"$err" )" || true ;;
esac
if [[ -s "$err" && -z "$ctx" ]]; then
  ctx="The Beast SessionStart hook could not name this directory's seat or home: $(tr '\n' ' ' < "$err"). Tell the user."
fi
rm -f "$err"
# Each fault the context names is also logged, one line (the rejoin's failure, the two "could not" faults).
for m in "$pre" "$ctx"; do
  case "$m" in
    *"could not decide whether to rejoin"*|*"could not name this directory's seat"*|*"The automatic rejoin of the Beast seat"*" failed"*)
      ( source "$scripts/lib.sh"; hook_log seat-hello fault "${sid:--}" "$m" ) 2>/dev/null || true ;;
  esac
done
ctx="$pre$ctx"
[[ -n "$ctx" ]] || exit 0
jq -n --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
