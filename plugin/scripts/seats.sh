#!/usr/bin/env bash
# seats.sh — the seat map and the seats' addresses. A seat is named by its LABEL (resolved through the roster, then
# every workstream's `## Seats` table), its short id <login>/<LABEL>, or its identity <slug>/<LABEL>/<login>.
#   record <seat> ["<address>"]    write this session's SendMessage address: the seat's one BEAST-ADDRESS comment on its
#                                  workstream tracking issue (created, then edited in place; the one owner), the
#                                  machine-local cache ~/.beast/sessions.json (keyed by the identity) with this
#                                  session's claim of the seat (sessions_claim), and the rendered Account/Address/Seen
#                                  cells of the issue's `## Seats` table. With no address it is this session's name,
#                                  read from its Claude Code session file (claude_session_of $CLAUDE_CODE_SESSION_ID,
#                                  lib.sh); dies naming the failure when that file cannot be read. A name that two live
#                                  sessions carry is recorded and printed as ambiguous.
#   list                           every seat of every open workstream among the workstream owners (the roster's owners plus its "workstream_owners") (ws_seats_all), with
#                                  its account, address and when it was seen (from the BEAST-ADDRESS comments)
#   address <seat>                 the seat's address, read live: line 1 the address alone; then its account, machine,
#                                  age, and which path applies: direct (SendMessage: same Claude account, same machine,
#                                  recorded within 24h, an approximation of "after its newest session start") or desk
#                                  (desk.sh msg). Exit 1 when none is recorded.
#   forget <seat>                  delete a stale address: the comment and the cache entry
#   touch <identity>               re-stamp the seat's BEAST-ADDRESS comment with the live name of the session that
#                                  holds the seat's claim, and at=now: the machine watchdog's one write to a seat's fact.
#                                  Refused unless the claim (~/.beast/sessions.json, session) names a session whose
#                                  Claude Code session file is live (claude_session_of, kill -0), whose cwd is the
#                                  seat's home or the claim's launch folder, and the comment was recorded on this
#                                  machine. A recorded "name [ref]" whose name is the live name keeps its ref. It
#                                  updates the cached address, re-renders the `## Seats` table when the address
#                                  changed, and claims no session (no sessions_claim).
# BEAST-ADDRESS seat=<identity> account=<claude account> address="<name>[ [ref]]" machine=<hostname> at=<UTC>
# (address_header, ADDRESS_RE, seat_address_read in lib.sh). A session's name changes when it restarts: join records it,
# the SessionStart hook records it on every rejoin, and the watchdog re-stamps it from the live session file.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need jq git gh

cmd="${1:-}"; shift || true
roster="$(roster_path)"
roster_check_unique "$roster"
sessions="$(sessions_path)"
mkdir -p "$(dirname "$sessions")"
[[ -f "$sessions" ]] || echo '{}' > "$sessions"

# The cache is keyed by the identity. A key of an older shape (a bare LABEL, or login/LABEL) is dropped, named: the
# comment on the tracking issue is the owner, and the next record rewrites the cache.
while IFS= read -r k; do
  [[ -n "$k" ]] || continue
  sessions_update 'del(.[$k])' --arg k "$k"
  echo "daita-beast: $sessions: dropped the key $k (not <slug>/<LABEL>/<login>; the BEAST-ADDRESS comment is the owner, seats.sh record rewrites the cache)" >&2
done < <(jq -r --arg re "$SEAT_IDENTITY_RE" 'keys[] | select(test($re) | not)' "$sessions")

