#!/usr/bin/env bash
# watch.sh — one GitHub search, then one diff per seat: emit one line per change to a row that waits on
# a seat (its seat:<login>/<LABEL> label; seat_label_terms owns which labels count). A row is a decision
# issue, a PR labelled needs-review, or the seat's desk (RELAY_ROW_LABELS in lib.sh): a new ask answer or
# message on a desk is an UPDATED for its seat.
#   watch.sh --roster [--once] [--interval 120]           every seat of every open workstream among this repo's roster owners (ws_seats_all)
#   watch.sh <LABEL | login/LABEL>... [--once] [--interval 120]   named seats only
# Event lines (stdout):
#   BEAST-EVENT kind=NEW seat=<id> state=<open|closed> <title> <url>            a decision concerning the seat appeared
#   BEAST-EVENT kind=DECIDED seat=<id> close=<closed|rejected|latitude|none> <title> <url> :: <first line of the close comment>
#                                                                                the word came (close: the close comment's kind,
#                                                                                close_of, lib.sh; latitude: merged under a
#                                                                                standing latitude, its record linked in the line)
#   BEAST-EVENT kind=UPDATED seat=<id> <title> <url>                             a new comment that is not bookkeeping (lib.sh BOOKKEEPING_FIRST_LINE_RE: acks, status, notes, addresses, the Cowork stamp, close and amend lines; label, body and comment edits are silent)
#   BEAST-WATCH <message>   (stderr)                                            the watcher itself (API failure, retried)
# A seat never hears its own act: an event whose every actor is the seat itself (event_actors, lib.sh: the filer's ack,
# the closer, the tagged writer of each new comment; an untagged comment is the decider's) is logged on stderr as
# "own act, not sent" and emits nothing. A comment that cannot be read leaves the event unfiltered (named on stderr).
# One REST search per poll whatever the seat count, from a high-water mark: each seat keeps its snapshot
# (~/.beast/watch/<login>/<LABEL>.json) and the start time of its last good poll (<LABEL>.mark, with the query
# it ran), so a poll asks only for rows updated since the oldest seat's mark minus WATCH_OVERLAP_S, and a restart
# resumes from the marks. The search index lags a write by seconds to minutes (measured 2026-10-15: 10 s for one
# comment; a decision issue created at 23:29:42Z was still absent from an updated:>= search at 23:35:48Z), so the
# overlap is an hour: a row returned again unchanged costs nothing and fires nothing (the diff is local). A seat with no snapshot or mark, or a mark
# made by another query (the roster's owners or the row labels changed), makes that poll a full one: every open
# row plus the closed ones updated in the last two days; a seat with no snapshot baselines silently. Meant to be
# run --once from a scheduler (relay.sh); the loop form exists for a terminal.
# A rate limit (the search quota, the secondary burst limit: lib.sh rate_limit_text) is named once, loud, with the
# backoff it starts (~/.beast/watch/backoff: "<until epoch> <seconds> <UTC named>"; WATCH_BACKOFF_S doubling to
# WATCH_BACKOFF_MAX_S); until then every poll asks GitHub nothing and exits 75 (relay.sh logs it as a skipped poll),
# and the next good search clears it. A workstream whose `## Seats` table does not parse is skipped and named once per
# distinct message (lib.sh fault_once, ledger ~/.beast/watch/faults.json); every other workstream is still polled.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

export BEAST_FAULT_LEDGER="${BEAST_FAULT_LEDGER:-$HOME/.beast/watch/faults.json}"
WATCH_BACKOFF_S=120; WATCH_BACKOFF_MAX_S=1800
backoff_file="$HOME/.beast/watch/backoff"
mkdir -p "$HOME/.beast/watch"

