#!/usr/bin/env bash
# desk.sh — a seat's desk: the tier below the board, for questions across the desk and messages.
#   desk.sh open <SEAT>                                           create the desk once (idempotent)
#   desk.sh ask <SEAT> --text "<question>" [--options "a | b | c"] [--default a] [--milestone "<title>"] [--waits-on <seat | owner/repo#N>]...
#       --milestone is required when the desk's repo has an open milestone (milestone_require, lib.sh)
#   desk.sh answer <SEAT> <n> "<text>"     the decider's words typed to the seat's session, posted verbatim
#   desk.sh withdraw <SEAT> <n>            the seat withdraws its own open ask
#   desk.sh msg <TO-SEAT> --from <SEAT> --text "<body>" [--re <owner/repo#N | url>]   a durable message on the recipient's desk
#   desk.sh publish <SEAT>                 regenerate the desk body (every write above publishes)
#   desk.sh inbox <SEAT>                   answers and messages newer than the seat's last ack on its desk
# A desk is ONE issue per seat in the seat's own repo (seat_repo, lib.sh: its roster row here, else the Repo cell of
# its workstream's `## Seats` table): title `Desk: <id>`, labels `desk` and `seat:<id>`, assigned to the decider (the
# roster's people[] owner). A verb acting AS a seat (open, ask, withdraw, publish, inbox, --from) names a seat of this
# roster (seat_rostered); a verb naming ANOTHER seat (msg <TO-SEAT>, answer <SEAT>) resolves it by label, id or
# identity through the workstream tables too (seat_id), and writes on that seat's desk in that seat's repo.
# Its comments are the facts:
#   BEAST-ASK n=<seq> seat=<id> at=<UTC>[ milestone="<title>"]   then the question lines, `options: a | b`,
#                                             `default: a`, `Waits on: <ref>` lines (ask_header, desk_parse in lib.sh)
#   BEAST-ANSWER n=<seq> <text>               by an assignee of the desk, or posted by `answer` (it carries
#                                             the line "(words typed to <id>'s session, verbatim)")
#   BEAST-WITHDRAW n=<seq>                    the seat withdraws an open ask
#   BEAST-MSG from=<composite> to=<composite> re=<ref|none> blocking=no   the seat-to-seat tag (msg_header, lib.sh: the
#                                             same first line a seat sends by SendMessage), then the body; a plain
#                                             comment by an assignee is a message too
#   BEAST-ACK seat=<id> …                     the seat's ack (ack.sh <desk> --seat <id> --state seen)
# The body is a view, regenerated from the comments by publish; nobody edits it. A comment that answers no
# open ask, an ask or message for another seat, and a malformed BEAST- line are named on stderr and dropped.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

# desk_find and desk_parse (the one parser of a desk, and of the ask header) live in lib.sh.

# desk_of <id>: "<repo> <number>" of the seat's open desk, for a write; dies naming `desk.sh open` when there is
# none, and refuses a desk in a public or public-intended repo (coord_write_guard). Every desk write reads it as
# f="$(desk_of …)" || exit 1, so a refusal stops the script before its first write.
desk_of() {
  local f repo n state
  repo="$(seat_repo "$1")" || exit 1
  coord_write_guard "$repo" "$1"
  f="$(desk_find "$1" "$repo")" || exit 1
  [[ -n "$f" ]] || die "seat $1 has no desk: desk.sh open $1"
  read -r repo n state <<< "$f"
  [[ "$state" == open ]] || die "the desk of $1 ($repo#$n) is closed: a desk is never closed; reopen it"
  echo "$repo $n"
}