# address_put <identity> <tracking> <have json | ""> <account> <address> <cwd | "">: the one writer of a seat's address
# (record and touch): the BEAST-ADDRESS comment (created, or edited in place keeping its lines after the header), and the
# cache entry's address fields (cwd only when given). Prints the line naming what it did and, when the name is carried by
# more than one live session on this machine, the ambiguity warning. Claims nothing.
address_put() {
  local identity="$1" tracking="$2" have="$3" account="$4" addr="$5" cwd="$6" repo number machine at body f url what p name ref nh
  repo="${tracking%%#*}"; number="${tracking#*#}"
  p="$(address_parse "$addr")" || exit 1; name="${p%%$'\t'*}"; ref="${p#*$'\t'}"
  machine="$(hostname -s 2>/dev/null || hostname)"
  [[ "$machine" =~ ^[^[:space:]]+$ ]] || die "the hostname '$machine' carries whitespace; the address line cannot hold it"
  at="$(utc_now)"
  f="$(mktemp)"
  { address_header "$identity" "$account" "$addr" "$machine" "$at" || exit 1
    [[ -z "$have" ]] || issue_comments "$repo" "$number" | jq -r --argjson i "$(jq -r .id <<< "$have")" '.[] | select(.id == $i) | (.body // "") | gsub("\r"; "") | split("\n")[1:] | .[]'; } > "$f" || { rm -f "$f"; exit 1; }
  if [[ -n "$have" ]]; then url="$(comment_edit "$repo" "$(jq -r .id <<< "$have")" "$f")"; what="edited"
  else url="$(gh_send POST "repos/$repo/issues/$number/comments" -F body=@"$f" | jq -r .html_url)"; what="created"; fi
  rm -f "$f"
  sessions_key_check "$identity"
  sessions_update '.[$l] = ((.[$l] // {}) + {name:$n, ref:$r, address:$a, account:$acc, machine:$m, recorded_at:$t} + (if $c != "" then {cwd:$c} else {} end))' \
    --arg l "$identity" --arg n "$name" --arg r "$ref" --arg a "$addr" --arg acc "$account" --arg m "$machine" --arg c "$cwd" --arg t "$at"
  echo "recorded $identity -> $addr (account $account, machine $machine): $what $url; cached in $sessions"
  if nh="$(claude_name_holders "$name" 2>&1)"; then
    [[ "$nh" -le 1 ]] || echo "ambiguous: $nh live sessions on this machine are named \"$name\"; a SendMessage to that name cannot tell them apart (recorded anyway; rename one session, and the next join or watchdog tick records the new name)"
  else echo "ambiguity not checked: ${nh#daita-beast: }"; fi
}