# backoff_active: status 0, silently, while a rate-limit backoff runs (backoff_start named it); a corrupt file is named and removed.
backoff_active() {
  local until secs
  [[ -f "$backoff_file" ]] || return 1
  read -r until secs _ < "$backoff_file" || true
  if ! [[ "$until" =~ ^[0-9]+$ && "$secs" =~ ^[0-9]+$ ]]; then echo "BEAST-WATCH the backoff file $backoff_file is corrupt ('$(cat "$backoff_file")'); removed" >&2; rm -f "$backoff_file"; return 1; fi
  [[ "$(date -u +%s)" -lt "$until" ]]
}
# backoff_start <stderr file>: a rate limit was hit: name it once, loud, and back off (doubling while it repeats).
backoff_start() {
  local secs=$WATCH_BACKOFF_S prev until
  if [[ -f "$backoff_file" ]]; then read -r _ prev _ < "$backoff_file" || true; [[ ! "$prev" =~ ^[0-9]+$ ]] || secs=$(( prev * 2 )); fi
  (( secs <= WATCH_BACKOFF_MAX_S )) || secs=$WATCH_BACKOFF_MAX_S
  until=$(( $(date -u +%s) + secs ))
  printf '%s %s %s\n' "$until" "$secs" "$(utc_now)" > "$backoff_file"
  echo "BEAST-WATCH GitHub rate limit at $(utc_now): $(grep -m1 -iE 'rate limit|quota|HTTP 429' "$1" | sed 's/^daita-beast: //'); backing off ${secs} s, until $(jq -rn --argjson t "$until" '$t | todate'); no search runs until then" >&2
}
# backoff_clear: a search answered; the backoff is over.
backoff_clear() { [[ ! -f "$backoff_file" ]] || { rm -f "$backoff_file"; echo "BEAST-WATCH searches answer again at $(utc_now); backoff cleared" >&2; }; }

seats=(); interval=120; once=0; roster=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --roster) roster=1; shift ;;
    --interval) interval="$2"; shift 2 ;;
    --once) once=1; shift ;;
    -*) die "unknown argument $1" ;;
    *) s="$(seat_rostered "$1")" || exit 1; seats+=("$s"); shift ;;
  esac