# publish <id>: regenerate the desk body from its comments; prints the desk URL.
publish() {
  local id="$1" repo n parsed tmp f
  f="$(desk_of "$id")" || exit 1; read -r repo n <<< "$f"
  parsed="$(desk_parse "$id" "$(row_read "$repo" "$n")")" || exit 1
  tmp="$(mktemp)"
  jq -r --arg id "$id" --arg stamp "$(utc_now)" '
    def c: tostring | gsub("\n"; " ") | gsub("\\|"; "\\|");
    def q1: (.question[0] // "(no question text)");
    ([.asks[] | select(.state == "open")]) as $open
    | ([.asks[] | select(.state != "open")] | sort_by(.answer.at) | reverse) as $done
    | (.messages | sort_by(.at) | reverse) as $msgs
    | "Desk of \($id): \($open | length) open ask(s), \($done | length) answered or withdrawn, \($msgs | length) message(s). Generated \($stamp) by daita-beast desk.sh publish from this issue'"'"'s comments; do not edit this body. Answer an ask with a comment `BEAST-ANSWER n=<n> <option or text>`; write to the seat with a plain comment (a seat writes `desk.sh msg \($id) --from <SEAT>`).",
      "",
      "## Open asks",
      "",
      (if ($open | length) == 0 then "(none)" else
        ("| n | Question | Options | Default | Milestone | Waits on | Asked |", "|---|---|---|---|---|---|---|",
         ($open[] | "| \(.n) | \(q1 | c) | \(.options // "—" | c) | \(.default // "—" | c) | \(.milestone // "—" | c) | \(if (.waits_on | length) > 0 then (.waits_on | join(", ") | c) else "—" end) | [\(.at)](\(.url)) |")) end),
      "",
      "## Answered (last 20)",
      "",
      (if ($done | length) == 0 then "(none)" else
        ("| n | Question | Answer | Links |", "|---|---|---|---|",
         ($done[:20][] | "| \(.n) | \(q1 | c) | \(.answer.text | c) | [ask](\(.url)) · [answer](\(.answer.url)) |")) end),
      "",
      "## Messages (last 10)",
      "",
      (if ($msgs | length) == 0 then "(none)" else
        ("| From | At | Message | Link |", "|---|---|---|---|",
         ($msgs[:10][] | "| \(.from | c) | \(.at) | \(.text | split("\n")[0] | c) | [comment](\(.url)) |")) end)
  ' <<< "$parsed" > "$tmp"
  issue_edit_body "$repo" "$n" "$tmp" || die "cannot edit the body of the desk $repo#$n"
  rm -f "$tmp"
  echo "published https://github.com/$repo/issues/$n"
}

# open_asks_n <parsed>: the numbers of the open asks, one per line.
open_asks_n() { jq -r '.asks[] | select(.state == "open") | .n' <<< "$1"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  open)
    [[ $# -eq 1 ]] || die "usage: desk.sh open <SEAT>"
    id="$(seat_rostered "$1")" || exit 1
    repo="$(seat_repo "$id")" || exit 1
    f="$(desk_find "$id" "$repo")" || exit 1
    if [[ -n "$f" ]]; then
      read -r repo n state <<< "$f"
      [[ "$state" == open ]] || die "the desk of $id ($repo#$n) is closed: a desk is never closed; reopen it"
      echo "exists: https://github.com/$repo/issues/$n"; exit 0
    fi
    coord_write_guard "$repo" "$id"
    decider="$(roster_decider)" || exit 1
    label_ensure_template "$repo" desk
    seat_label_ensure "$repo" "$id"
    tmp="$(mktemp)"; printf 'Desk of %s: generated by daita-beast desk.sh publish.\n' "$id" > "$tmp"
    url="$(issue_create "$repo" --title "Desk: $id" --label desk --label "seat:$id" --assignee "$decider" --body-file "$tmp")" || die "cannot create the desk of $id in $repo"
    rm -f "$tmp"
    echo "opened: $url"
    # open returns only once the list shows this desk, so a later open finds it (the list lags a create).
    issues_list_shows "$repo" "${url##*/}" -f labels="desk,seat:$id" -f state=all
    publish "$id" >/dev/null
    ;;
  ask)
    [[ $# -ge 1 ]] || die "usage: desk.sh ask <SEAT> --text \"<question>\" [--options \"a | b\"] [--default a]"
    id="$(seat_rostered "$1")" || exit 1; shift
    text=""; options=""; default=""; ms=""; waits=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --text) text="$2"; shift 2 ;;
        --options) options="$2"; shift 2 ;;
        --default) default="$2"; shift 2 ;;
        --milestone) ms="$2"; shift 2 ;;
        --waits-on) w="$(waits_on_ref "$2")" || exit 1; waits+=("$w"); shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "${text//[[:space:]]/}" ]] || die "ask needs --text \"<question>\""
    ! printf '%s\n' "$text" | grep -qE '^(options|default):|^BEAST-|^Waits on:' || die "a question line may not start with options:, default:, Waits on: or BEAST- (pass --options / --default / --waits-on)"
    [[ "$options$default" != *$'\n'* ]] || die "--options and --default are one line each"
    ask_inline_check "desk ask of $id" "$text
$options"
    if [[ -n "$default" && -n "$options" ]]; then
      printf '%s\n' "$options" | tr '|' '\n' | sed 's/^ *//; s/ *$//' | grep -qxF -- "$default" || die "--default '$default' is not one of --options '$options'"
    fi
    f="$(desk_of "$id")" || exit 1; read -r repo n <<< "$f"
    [[ -z "$ms" ]] || milestone_title_check "$ms"
    milestone_require "$repo" "$ms" >/dev/null || exit 1
    cs="$(issue_comments "$repo" "$n")" || die "cannot read the comments of the desk $repo#$n"
    seq="$(ask_next_n "$cs")" || exit 1
    body="$(ask_header "$seq" "$id" "$(utc_now)" "$ms")
$text"
    for w in "${waits[@]:-}"; do [[ -z "$w" ]] || body="$body
$(waits_on_line "$w")"; done
    [[ -z "$options" ]] || body="$body
options: $options"
    [[ -z "$default" ]] || body="$body