case "$cmd" in
  record)
    seat="${1:-}"; addr="${2:-}"
    [[ -n "$seat" ]] || die "usage: seats.sh record <LABEL | login/LABEL | slug/LABEL/login> [\"<name>\" | \"<name [ref]>\"] (no address: this session's name from its Claude Code session file)"
    id="$(seat_rostered "$seat")" || die "add the seat to $roster first (seat.sh new)"
    identity="$(seat_identity "$id")" || exit 1
    if [[ -z "$addr" ]]; then
      [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]] || die "no address given and CLAUDE_CODE_SESSION_ID is unset (not a Claude Code session): pass the address, the session's ListAgents name"
      live="$(claude_session_of "$CLAUDE_CODE_SESSION_ID")" || exit 1
      [[ "$(jq -r .alive <<< "$live")" == true ]] || die "the Claude Code session file $(jq -r .file <<< "$live") names this session ($CLAUDE_CODE_SESSION_ID), but its pid $(jq -r .pid <<< "$live") is not alive"
      addr="$(jq -r .name <<< "$live")"
    fi
    p="$(address_parse "$addr")" || exit 1
    name="${p%%$'\t'*}"; ref="${p#*$'\t'}"
    slug="${identity%%/*}"
    tracking="$(workstream_issue "$slug")" || exit 1
    repo="${tracking%%#*}"
    coord_write_guard "$repo" "$id"
    account="$(claude_account)" || exit 1
    have="$(seat_address_read "$identity")" || exit 1
    address_put "$identity" "$tracking" "$have" "$account" "$addr" "$(pwd)"
    sessions_claim "$identity" "" "$tracking"
    ws_seats_write "$slug" "$(ws_seats_parse "$slug")" >/dev/null || exit 1
    echo "the \`## Seats\` table of $tracking re-rendered (Account, Address, Seen are rendered from the comments; the comment is the owner)"
    ;;
  list)
    me="$(claude_account 2>/dev/null || echo "")"
    printf '| Seat | Repo | Home | Agent | Account | Address | Seen |\n|---|---|---|---|---|---|---|\n'
    cur=""; addrs=""
    while IFS=$'\t' read -r slug seat repo home agent tracking title; do
      [[ -n "$slug" ]] || continue
      if [[ "$slug" != "$cur" ]]; then cur="$slug"; addrs="$(seat_addresses_of "$slug")" || exit 1; fi
      identity="$(seat_identity_of "$seat" "$slug")"
      a="$(jq -c --arg s "$identity" 'select(.seat == $s)' <<< "$addrs" | head -1)"
      if [[ -n "$a" ]]; then
        acc="$(jq -r .account <<< "$a")"; at="$(jq -r .at <<< "$a")"
        age="$(address_age "$at")"
        printf '| %s | %s | %s | %s | %s | %s | %s |\n' "$identity" "$repo" "$home" "$agent" "$acc$([[ -n "$me" && "$acc" == "$me" ]] && echo " (yours)")" "$(jq -r .address <<< "$a" | cell) on $(jq -r .machine <<< "$a")" "$at (${age%%$'\t'*}, ${age#*$'\t'})"
      else printf '| %s | %s | %s | %s | — | — | — |\n' "$identity" "$repo" "$home" "$agent"; fi
    done < <(ws_seats_all)
    echo
    echo "Addresses are re-minted on every reload: verify one by a reply before relying on it. seats.sh address <SEAT> says whether a direct SendMessage applies or the desk (desk.sh msg)."
    ;;
  address)
    seat="${1:-}"; [[ -n "$seat" ]] || die "usage: seats.sh address <LABEL | login/LABEL | slug/LABEL/login>"
    identity="$(seat_identity "$seat")" || exit 1
    a="$(seat_address_read "$identity")" || exit 1
    [[ -n "$a" ]] || die "no address recorded for $identity (no BEAST-ADDRESS comment on the tracking issue of workstream ${identity%%/*}): that session has not run seats.sh record since its last reload; write to its desk instead (desk.sh msg)"
    me="$(claude_account)" || exit 1
    machine="$(hostname -s 2>/dev/null || hostname)"
    acc="$(jq -r .account <<< "$a")"; m="$(jq -r .machine <<< "$a")"; at="$(jq -r .at <<< "$a")"
    age="$(address_age "$at")"; fresh="${age#*$'\t'}"
    jq -r .address <<< "$a"
    echo "account: $acc ($([[ "$acc" == "$me" ]] && echo "same as yours" || echo "not yours: $me"))"
    echo "machine: $m ($([[ "$m" == "$machine" ]] && echo "this machine" || echo "not this machine: $machine"))"
    echo "recorded: $at (${age%%$'\t'*}, $fresh; fresh = within 24h, an approximation of \"after that seat's newest session start\") $(jq -r .url <<< "$a")"
    why=""
    [[ "$acc" == "$me" ]] || why="another Claude account"
    [[ "$m" == "$machine" ]] || why="${why:+$why, }another machine"
    [[ "$fresh" == fresh ]] || why="${why:+$why, }a stale address"
    if [[ -z "$why" ]]; then echo "path: direct — SendMessage to the address above, first line $(msg_header "<your identity>" "$identity" "<ref|none>" 2>/dev/null || echo "BEAST-MSG from=<your identity> to=$identity re=<ref|none> blocking=no at=<UTC>")"
    else echo "path: desk — $why: desk.sh msg $(seat_short "$identity") --from <SEAT> --text \"…\" [--re <ref>] (the durable copy on its desk; it reads it at its next wake)"; fi
    ;;
  forget)
    seat="${1:-}"; [[ -n "$seat" ]] || die "usage: seats.sh forget <LABEL | login/LABEL | slug/LABEL/login>"
    identity="$(seat_identity "$seat")" || exit 1
    a="$(seat_address_read "$identity")" || exit 1
    if [[ -n "$a" ]]; then
      coord_write_guard "$(jq -r '.url | capture("github.com/(?<r>[^/]+/[^/]+)/") | .r' <<< "$a")"
      comment_delete "$(jq -r '.url | capture("github.com/(?<r>[^/]+/[^/]+)/") | .r' <<< "$a")" "$(jq -r .id <<< "$a")"
      echo "deleted $(jq -r .url <<< "$a")"
    fi
    sessions_update 'del(.[$l])' --arg l "$identity"
    echo "forgot $identity (its address and its session claim on this machine)"
    ;;
  touch)
    identity="${1:-}"
    [[ "${2:-}" != --verified ]] || die "refused: touch --verified is gone: seats.sh touch $identity reads the live name of the seat's claimed session from its Claude Code session file itself"
    [[ "$identity" =~ $SEAT_IDENTITY_RE && $# -eq 1 ]] || die "usage: seats.sh touch <slug>/<LABEL>/<login>"
    entry="$(jq -c --arg k "$identity" '.[$k] // {}' "$sessions")"
    sid="$(jq -r '.session // empty' <<< "$entry")"
    [[ -n "$sid" ]] || die "refused: $sessions holds no session claim for $identity"
    [[ -z "$(jq -r '.ended_at // empty' <<< "$entry")" ]] || die "refused: the claim of $identity by session $sid ended at $(jq -r .ended_at <<< "$entry")"
    live="$(claude_session_of "$sid")" || exit 1
    [[ "$(jq -r .alive <<< "$live")" == true ]] || die "refused: the session $sid claiming $identity is not alive (pid $(jq -r .pid <<< "$live") of $(jq -r .file <<< "$live"))"
    home="$(seat_home_on_machine "$identity")" || exit 1
    [[ -n "$home" ]] || die "refused: no roster on this machine names $identity, so its home cannot be checked"
    lcwd="$(cd "$(jq -r .cwd <<< "$live")" 2>/dev/null && pwd -P)" || lcwd="$(jq -r .cwd <<< "$live")"
    launch="$(jq -r '.launch // empty' <<< "$entry")"
    [[ "$lcwd" == "$(cd "$home" 2>/dev/null && pwd -P)" || ( -n "$launch" && "$lcwd" == "$(cd "$launch" 2>/dev/null && pwd -P)" ) ]] \
      || die "refused: the session $sid claiming $identity runs in $lcwd, which is neither its home $home nor its launch folder ${launch:-(none recorded)}"
    # The claim names the tracking issue it was recorded on (no search); a seat claimed before that field existed is found by its labels.
    tracking="$(jq -r '.tracking // empty' <<< "$entry")"
    [[ -n "$tracking" ]] || tracking="$(workstream_issue "${identity%%/*}")" || exit 1
    a="$(seat_addresses_at "$tracking" | jq -c --arg s "$identity" 'select(.seat == $s)' | jq -sc .)" || exit 1
    [[ "$(jq length <<< "$a")" -eq 1 ]] || die "refused: $identity has $(jq length <<< "$a") BEAST-ADDRESS comments on $tracking; touch re-stamps exactly one"
    a="$(jq -c '.[0]' <<< "$a")"
    machine="$(hostname -s 2>/dev/null || hostname)"
    [[ "$(jq -r .machine <<< "$a")" == "$machine" ]] || die "refused: $identity's address was recorded on $(jq -r .machine <<< "$a"), not this machine ($machine)"
    name="$(jq -r .name <<< "$live")"; old="$(jq -r .address <<< "$a")"
    new="$name"; [[ "$(jq -r .name <<< "$a")" != "$name" ]] || new="$old"
    coord_write_guard "${tracking%%#*}"
    address_put "$identity" "$tracking" "$a" "$(jq -r .account <<< "$a")" "$new" ""
    echo "touched $identity: address \"$old\" -> \"$new\" (the live name of its claimed session $sid), at= $(jq -r .at <<< "$a") -> now; no session claimed"
    if [[ "$new" != "$old" ]]; then
      slug="${identity%%/*}"
      ws_seats_write "$slug" "$(ws_seats_parse "$slug")" >/dev/null || exit 1
      echo "the \`## Seats\` table of $tracking re-rendered"
    fi
    ;;
  *) die "usage: seats.sh record|list|address|forget|touch" ;;
esac
