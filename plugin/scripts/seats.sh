#!/usr/bin/env bash
# seats.sh — the repo-scoped seat map. A seat is named by its LABEL (resolved through the roster) or its id <login>/<LABEL>.
#   record <seat> "<name [ref]>"   write this session's SendMessage address under the seat's id
#   list                           every roster seat of this repo by id, with its label and live address, if any
#   address <seat>                 print the address for SendMessage, or exit 1
#   forget <seat>                  drop a stale address
# The roster (.beast/roster.json, committed) says who may be addressed from this repo.
# Addresses (~/.beast/sessions.json, never committed, keyed by seat id) change on every session reload.
# A key without a login (written before ids) is migrated on read when this roster resolves it; one that
# does not resolve is left as is and named on stderr.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need jq git

cmd="${1:-}"; shift || true
roster="$(roster_path)"
roster_check_unique "$roster"
sessions="$(sessions_path)"
mkdir -p "$(dirname "$sessions")"
[[ -f "$sessions" ]] || echo '{}' > "$sessions"

# Migrate bare keys to ids. When both exist, the newer recorded_at wins.
while IFS= read -r k; do
  [[ -n "$k" ]] || continue
  if id="$(seat_id "$k" 2>/dev/null)"; then
    tmp="$(mktemp)"
    jq --arg k "$k" --arg id "$id" '
      (if .[$id] == null or ((.[$k].recorded_at // "") > (.[$id].recorded_at // "")) then .[$id] = .[$k] else . end) | del(.[$k])' "$sessions" > "$tmp" && mv "$tmp" "$sessions"
    echo "daita-beast: $sessions: migrated key $k -> $id" >&2
  else
    echo "daita-beast: $sessions: key $k is not a seat id and does not resolve to one seat of $roster; left as is" >&2
  fi
done < <(jq -r 'keys[] | select(contains("/") | not)' "$sessions")

case "$cmd" in
  record)
    seat="${1:-}"; addr="${2:-}"
    [[ -n "$seat" && -n "$addr" ]] || die "usage: seats.sh record <LABEL | login/LABEL> \"<name [ref]>\""
    id="$(seat_rostered "$seat")" || die "add the seat to $roster first (a roster is the repo's visibility filter)"
    [[ "$addr" =~ ^([^][$'\n']+)\ \[([0-9a-f]{6})\]$ ]] || die "address '$addr' is not of the shape 'name [ref]' as ListAgents prints it (the name may carry spaces and slashes; the ref is 6 hex digits)"
    name="${BASH_REMATCH[1]}"; ref="${BASH_REMATCH[2]}"
    tmp="$(mktemp)"
    jq --arg l "$id" --arg n "$name" --arg r "$ref" --arg a "$addr" --arg c "$(pwd)" --arg t "$(utc_now)" \
       '.[$l] = {name:$n, ref:$r, address:$a, cwd:$c, recorded_at:$t}' "$sessions" > "$tmp" && mv "$tmp" "$sessions"
    echo "recorded $id -> $addr in $sessions"
    ;;
  list)
    printf '| Seat | Label | Role | Repo | Lane | Address | Recorded |\n|---|---|---|---|---|---|---|\n'
    roster_seat_ids "$roster" | while IFS= read -r id; do
      l="$(seat_label "$id")"
      IFS=$'\t' read -r role repo lane < <(jq -r --arg g "$(seat_login "$id")" --arg l "$l" '.seats[] | select(.github == $g and .label == $l) | [.role, .repo, .lane] | @tsv' "$roster")
      addr=$(jq -r --arg l "$id" '.[$l].address // "unknown"' "$sessions")
      at=$(jq -r --arg l "$id" '.[$l].recorded_at // "-"' "$sessions")
      printf '| %s | %s | %s | %s | %s | %s | %s |\n' "$id" "$l" "$role" "$repo" "$lane" "$addr" "$at"
    done
    echo
    echo "Addresses are re-minted on every reload: verify one by a reply before relying on it."
    ;;
  address)
    seat="${1:-}"; [[ -n "$seat" ]] || die "usage: seats.sh address <LABEL | login/LABEL>"
    id="$(seat_rostered "$seat")" || exit 1
    addr=$(jq -r --arg l "$id" '.[$l].address // empty' "$sessions")
    [[ -n "$addr" ]] || die "no recorded address for $id — that session has not run seats record since its last reload"
    echo "$addr"
    ;;
  forget)
    seat="${1:-}"; [[ -n "$seat" ]] || die "usage: seats.sh forget <LABEL | login/LABEL>"
    id="$(seat_id "$seat")" || exit 1
    tmp="$(mktemp)"; jq --arg l "$id" 'del(.[$l])' "$sessions" > "$tmp" && mv "$tmp" "$sessions"
    echo "forgot $id"
    ;;
  *) die "usage: seats.sh record|list|address|forget" ;;
esac