default: $default"
    issue_comment "$repo" "$n" "$body"
    publish "$id"
    ;;
  answer)
    [[ $# -eq 3 ]] || die "usage: desk.sh answer <SEAT> <n> \"<the decider's words, verbatim>\""
    id="$(seat_id "$1")" || exit 1; k="$2"; text="$3"   # the decider answers ANY seat's ask: the seat may be of another repo
    [[ "$k" =~ ^[0-9]+$ ]] || die "ask number '$k' is not a number"
    [[ -n "${text//[[:space:]]/}" ]] || die "an answer carries the words"
    f="$(desk_of "$id")" || exit 1; read -r repo n <<< "$f"
    open_asks_n "$(desk_parse "$id" "$(row_read "$repo" "$n")" 2>/dev/null)" | grep -qx -- "$k" || die "n=$k is not an open ask on the desk of $id (desk.sh publish $id lists them)"
    issue_comment "$repo" "$n" "BEAST-ANSWER n=$k $text
(words typed to $id's session, verbatim)"
    publish "$id"
    ;;
  withdraw)
    [[ $# -eq 2 ]] || die "usage: desk.sh withdraw <SEAT> <n>"
    id="$(seat_rostered "$1")" || exit 1; k="$2"
    [[ "$k" =~ ^[0-9]+$ ]] || die "ask number '$k' is not a number"
    f="$(desk_of "$id")" || exit 1; read -r repo n <<< "$f"
    open_asks_n "$(desk_parse "$id" "$(row_read "$repo" "$n")" 2>/dev/null)" | grep -qx -- "$k" || die "n=$k is not an open ask on the desk of $id"
    issue_comment "$repo" "$n" "BEAST-WITHDRAW n=$k"
    publish "$id"
    ;;
  msg)
    [[ $# -ge 1 ]] || die "usage: desk.sh msg <TO-SEAT> --from <SEAT> --text \"<body>\" [--re <owner/repo#N | url>]"
    to="$(seat_id "$1")" || exit 1; shift   # the recipient is ANOTHER seat: its desk is in its own repo (seat_repo)
    from=""; text=""; re="none"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --from) from="$2"; shift 2 ;;
        --text) text="$2"; shift 2 ;;
        --re) re="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "$from" && -n "${text//[[:space:]]/}" ]] || die "msg needs --from <SEAT> and --text \"<body>\""
    [[ "$re" == none || "$re" =~ ^https://[^[:space:]]+$ ]] || { rn="$(parse_issue_ref "$re")" || exit 1; read -r rr rnum <<< "$rn"; re="$rr#$rnum"; }
    from="$(seat_rostered "$from")" || exit 1   # the sender is a seat of this roster
    from="$(seat_identity "$from")" || exit 1
    to_id="$(seat_identity "$to")" || exit 1
    f="$(desk_of "$to")" || exit 1; read -r repo n <<< "$f"
    issue_comment "$repo" "$n" "$(msg_header "$from" "$to_id" "$re")
$text"
    publish "$to"
    ;;
  publish)
    [[ $# -eq 1 ]] || die "usage: desk.sh publish <SEAT>"
    id="$(seat_rostered "$1")" || exit 1
    publish "$id"
    ;;
  inbox)
    [[ $# -eq 1 ]] || die "usage: desk.sh inbox <SEAT>"
    id="$(seat_rostered "$1")" || exit 1
    repo="$(seat_repo "$id")" || exit 1
    f="$(desk_find "$id" "$repo")" || exit 1
    if [[ -z "$f" ]]; then echo "desk: $id has none (desk.sh open $id)"; exit 0; fi
    read -r repo n state <<< "$f"
    [[ "$state" == open ]] || die "the desk of $id ($repo#$n) is closed: a desk is never closed; reopen it"
    rd="$(row_read "$repo" "$n")"
    parsed="$(desk_parse "$id" "$rd")" || exit 1
    acked="$(seat_acks "$rd" | awk -F'\t' -v s="$id" '$1==s {print $2}')"
    out="$(jq -r --arg ack "$acked" '
      ([.asks[] | select(.state == "answered" and .answer.at > $ack)] | map("  answered n=\(.n): \(.question[0] // "") -> \(.answer.text | split("\n")[0])  \(.answer.url)")) +
      ([.messages[] | select(.at > $ack)] | map("  message from \(.from) at \(.at): \(.text | split("\n")[0])  \(.url)")) | .[]' <<< "$parsed")"
    open_n="$(jq '[.asks[] | select(.state == "open")] | length' <<< "$parsed")"
    if [[ -z "$out" ]]; then
      echo "desk: nothing new for $id since its last ack ${acked:-(none)}; $open_n open ask(s) — https://github.com/$repo/issues/$n"
    else
      echo "desk: new for $id since its last ack ${acked:-(none)} — https://github.com/$repo/issues/$n ($open_n open ask(s)). Act, then: ack.sh $repo#$n --seat $id --state seen --next \"<act>\""
      printf '%s\n' "$out"
    fi
    ;;
  *) die "usage: desk.sh open|ask|answer|withdraw|msg|publish|inbox (see the header of $0)" ;;
esac
