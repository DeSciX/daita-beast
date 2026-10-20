#!/usr/bin/env bash
# seats.sh — the seat map and the seats' addresses. A seat is named by its LABEL (resolved through the roster, then
# every workstream's `## Seats` table), its short id <login>/<LABEL>, or its identity <slug>/<LABEL>/<login>.
#   record <seat> "<name [ref]>"   write this session's SendMessage address: the seat's one BEAST-ADDRESS comment on its
#                                  workstream tracking issue (created, then edited in place; the one owner), the
#                                  machine-local cache ~/.beast/sessions.json (keyed by the identity) with this
#                                  session's claim of the seat (sessions_claim), and the rendered Account/Address/Seen
#                                  cells of the issue's `## Seats` table
#   list                           every seat of every open workstream among the workstream owners (the roster's owners plus its "workstream_owners") (ws_seats_all), with
#                                  its account, address and when it was seen (from the BEAST-ADDRESS comments)
#   address <seat>                 the seat's address, read live: line 1 the address alone; then its account, machine,
#                                  age, and which path applies: direct (SendMessage: same Claude account, same machine,
#                                  recorded within 24h, an approximation of "after its newest session start") or desk
#                                  (desk.sh msg). Exit 1 when none is recorded.
#   forget <seat>                  delete a stale address: the comment and the cache entry
# BEAST-ADDRESS seat=<identity> account=<claude account> address="<name [ref]>" machine=<hostname> at=<UTC>
# (address_header, seat_address_read in lib.sh). Addresses change on every session reload: a seat records at every
# join; a reader verifies one by a reply before relying on it.
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

case "$cmd" in
  record)
    seat="${1:-}"; addr="${2:-}"
    [[ -n "$seat" && -n "$addr" ]] || die "usage: seats.sh record <LABEL | login/LABEL | slug/LABEL/login> \"<name [ref]>\""
    id="$(seat_rostered "$seat")" || die "add the seat to $roster first (seat.sh new)"
    identity="$(seat_identity "$id")" || exit 1
    [[ "$addr" =~ ^([^][$'\n']+)\ \[([0-9a-f]{6})\]$ ]] || die "address '$addr' is not of the shape 'name [ref]' as ListAgents prints it (the name may carry spaces and slashes; the ref is 6 hex digits)"
    name="${BASH_REMATCH[1]}"; ref="${BASH_REMATCH[2]}"
    slug="${identity%%/*}"
    tracking="$(workstream_issue "$slug")" || exit 1
    repo="${tracking%%#*}"; number="${tracking#*#}"
    coord_write_guard "$repo" "$id"
    account="$(claude_account)" || exit 1
    machine="$(hostname -s 2>/dev/null || hostname)"
    [[ "$machine" =~ ^[^[:space:]]+$ ]] || die "the hostname '$machine' carries whitespace; the address line cannot hold it"
    at="$(utc_now)"
    have="$(seat_address_read "$identity")" || exit 1
    body="$(address_header "$identity" "$account" "$addr" "$machine" "$at")" || exit 1
    f="$(mktemp)"; printf '%s\n' "$body" > "$f"
    if [[ -n "$have" ]]; then url="$(comment_edit "$repo" "$(jq -r .id <<< "$have")" "$f")"; what="edited"
    else url="$(gh_send POST "repos/$repo/issues/$number/comments" -F body=@"$f" | jq -r .html_url)"; what="created"; fi
    rm -f "$f"
    sessions_key_check "$identity"
    sessions_update '.[$l] = ((.[$l] // {}) + {name:$n, ref:$r, address:$a, account:$acc, machine:$m, cwd:$c, recorded_at:$t})' \
      --arg l "$identity" --arg n "$name" --arg r "$ref" --arg a "$addr" --arg acc "$account" --arg m "$machine" --arg c "$(pwd)" --arg t "$at"
    echo "recorded $identity -> $addr (account $account, machine $machine): $what $url; cached in $sessions"
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
  *) die "usage: seats.sh record|list|address|forget" ;;
esac