done
[[ $roster -eq 1 || ${#seats[@]} -gt 0 ]] || die "usage: watch.sh --roster | <LABEL | login/LABEL>... [--once] [--interval N]"
[[ "$interval" -ge 30 ]] || die "interval must be 30 s or more"
if [[ $roster -eq 1 ]]; then
  ! backoff_active || exit 75
  errf="$(mktemp)"
  if ! ids="$(ws_seats_all 2>"$errf" | cut -f2)"; then
    if rate_limit_text "$(cat "$errf")"; then backoff_start "$errf"; rm -f "$errf"; exit 75; fi
    cat "$errf" >&2; rm -f "$errf"
    die "watch.sh --roster: cannot enumerate the seats of the open workstreams (named above)"
  fi
  cat "$errf" >&2; rm -f "$errf"
  while IFS= read -r s; do [[ -n "$s" ]] && seats+=("$s"); done <<< "$ids"
  if [[ ${#seats[@]} -eq 0 ]]; then echo "BEAST-WATCH no seat in any open workstream among $(workstream_user_terms) at $(utc_now); nothing to poll" >&2; exit 0; fi
fi
mkdir -p "$HOME/.beast"
# The label names each seat's rows carry, resolved once (seat_label_terms is the one owner of which count).
names=()
for seat in "${seats[@]}"; do t="$(seat_label_terms "$seat")" || exit 1; names+=("$(jq -R . <<< "$t" | jq -sc .)"); done

# The owners whose repos hold this roster's decisions: the roster repo, the board repo and every
# seat's repo (their owner part). The roster is the one place that knows; no owner list is typed here.
scope="$(roster_user_terms)"
WATCH_OVERLAP_S=3600
# The query every mark is made by: a mark from another query (other owners, other labels) is not resumed from.
query_id="$(beast_sha "label:$RELAY_ROW_LABELS $scope")"

# write_atomic <file> <content>: several watchers (the relay, a terminal) may write one seat's files.
write_atomic() { local t; t="$(mktemp "$1.XXXXXX")"; printf '%s\n' "$2" > "$t" && mv -f "$t" "$1"; }

# watch_search <var> "<query>" "<what>": search_issues into <var>. A rate limit starts the backoff (status 75); any other
# failure is named and the poll ends (status 1; the next poll retries); a success clears a backoff.
watch_search() {
  local e got; e="$(mktemp)"
  if got="$(search_issues "$2" 2>"$e")"; then cat "$e" >&2; rm -f "$e"; backoff_clear; printf -v "$1" '%s' "$got"; return 0; fi
  if rate_limit_text "$(cat "$e")"; then backoff_start "$e"; rm -f "$e"; return 75; fi
  cat "$e" >&2; rm -f "$e"
  echo "BEAST-WATCH GitHub search ($3) failed at $(utc_now); retrying next poll" >&2; return 1
}

poll() {
  # Scoped to the roster's owners: a `decision` label exists in strangers' repos too, and an unscoped search
  # competes with all of GitHub for the result window. Newest-updated first.
  local started since="" full=0 open_ closed_ all seat snap markf m q mark_q mark_at
  started="$(utc_now)"
  for seat in "${seats[@]}"; do
    snap="$HOME/.beast/watch/$seat.json"; markf="$HOME/.beast/watch/$seat.mark"
    if [[ ! -f "$snap" || ! -f "$markf" ]]; then full=1; continue; fi
    read -r mark_q mark_at < "$markf" || die "the mark $markf is unreadable"
    [[ "$mark_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && -n "$mark_q" ]] || die "the mark $markf is corrupt (expected '<query id> <UTC>', got '$mark_q $mark_at'); delete it to make the next poll a full one"
    if [[ "$mark_q" != "$query_id" ]]; then full=1; continue; fi
    [[ -n "$since" && ! "$mark_at" < "$since" ]] || since="$mark_at"
  done
  if [[ $full -eq 1 ]]; then
    # The bounded first window: every OPEN row, plus every CLOSED one updated in the last two days (a close
    # older than that is caught up by `decision.sh inbox`).
    m="$(date -u -v-2d +%Y-%m-%d 2>/dev/null || date -u -d '2 days ago' +%Y-%m-%d)"
    watch_search open_ "label:$RELAY_ROW_LABELS is:open $scope" "open" || return $?
    watch_search closed_ "label:$RELAY_ROW_LABELS is:closed updated:>=$m $scope" "closed" || return $?
    echo "BEAST-WATCH full poll (a seat has no snapshot or mark of this query) at $started" >&2
  else
    since="$(jq -rn --arg m "$since" --argjson o "$WATCH_OVERLAP_S" '$m | fromdateiso8601 - $o | todateiso8601')"
    watch_search open_ "label:$RELAY_ROW_LABELS updated:>=$since $scope" "since $since" || return $?
    closed_='[]'
    echo "BEAST-WATCH poll since $since ($(jq length <<< "$open_") row(s) updated) at $started" >&2
  fi
  # REST fields mapped once here, so the snapshot files keep their shape and the diff below is unchanged.
  all="$(jq -s 'add | unique_by(.html_url) | map({url: .html_url, title, state, updatedAt: .updated_at, comments, labels})' <(echo "$open_") <(echo "$closed_"))"
  local cur prev i
  for i in "${!seats[@]}"; do
    seat="${seats[$i]}"
    snap="$HOME/.beast/watch/$seat.json"; markf="$HOME/.beast/watch/$seat.mark"; mkdir -p "$(dirname "$snap")"
    cur="$(jq --argjson l "${names[$i]}" '[.[] | select(.labels | any(.name as $n | $l | index($n)))] | map({key:.url, value:{title,state,updatedAt,comments,desk:(.labels | any(.name == "desk"))}}) | from_entries' <<< "$all")"
    if [[ ! -f "$snap" ]]; then
      write_atomic "$snap" "$cur"
      write_atomic "$markf" "$query_id $started"
      echo "BEAST-WATCH seat=$seat baseline $(jq 'length' <<< "$cur") decision(s) at $(utc_now); events start now" >&2
      continue
    fi
    prev="$(cat "$snap")"
    jq -r --argjson p "$prev" 'to_entries[] | . as $e | (($e.value.comments // 0) - ($p[$e.key].comments // 0)) as $d |
        if ($p[$e.key] == null) then (if $e.value.state == "open" then "NEW\t\($e.value.state)\t\($e.value.title)\t\($e.key)\t0\t\($e.value.desk // false)" else empty end)
        elif ($p[$e.key].state == "open" and $e.value.state == "closed") then "DECIDED\t\($e.value.state)\t\($e.value.title)\t\($e.key)\t\([$d, 0] | max)\t\($e.value.desk // false)"
        elif $d > 0 then "UPDATED\t\($e.value.state)\t\($e.value.title)\t\($e.key)\t\($d)\t\($e.value.desk // false)"
        else empty end' <<< "$cur" | while IFS=$'\t' read -r kind state title url delta desk; do
      [[ -n "$kind" ]] || continue
      read -r repo number < <(parse_issue_ref "$url")
      # Who acted (event_actors, lib.sh): an UPDATED with no news is no event, and an event whose every actor is this
      # seat is its own act, never sent back to it. Unreadable comments leave the event unfiltered, named here.
      if cs="$(issue_comments "$repo" "$number")"; then
        actors="$(event_actors "$kind" "${delta:-0}" "$cs" "$([[ "$desk" == true ]] && echo "$seat")")" \
          || { echo "BEAST-WATCH seat=$seat cannot read the actors of $kind $url (named above); sent unfiltered" >&2; actors="-"; }
        [[ -n "$actors" ]] || continue
        if ! grep -qvxF -- "$seat" <<< "$actors"; then echo "BEAST-WATCH seat=$seat own act, not sent: $kind $url" >&2; continue; fi
      else
        echo "BEAST-WATCH seat=$seat cannot read the comments of $url at $(utc_now); $kind sent unfiltered" >&2; cs=""
      fi
      case "$kind" in
        DECIDED)
          ck=none
          if [[ -z "$cs" ]]; then word="(close comment unreadable)"
          else
            word="$(jq -r 'if length == 0 then "(no comment on the row)" else (.[-1].body // "" | split("\n")[0]) end' <<< "$cs")" || word="(close comment unreadable)"
            ck="$(close_of_comments "$cs" | jq -r '.kind // "none"')" || ck=none
          fi
          echo "BEAST-EVENT kind=DECIDED seat=$seat close=$ck $title $url :: $word" ;;
        NEW) echo "BEAST-EVENT kind=NEW seat=$seat state=$state $title $url" ;;
        UPDATED) echo "BEAST-EVENT kind=UPDATED seat=$seat $title $url" ;;
      esac
    done
    # Never forget an issue the search did not return this time (index lag, window): keep the old
    # entry, let the current result override, drop entries closed more than seven days ago.
    write_atomic "$snap" "$(jq -n --argjson p "$prev" --argjson c "$cur" --arg cut "$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
       '($p + $c) | with_entries(select(.value.state == "open" or .value.updatedAt >= $cut))')"
    write_atomic "$markf" "$query_id $started"
  done
}

while true; do
  # 75: a rate limit backs off (named once by backoff_start); any other failed search was named and the next poll retries.
  if backoff_active; then rc=75; else rc=0; poll || rc=$?; [[ $rc -eq 75 ]] || rc=0; fi
  [[ $once -eq 1 ]] && exit $rc
  sleep "$interval"
  run_cache_clear   # a new poll asks GitHub again: the run's memoized searches are the last poll's
done
