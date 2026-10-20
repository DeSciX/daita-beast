#!/usr/bin/env bash
# watch.sh — one GitHub search, then one diff per seat: emit one line per change to a row that waits on
# a seat (its seat:<login>/<LABEL> label; seat_label_terms owns which labels count). A row is a decision
# issue, a PR labelled needs-review, or the seat's desk (RELAY_ROW_LABELS in lib.sh): a new ask answer or
# message on a desk is an UPDATED for its seat.
#   watch.sh --roster [--once] [--interval 120]           every seat of every open workstream among this repo's roster owners (ws_seats_all)
#   watch.sh <LABEL | login/LABEL>... [--once] [--interval 120]   named seats only
# Event lines (stdout):
#   BEAST-EVENT kind=NEW seat=<id> state=<open|closed> <title> <url>            a decision concerning the seat appeared
#   BEAST-EVENT kind=DECIDED seat=<id> <title> <url> :: <first line of the close comment>   the word came
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
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

seats=(); interval=120; once=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --roster) ids="$(ws_seats_all | cut -f2)" || exit 1; while IFS= read -r s; do [[ -n "$s" ]] && seats+=("$s"); done <<< "$ids"; shift ;;
    --interval) interval="$2"; shift 2 ;;
    --once) once=1; shift ;;
    -*) die "unknown argument $1" ;;
    *) s="$(seat_rostered "$1")" || exit 1; seats+=("$s"); shift ;;
  esac
done
[[ ${#seats[@]} -gt 0 ]] || die "usage: watch.sh --roster | <LABEL | login/LABEL>... [--once] [--interval N]"
[[ "$interval" -ge 30 ]] || die "interval must be 30 s or more"
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
    open_="$(search_issues "label:$RELAY_ROW_LABELS is:open $scope")" \
      || { echo "BEAST-WATCH GitHub search (open) failed at $(utc_now); retrying next poll" >&2; return 0; }
    closed_="$(search_issues "label:$RELAY_ROW_LABELS is:closed updated:>=$m $scope")" \
      || { echo "BEAST-WATCH GitHub search (closed) failed at $(utc_now); retrying next poll" >&2; return 0; }
    echo "BEAST-WATCH full poll (a seat has no snapshot or mark of this query) at $started" >&2
  else
    since="$(jq -rn --arg m "$since" --argjson o "$WATCH_OVERLAP_S" '$m | fromdateiso8601 - $o | todateiso8601')"
    open_="$(search_issues "label:$RELAY_ROW_LABELS updated:>=$since $scope")" \
      || { echo "BEAST-WATCH GitHub search (since $since) failed at $(utc_now); retrying next poll" >&2; return 0; }
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
          if [[ -z "$cs" ]]; then word="(close comment unreadable)"
          else word="$(jq -r 'if length == 0 then "(no comment on the row)" else (.[-1].body // "" | split("\n")[0]) end' <<< "$cs")" || word="(close comment unreadable)"; fi
          echo "BEAST-EVENT kind=DECIDED seat=$seat $title $url :: $word" ;;
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
  poll
  [[ $once -eq 1 ]] && exit 0
  sleep "$interval"
  run_cache_clear   # a new poll asks GitHub again: the run's memoized searches are the last poll's
done
