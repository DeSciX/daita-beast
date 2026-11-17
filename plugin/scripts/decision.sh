#!/usr/bin/env bash
# decision.sh — file, close, or sweep pending decisions.
#   decision.sh --help   this header, and the rule every row's text is written to (ask_inline_check, lib.sh ASK_INLINE_RULE):
#       the content inline, or a URL to a file or diff at a commit; never a local path or "see session". new, record and
#       revise refuse it before anything is written, so compose the row that way.
#   decision.sh new [--repo <owner/repo>] [--decides <owner/repo>] --title "<plain question>" --assignee <login> --by <LABEL | login/LABEL>
#       --decision "<text>" --unblocks "<text>" --waits "<text>" --recommendation "<text>"
#       --approve-with "<exact phrase>" --record "<repo commit — path>"
#       [--seat <LABEL | login/LABEL>]... [--hands] [--project <owner>/<number>]...
#       [--milestone "<title>"] [--waits-on <seat | owner/repo#N>]...
#       [--stops-if "<condition>"]... [--undo "<how the act is undone>"] [--run-sheet <https url>]
#       [--sub "<slug>: <one-line act>[ when: <condition>]"]... | [--follows <program owner/repo#N | url> --sub-act <slug>]
#     or: decision.sh new [--repo ...] [--decides ...] --title ... --assignee ... --by ... --body-file <md> [--seat ...] [--hands] [--project ...]
#   --sub (repeatable) files a PROGRAM row: its body gets the section `## Sub-acts` right after `## Decision`, one line per
#   sub-act (sub_acts_render, lib.sh), and the decider's one approving answer on it pre-authorizes every listed sub-act.
#   A sub-act may carry " when: <condition>": the act waits on it, and its follow-on closes covered only with
#   --condition-met evidence; a condition that does not hold is a stop, never a widening.
#   --stops-if (repeatable) and --undo write the optional sections `## Stops if` ("- <condition>" each: the seat halts and
#   comes back instead of proceeding) and `## Undo` (the rollback, named; every deploy, release or publish row carries it)
#   right before `## Approve with` (row_optional_set, lib.sh); a --body-file may carry them instead, never both.
#   --run-sheet (a --hands row only) appends "Run sheet: <url>" (run_sheet_line) to `## Decision`: the page the decider
#   works through for the act only they can perform (the stage-hands skill).
#   --follows with --sub-act files a FOLLOW-ON row for one listed sub-act of an approved program: the line "Follows:
#   <owner/repo#N> sub-act <slug>" (follows_line) is appended to its `## Decision`; it is refused, before anything is
#   written, unless the program covers that sub-act now (program_cover: the sub-act listed, the program approved, not
#   revise-pending, not rejected) and --assignee is an assignee of the program. A follow-on is covered: the board renders
#   it under its program, never as the decider's turn, and its seat closes it with close --covered. A row is a program
#   or a follow-on, never both; anything not listed is a normal row.
#   --by names the filing seat: its seen ack (ack_line, lib.sh) is the row's first comment, so the filer is current on
#   the row it filed and the relay never sends the filing back to it (event_actors, lib.sh).
#   The row is filed in --repo, by default the roster's "repo" (the home of the seats working from this checkout).
#   --decides names the repo the row decides, when it is another: the line "Decides: https://github.com/<owner/repo>"
#   is appended to the body's ## Decision section (the six sections stay the six).
#   --milestone files the row under that open milestone of the repo; it is required when the repo has any open
#   milestone (milestone_require, lib.sh, dies listing them). Each --waits-on appends the line "Waits on: <ref>"
#   (waits_on_line, lib.sh) to the body's ## Waits section: dependencies as data, read by deps.sh.
#   Every write (new, record, close) refuses a public or public-intended repo (coord_write_guard, lib.sh).
#   decision.sh close <owner/repo#N | url> --words "<verbatim ruling>" --record "<repo commit | comment url>" --by <LABEL | login/LABEL> [--board <owner/repo>] [--next "<act>"]
#       the close comment's last line is the closing seat's BEAST-ACK (state=seen); the other seats ack separately
#   decision.sh close <owner/repo#N | url> --covered [--condition-met "<evidence>"] --by <LABEL | login/LABEL> [--board <owner/repo>] [--next "<act>"]
#       closes a follow-on row under its program, by the row's own seat (row_seat_require), with no words: refused unless
#       its Follows: line names a sub-act the program covers now (program_cover); the close line is "Closed as covered by
#       <the program's approving answer url> by <seat id>" (row_close_comment, kind covered). When the program's line for
#       that sub-act carries " when: <condition>", --condition-met is required (one line: the evidence the condition
#       holds, e.g. the test run and the served==built hashes) and is written into the close line as "; condition met:
#       <evidence>"; it is refused on a sub-act without a condition and on any other close.
#   decision.sh revise <owner/repo#N | url> --by <LABEL | login/LABEL> [--decision …] [--unblocks …] [--waits …]
#       [--recommendation …] [--approve-with "<exact phrase>"] [--record …] [--sub "<slug>: <act>"]...
#       [--stops-if "<condition>"]... [--undo "<text>"] [--run-sheet <https url>] | --body-file <md>
#       revises the row itself, in one of two cases. (a) The decider's standing answer on the row is a revise:
#       (row_answer_url): the revision answers it. (b) The row has no standing answer yet (none, or only an approval older
#       than its latest amend line): its own seat amends it (row_seat_require: --by is the row's filer or one of its seats),
#       when the facts under it changed. Refused on a closed row and once the decider's standing answer is an approve or a
#       reject. Either case rewrites only the named sections of the body (section_replace; --sub replaces the program's
#       whole `## Sub-acts`; --approve-with
#       swaps the quoted phrase and keeps the paragraph; --stops-if replaces the whole `## Stops if`, --undo the `## Undo`,
#       each added before `## Approve with` when absent; --run-sheet replaces the Run sheet: line of `## Decision`, on a
#       row labelled hands only; --body-file replaces the six, each checked by section_required),
#       then posts ONE comment whose first line is the amend line (amend_line: "revised after <revise url>; changed:
#       <sections>", or in case (b) "amended by <seat id> before any answer; changed: <sections>") and whose last line is the
#       body line (body_line). An approval older than the amend no longer counts (row_answer_url), and until the amend no approval
#       closes the row (row_revise_pending: decision.sh close, pr.sh close --merge, publish.sh merge). A reply comment
#       is not a revision. On a pull request, push the change first; --body-file then replaces the PR body whole.
#   decision.sh restore <owner/repo#N | url> --by <LABEL | login/LABEL>
#       puts a row's body back to exactly the last body a Beast script wrote (new, revise, restore, pr.sh request; publish.sh
#       request files through new), after a hand edit broke it: the newest comment whose last line is a body line
#       (body_line: "BEAST-BODY digest=<digest of the body written>", body_record_last) names it, and the version of the
#       body in the issue's edit history (issue_body_versions, GraphQL userContentEdits) with that digest is written back
#       byte for byte; no text is composed. Seat-only: --by is the row's filer (row_filer) or one of its seats (row_seats).
#       Posts ONE comment whose first line is the amend line ("restored the body recorded at <url>; changed: <sections>"),
#       so an approval older than it no longer counts (row_answer_url), then edits the body. Refused on a closed row, while
#       the decider's revise: is pending (decision.sh revise answers it), when no body line exists, when the current body
#       already is that body, when the edit history cannot be read or does not hold it, and when that body is itself
#       malformed (section_required over ROW_SECTIONS, or PR_ROW_SECTIONS on a pull request).
#   decision.sh record --repo ... --title ... --assignee ... <the new sections or --body-file> --words "<verbatim>" --record "<repo commit>" --by <LABEL | login/LABEL> [--seat ...] [--rejected]
#       files the row AND closes it on the words in one act: for a decision the decider gave in session before a
#       row existed, so the board's decided table carries it (nothing is decided off the board).
#   decision.sh inbox <LABEL | login/LABEL>   the board rows (decision issues and PRs labelled needs-review) labelled
#       seat:<login>/<LABEL> (open, or closed in the last 7 days) whose latest event (created, the decider's answer,
#       closed) is newer than the seat's newest BEAST-ACK, then the seat's desk (desk.sh inbox); computed from
#       GitHub, nothing local, the same on every machine and surface. It opens with the seat's home milestones due
#       within 3 days or overdue (milestone_due_flags, lib.sh), one line each, when there are any
# The row carries the label seat:<login>/<LABEL> of the filing seat (--by) and of each --seat (a LABEL resolved through
# the roster, or an id) that waits on the decision, each created in the repo when missing and read back after the
# write (seat_labels_require dies naming a label that did not land), so every row is in its seats' inboxes and relay
# and filterable in the GitHub UI.
# `close` comments the verbatim word with its record, closes the issue, republishes the decider's board
# (the roster's "board" repo, or --board), and prints the waiting seats with their live addresses so the
# closing session can send each one line. The record (a dated commit, or the decider's own comment on
# the issue) stays the owner of the words; the close comment cites it.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq
here="$(dirname "${BASH_SOURCE[0]}")"

cmd="${1:-}"; shift || true
case "$cmd" in
  new)
    repo=""; decides=""; title=""; assignee=""; by=""; hands=0; body_file=""; projects=(); seats=(); ms=""; waits=()
    d=""; u=""; w=""; r=""; a=""; rec=""; subs=(); follows=""; subact=""; stops=(); undo=""; runsheet=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --stops-if) stops+=("$2"); shift 2 ;;
        --undo) undo="$2"; shift 2 ;;
        --run-sheet) runsheet="$2"; shift 2 ;;
        --repo) repo="$2"; shift 2 ;;
        --decides) decides="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --assignee) assignee="$2"; shift 2 ;;
        --by) by="$2"; shift 2 ;;
        --hands) hands=1; shift ;;
        --project) projects+=("$2"); shift 2 ;;
        --seat) seats+=("$2"); shift 2 ;;
        --body-file) body_file="$2"; shift 2 ;;
        --decision) d="$2"; shift 2 ;;
        --unblocks) u="$2"; shift 2 ;;
        --waits) w="$2"; shift 2 ;;
        --recommendation) r="$2"; shift 2 ;;
        --approve-with) a="$2"; shift 2 ;;
        --record) rec="$2"; shift 2 ;;
        --milestone) ms="$2"; shift 2 ;;
        --waits-on) wr="$(waits_on_ref "$2")" || exit 1; waits+=("$wr"); shift 2 ;;
        --sub) subs+=("$2"); shift 2 ;;
        --follows) follows="$2"; shift 2 ;;
        --sub-act) subact="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "$title" && -n "$assignee" && -n "$by" ]] || die "new needs --title, --assignee and --by <the filing seat>"
    [[ -z "$follows" && -z "$subact" ]] || [[ -n "$follows" && -n "$subact" ]] || die "a follow-on row takes --follows <program row> and --sub-act <slug> together"
    [[ -z "$follows" || ${#subs[@]} -eq 0 ]] || die "a row is a program (--sub) or a follow-on (--follows), not both"
    [[ -z "$runsheet" || $hands -eq 1 ]] || die "--run-sheet links the run sheet of a hands row: file it with --hands (only the decider can perform the act)"
    by="$(seat_id "$by")" || exit 1
    [[ -n "$repo" ]] || repo="$(roster_repo)" || exit 1
    [[ -z "$decides" || "$decides" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "--decides '$decides' is not owner/repo"
    coord_write_guard "$repo" "$by"
    [[ -z "$ms" ]] || milestone_title_check "$ms"
    msn="$(milestone_require "$repo" "$ms")" || exit 1
    # The row's seats, each resolved to its id before anything is written: the filer first, always (a row without a
    # seat: label reaches no seat's inbox or relay), then every --seat that is not the filer.
    ids=("$by")
    for s in "${seats[@]:-}"; do
      [[ -n "$s" ]] || continue; s="$(seat_id "$s")" || exit 1
      [[ " ${ids[*]} " == *" $s "* ]] || ids+=("$s")
    done
    tmp="$(mktemp)"
    if [[ -n "$body_file" ]]; then
      cp "$body_file" "$tmp"
    else
      [[ -n "$d" && -n "$u" && -n "$w" && -n "$r" && -n "$a" && -n "$rec" ]] || die "new needs every section (--decision --unblocks --waits --recommendation --approve-with --record) or --body-file"
      cat > "$tmp" <<EOF
## Decision
$d

## Unblocks
$u

## Waits
$w

## Recommendation
$r

## Approve with
"$a" — typed to the orchestrator session, or commented here by the assignee (here a bare \`approve\` also counts; \`<phrase> — <comment>\` approves with a comment; \`revise: <what to change>\` sends it back; \`reject: <reason>\` closes it). Any other wording is a question back.

## Record
$rec
EOF
    fi
    if [[ -n "$decides" && "$(tr 'A-Z' 'a-z' <<< "$decides")" != "$(tr 'A-Z' 'a-z' <<< "$repo")" ]]; then
      # The decided repo is a link at the end of ## Decision: the board shows the section whole, so it reads there.
      awk -v line="Decides: https://github.com/$decides" '
        $0 == "## Decision" { on = 1; print; next }
        on && /^## / { print line; print ""; on = 0 }
        { print }
        END { if (on) print line }' "$tmp" > "$tmp.d" && mv "$tmp.d" "$tmp"
    fi
    if [[ -n "$follows" ]]; then
      # The follow-on's marker is a line at the end of ## Decision (follows_line), like Decides:.
      frn="$(parse_issue_ref "$follows")" || exit 1; read -r fr fn <<< "$frn"
      fl="$(follows_line "$fr#$fn" "$subact")" || exit 1
      FL="$fl" awk '
        $0 == "## Decision" { on = 1; print; next }
        on && /^## / { print ENVIRON["FL"]; print ""; on = 0 }
        { print }
        END { if (on) print ENVIRON["FL"] }' "$tmp" > "$tmp.f" && mv "$tmp.f" "$tmp"
    fi
    if [[ ${#subs[@]} -gt 0 ]]; then
      # The program's sub-acts: the section ## Sub-acts right after ## Decision (sub_acts_render, the one writer).
      [[ -z "$(section "$SUB_ACTS_SECTION" < "$tmp")" ]] || die "new decision '$title': the body already has '## $SUB_ACTS_SECTION': pass the sub-acts in the body or with --sub, not both"
      sl="$(sub_acts_render "${subs[@]}")" || exit 1
      SL="$sl" H="## $SUB_ACTS_SECTION" awk '
        $0 == "## Decision" { on = 1; print; next }
        on && /^## / { print ENVIRON["H"]; print ENVIRON["SL"]; print ""; on = 0 }
        { print }
        END { if (on) { print ""; print ENVIRON["H"]; print ENVIRON["SL"] } }' "$tmp" > "$tmp.s" && mv "$tmp.s" "$tmp"
    fi
    # The optional sections, right before ## Approve with (row_optional_set, the one writer of their place).
    if [[ ${#stops[@]} -gt 0 ]]; then
      ! grep -qxF -- "## Stops if" "$tmp" || die "new decision '$title': the body already has '## Stops if': pass the conditions in the body or with --stops-if, not both"
      sl="$(stops_if_render "${stops[@]}")" || exit 1
      row_optional_set "Stops if" "$sl" < "$tmp" > "$tmp.o" && mv "$tmp.o" "$tmp" || exit 1
    fi
    if [[ -n "$undo" ]]; then
      ! grep -qxF -- "## Undo" "$tmp" || die "new decision '$title': the body already has '## Undo': pass it in the body or with --undo, not both"
      [[ -n "${undo//[[:space:]]/}" ]] || die "new decision '$title': --undo is empty"
      row_optional_set "Undo" "$undo" < "$tmp" > "$tmp.o" && mv "$tmp.o" "$tmp" || exit 1
    fi
    if [[ -n "$runsheet" ]]; then
      [[ -z "$(run_sheet_parse "new decision '$title'" "$(cat "$tmp")")" ]] || die "new decision '$title': the body already has a Run sheet: line: pass it in the body or with --run-sheet, not both"
      rl="$(run_sheet_line "$runsheet")" || exit 1
      section_line_set "Decision" "Run sheet:" "$rl" < "$tmp" > "$tmp.r" && mv "$tmp.r" "$tmp" || exit 1
    fi
    if [[ ${#waits[@]} -gt 0 ]]; then
      # Each dependency is a "Waits on: <ref>" line at the end of ## Waits (the one shape, waits_on_line).
      wl="$(for wr in "${waits[@]}"; do waits_on_line "$wr"; done)" || exit 1
      WL="$wl" awk '
        $0 == "## Waits" { on = 1; print; next }
        on && /^## / { print ENVIRON["WL"]; print ""; on = 0 }
        { print }
        END { if (on) print ENVIRON["WL"] }' "$tmp" > "$tmp.w" && mv "$tmp.w" "$tmp"
    fi
    body="$(cat "$tmp")"
    ask_inline_check "new decision '$title'" "$title
$body"
    waits_on_parse "new decision '$title'" "$body" >/dev/null || exit 1
    for h in "${ROW_SECTIONS[@]}"; do
      section_required "$h" "$body" "new decision '$title'" >/dev/null
    done
    row_optional_check "new decision '$title'" "$body"
    rs="$(run_sheet_parse "new decision '$title'" "$body")" || exit 1
    [[ -z "$rs" || $hands -eq 1 ]] || die "new decision '$title': its body links a run sheet (Run sheet: $rs): a run sheet belongs to a hands row; file it with --hands"
    # A program or a follow-on is read from the body itself (a --body-file one too), before anything is written.
    progsubs="$(sub_acts_parse "new decision '$title'" "$body")" || exit 1
    fol="$(follows_parse "new decision '$title'" "$body")" || exit 1
    [[ -z "$progsubs" || -z "$fol" ]] || die "new decision '$title': a row is a program (## $SUB_ACTS_SECTION) or a follow-on (Follows:), not both"
    cover=""; fcond=""
    if [[ -n "$fol" ]]; then
      IFS=$'\t' read -r fref fslug <<< "$fol"
      cover="$(program_cover "$fref" "$fslug")" || exit 1
      frn="$(parse_issue_ref "$fref")" || exit 1; read -r fr fn <<< "$frn"
      pinfo="$(issue_get "$fr" "$fn")" || exit 1
      jq -e --arg a "$assignee" 'any(.assignees[]; .login == $a)' <<< "$pinfo" >/dev/null \
        || die "new decision '$title': --assignee $assignee is not an assignee of the program $fref: a follow-on is assigned to the program's decider"
      fcond="$(sub_act_condition "$fref" "$(jq -r '.body // ""' <<< "$pinfo")" "$fslug")" || exit 1
    fi
    phrase="$(approve_phrase "$body")"
    [[ -n "$phrase" ]] || die "new decision '$title': its '## Approve with' section has no double-quoted phrase (the exact words that approve it, in \"…\")"
    [[ "$phrase$a" != *"|"* ]] || die "new decision '$title': the approving phrase '${a:-$phrase}' carries '|': one exact approving phrase per row; a choice between options is a desk ask (desk.sh ask <SEAT> --text \"…\" --options \"a | b\")"
    # A repo filed in for the first time has none of the labels; create what this issue needs
    # (the board and the relay find decisions by label, so an unlabelled issue is invisible).
    label_ensure_template "$repo" decision
    labels=(--label decision); [[ $hands -eq 1 ]] && { label_ensure_template "$repo" hands; labels+=(--label hands); }
    for s in "${ids[@]}"; do seat_label_ensure "$repo" "$s"; labels+=(--label "seat:$s"); done
    [[ "$title" == Decision:* ]] || title="Decision: $title"
    # Idempotent: a rerun after a failure part-way (the create landed, a later step died) finds the row it filed
    # instead of filing a second. The list API, not search (the search index lags a create): an OPEN decision
    # issue with this exact title, filed by this login, carrying exactly these seat labels, is reused.
    want_seats="$(printf 'seat:%s\n' "${ids[@]}" | jq -R . | jq -sc 'sort')"
    url="$(issues_list "$repo" -f labels=decision -f state=open | jq -r --arg t "$title" --arg me "$(gh_login)" --argjson s "$want_seats" '
      [.[] | select(.pull_request == null and .title == $t and .user.login == $me
                    and ([.labels[].name | select(startswith("seat:"))] | sort) == $s)] | sort_by(.number) | .[0].html_url // empty')" \
      || die "cannot list the open decision issues of $repo to check for this row"
    reused=0
    if [[ -n "$url" ]]; then
      reused=1
      echo "reusing $url (an open decision row with this title and these seats, filed by $(gh_login))" >&2
      [[ -z "$msn" ]] || milestone_set "$repo" "${url##*/}" "$msn"
    else
      url="$(issue_create "$repo" --title "$title" --assignee "$assignee" "${labels[@]}" ${msn:+--milestone "$msn"} --body-file "$tmp")"
      issues_list_shows "$repo" "${url##*/}" -f labels=decision -f state=open   # so a rerun finds it (the list lags a create)
    fi
    rm -f "$tmp"
    seat_labels_require "$repo" "${url##*/}" "${ids[@]}"
    # The filer's seen ack, the row's first comment (a rerun that reuses the row posts it only when it is missing).
    acked=0
    if [[ $reused -eq 1 ]]; then rd="$(row_read "$repo" "${url##*/}")" || exit 1; seat_acks "$rd" | cut -f1 | grep -qxF -- "$by" && acked=1; fi
    if [[ $acked -eq 0 ]]; then
      line="$(ack_line "$by" seen "filed; waits on the decider's word")" || exit 1
      # Its last line records the body this filing wrote (body_line, lib.sh): what decision.sh restore puts back.
      issue_comment "$repo" "${url##*/}" "$line

$(body_line "$body")" >/dev/null \
        || die "$url is filed but the filer's ack was NOT posted (named above): rerun the same decision.sh new, which reuses the row and posts it"
    fi
    echo "$url"
    [[ -z "$cover" ]] || echo "covered: sub-act $fslug of the program $fref, approved at $cover; once the sub-act is done: decision.sh close $url --covered --by $by${fcond:+ --condition-met \"<evidence that: $fcond>\" (its condition; when it does not hold, stop and come back: never widen the sub-act)}" >&2
    [[ -z "$progsubs" ]] || echo "program: the decider's one approving answer pre-authorizes $(cut -f1 <<< "$progsubs" | paste -sd, - | sed 's/,/, /g'); file each as a follow-on (decision.sh new --follows $url --sub-act <slug> …) once approved" >&2
    for p in "${projects[@]:-}"; do
      [[ -n "$p" ]] || continue
      owner="${p%%/*}"; number="${p##*/}"
      project_cmd item-add "$number" --owner "$owner" --url "$url" >/dev/null && echo "added to project $p"
    done
    ;;
  close)
    ref="${1:-}"; shift || true
    words=""; rec=""; by=""; board=""; rejected=0; covered=0; next=""; met=""; metset=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --condition-met) met="$2"; metset=1; shift 2 ;;
        --next) next="$2"; shift 2 ;;
        --words) words="$2"; shift 2 ;;
        --record) rec="$2"; shift 2 ;;
        --by) by="$2"; shift 2 ;;
        --board) board="$2"; shift 2 ;;
        --rejected) rejected=1; shift ;;
        --covered) covered=1; shift ;;
        *) die "unknown argument $1" ;;
      esac
    done
    if [[ $covered -eq 1 ]]; then
      [[ -n "$ref" && -n "$by" ]] || die "close --covered needs <issue> --by <SEAT>"
      [[ -z "$words$rec" && $rejected -eq 0 ]] || die "close --covered takes no --words, --record or --rejected: a covered close quotes no words; its record is the program's approving answer"
      [[ -n "$next" ]] || next="execute the sub-act"
      [[ $metset -eq 0 || -n "${met//[[:space:]]/}" ]] || die "close --covered: --condition-met is empty: it is the evidence that the sub-act's condition holds"
      [[ "$met" != *$'\n'* ]] || die "close --covered: --condition-met is one line"
    else
      [[ $metset -eq 0 ]] || die "--condition-met belongs to close --covered (a follow-on whose sub-act carries a condition), not to a close on the words"

      [[ -n "$ref" && -n "$words" && -n "$rec" && -n "$by" ]] || die "close needs <issue> --words --record --by [--rejected], or <issue> --covered --by"
      [[ -n "$next" ]] || next="execute on the words"
    fi
    [[ -n "$board" ]] || board="$(board_repo)"
    by="$(seat_id "$by")" || exit 1
    rn="$(parse_issue_ref "$ref")" || exit 1; read -r repo number <<< "$rn"
    coord_write_guard "$repo" "$by"
    issue_get "$repo" "$number" | jq -e '.pull_request == null' >/dev/null || die "$repo#$number is a pull request: close it with pr.sh close (--merge or --rejected)"
    if [[ $covered -eq 1 ]]; then
      # A follow-on closed under its program: its own seat, its Follows: line, and the program covering that sub-act now.
      who="$repo#$number"
      rd="$(row_read "$repo" "$number")" || exit 1
      [[ "$(jq -r .issue.state <<< "$rd")" == open ]] || die "$who is closed"
      fol="$(follows_parse "$who" "$(jq -r '.issue.body // ""' <<< "$rd")")" || exit 1
      [[ -n "$fol" ]] || die "$who is not a follow-on row (its body has no 'Follows: <program> sub-act <slug>' line): it closes on the decider's words"
      row_seat_require "$rd" "$by" "$who" "closes it as covered"
      IFS=$'\t' read -r fref fslug <<< "$fol"
      ans="$(program_cover "$fref" "$fslug")" || exit 1
      # The sub-act's condition, from the program's own line (sub_act_condition): evidence is required for one, refused without.
      prn="$(parse_issue_ref "$fref")" || exit 1; read -r pr_ pn_ <<< "$prn"
      pbody="$(issue_get "$pr_" "$pn_" | jq -r '.body // ""')" || exit 1
      cond="$(sub_act_condition "$fref" "$pbody" "$fslug")" || exit 1
      if [[ -n "$cond" ]]; then
        [[ -n "$met" ]] || die "$who: sub-act $fslug of $fref carries the condition \"$cond\": close --covered needs --condition-met \"<the evidence it holds>\"; when it does not hold, stop and come back to the decider (a new row), never widen the sub-act"
      else
        [[ -z "$met" ]] || die "$who: sub-act $fslug of $fref carries no condition: --condition-met has nothing to meet"
      fi
      if [[ -n "$met" ]]; then row_close "$repo" "$number" "" "$ans" "$by" "$next" covered "$board" "$met"
      else row_close "$repo" "$number" "" "$ans" "$by" "$next" covered "$board"; fi
      exit 0
    fi
    if [[ $rejected -eq 0 ]]; then
      pend="$(row_revise_pending "$(row_read "$repo" "$number")")" || exit 1
      [[ -z "$pend" ]] || revise_pending_refusal "$pend"
    fi
    row_close "$repo" "$number" "$words" "$rec" "$by" "$next" "$([[ $rejected -eq 1 ]] && echo rejected || echo closed)" "$board"
    ;;
  revise)
    ref="${1:-}"; shift || true
    by=""; body_file=""; names=(); vals=(); subs=(); stops=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --by) by="$2"; shift 2 ;;
        --body-file) body_file="$2"; shift 2 ;;
        --sub) subs+=("$2"); shift 2 ;;
        --stops-if) stops+=("$2"); shift 2 ;;
        --undo) names+=("Undo"); vals+=("$2"); shift 2 ;;
        --run-sheet) names+=("Run sheet"); vals+=("$2"); shift 2 ;;
        --decision) names+=("Decision"); vals+=("$2"); shift 2 ;;
        --unblocks) names+=("Unblocks"); vals+=("$2"); shift 2 ;;
        --waits) names+=("Waits"); vals+=("$2"); shift 2 ;;
        --recommendation) names+=("Recommendation"); vals+=("$2"); shift 2 ;;
        --approve-with) names+=("Approve with"); vals+=("$2"); shift 2 ;;
        --record) names+=("Record"); vals+=("$2"); shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    if [[ ${#subs[@]} -gt 0 ]]; then sl="$(sub_acts_render "${subs[@]}")" || exit 1; names+=("$SUB_ACTS_SECTION"); vals+=("$sl"); fi
    if [[ ${#stops[@]} -gt 0 ]]; then sl="$(stops_if_render "${stops[@]}")" || exit 1; names+=("Stops if"); vals+=("$sl"); fi
    [[ -n "$ref" && -n "$by" ]] || die "usage: decision.sh revise <issue> --by <SEAT> (--decision … | --unblocks … | --waits … | --recommendation … | --approve-with \"…\" | --record … | --sub \"<slug>: <act>\"... | --stops-if \"<condition>\"... | --undo \"…\" | --run-sheet <url>)... | --body-file <md>"
    [[ -z "$body_file" || ${#names[@]} -eq 0 ]] || die "revise takes the sections to change, or --body-file, not both"
    [[ -n "$body_file" || ${#names[@]} -gt 0 ]] || die "revise needs the sections to change (--decision, --unblocks, --waits, --recommendation, --approve-with, --record) or --body-file: a revision changes the row, a reply comment does not"
    [[ -z "$body_file" || -f "$body_file" ]] || die "no body file $body_file"
    dupes="$(printf '%s\n' "${names[@]:-}" | sed '/^$/d' | sort | uniq -d | paste -sd, -)"
    [[ -z "$dupes" ]] || die "revise names a section twice: $dupes"
    by="$(seat_id "$by")" || exit 1
    rn="$(parse_issue_ref "$ref")" || exit 1; read -r repo number <<< "$rn"
    coord_write_guard "$repo" "$by"
    rd="$(row_read "$repo" "$number")" || exit 1
    info="$(jq '.issue' <<< "$rd")"
    who="$repo#$number"
    [[ "$(jq -r .state <<< "$info")" == open ]] || die "$who is closed: a decided row is not revised"
    is_pr=0; jq -e '.pull_request != null' <<< "$info" >/dev/null && is_pr=1
    is_hands=0; jq -e 'any(.labels[]; (.name // .) == "hands")' <<< "$info" >/dev/null && is_hands=1
    for h in "${names[@]:-}"; do
      case "$h" in
        "Stops if"|Undo|"Run sheet") [[ $is_pr -eq 0 ]] || die "revise $who: a pull request carries no '$h': it belongs to a decision row" ;;
      esac
    done
    phrase="$(row_phrase "$who" "$info" 2>/dev/null)"
    rev="$(row_answer_url "$rd" "$phrase" revise 2>/dev/null)" || exit 1
    if [[ -z "$rev" ]]; then
      # No revise: to answer: the row's own seat amends it, only while the decider has given no standing answer (an
      # approval older than the latest amend line is none: it no longer counts).
      for k in approve reject; do
        u="$(row_answer_url "$rd" "$phrase" "$k" 2>/dev/null)" || exit 1
        [[ -z "$u" ]] || die "$who: the decider has already answered ($k: $u): a seat amends only a row with no answer yet; a change now is the decider's revise: or a new row"
      done
      row_seat_require "$rd" "$by" "$who" "amends it before the decider answers"
    fi
    old="$(jq -r '.body // ""' <<< "$info")"
    tmp="$(mktemp)"
    if [[ -n "$body_file" ]]; then
      cp "$body_file" "$tmp"
      new="$(cat "$tmp")"
      if [[ $is_pr -eq 0 ]]; then
        for h in "${ROW_SECTIONS[@]}" "$SUB_ACTS_SECTION" "${ROW_OPTIONAL_SECTIONS[@]}"; do
          [[ "$h" == "$SUB_ACTS_SECTION" || " ${ROW_OPTIONAL_SECTIONS[*]} " == *" $h "* ]] || section_required "$h" "$new" "revise $who" >/dev/null
          [[ "$(printf '%s\n' "$old" | section "$h")" == "$(printf '%s\n' "$new" | section "$h")" ]] || names+=("$h")
        done
      else
        names+=("the PR body")
      fi
    else
      printf '%s\n' "$old" > "$tmp"
      for i in "${!names[@]}"; do
        h="${names[$i]}"; v="${vals[$i]}"
        [[ -n "$(sed '/^[[:space:]]*$/d' <<< "$v")" ]] || die "revise $who: --$(tr 'A-Z ' 'a-z-' <<< "$h") is empty"
        if [[ "$h" == "Run sheet" ]]; then
          [[ $is_hands -eq 1 ]] || die "revise $who: --run-sheet links the run sheet of a hands row; this row is not labelled hands"
          v="$(run_sheet_line "$v")" || exit 1
          section_line_set "Decision" "Run sheet:" "$v" < "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" || exit 1
          continue
        fi
        if [[ " ${ROW_OPTIONAL_SECTIONS[*]} " == *" $h "* ]]; then
          row_optional_set "$h" "$v" < "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" || exit 1
          continue
        fi
        if [[ "$h" == "Approve with" ]]; then
          [[ "$v" != *'"'* && "$v" != *$'\n'* ]] || die "revise $who: --approve-with is the exact phrase, one line, no double quote"
          cur="$(printf '%s\n' "$old" | section "Approve with")"
          if grep -q '"[^"]*"' <<< "$cur"; then
            v="$(PH="$v" python3 -I -c 'import os,re,sys; sys.stdout.write(re.sub(r"\"[^\"]*\"", lambda m: "\"" + os.environ["PH"] + "\"", sys.stdin.read(), count=1))' <<< "$cur")"
          else
            v="\"$v\""
          fi
        fi
        section_replace "$h" "$v" < "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
      done
      new="$(cat "$tmp")"
    fi
    ask_inline_check "revise $who" "$new"
    if [[ $is_pr -eq 0 ]]; then
      waits_on_parse "revise $who" "$new" >/dev/null || exit 1
      rs="$(sub_acts_parse "revise $who" "$new")" || exit 1
      rf="$(follows_parse "revise $who" "$new")" || exit 1
      [[ -z "$rs" || -z "$rf" ]] || die "revise $who: a row is a program (## $SUB_ACTS_SECTION) or a follow-on (Follows:), not both"
      row_optional_check "revise $who" "$new"
      rsh="$(run_sheet_parse "revise $who" "$new")" || exit 1
      [[ -z "$rsh" || $is_hands -eq 1 ]] || die "revise $who: the body links a run sheet (Run sheet: $rsh) but the row is not labelled hands"
      np="$(approve_phrase "$new")"
      [[ -n "$np" ]] || die "revise $who: its '## Approve with' section has no double-quoted phrase"
      [[ "$np" != *"|"* ]] || die "revise $who: the approving phrase '$np' carries '|': one exact approving phrase per row; a choice between options is a desk ask"
    else
      np="$(row_phrase "$who" "$(jq --arg b "$new" '.body = $b' <<< "$info")")"
    fi
    pend="$(row_revise_pending "$rd")" || exit 1
    if [[ "$new" == "$old" ]]; then
      # A rerun after the body edit landed and the amend comment did not: post the comment only. Answering a revise:, the
      # amend is missing while the revise is pending; amending an unanswered row, while no body line records this body.
      if [[ -n "$rev" ]]; then
        [[ -n "$pend" ]] || die "revise $who: nothing to change: the body already carries these sections, and the row was amended after $rev"
      else
        last="$(body_record_last "$(jq -c .comments <<< "$rd")")" || die "$who: cannot read the row's comments"
        [[ "${last%%$'\t'*}" != "$(body_digest "$new")" ]] || die "revise $who: nothing to change: the body already carries these sections, recorded at ${last#*$'\t'}"
      fi
      echo "the body of $who already carries this revision; posting the amend line only" >&2
    else
      issue_edit_body "$repo" "$number" "$tmp"
    fi
    rm -f "$tmp"
    # The changed sections in the body's own order, once each.
    changed="$(for h in "${ROW_SECTIONS[@]}" "$SUB_ACTS_SECTION" "${ROW_OPTIONAL_SECTIONS[@]}" "Run sheet" "the PR body"; do for n in "${names[@]:-}"; do if [[ "$n" == "$h" ]]; then echo "$h"; break; fi; done; done | paste -sd, - | sed 's/,/, /g')"
    if [[ -n "$rev" ]]; then
      line="$(amend_line "revised after $rev; changed: $changed")"
      why="The row's body is revised in answer to the decider's revise (by seat $by)."
    else
      line="$(amend_line "amended by $by before any answer; changed: $changed")"
      why="The row's body is amended by its seat $by before the decider answered: the facts under it changed."
    fi
    summary="$(for h in "${ROW_SECTIONS[@]}" "$SUB_ACTS_SECTION" "${ROW_OPTIONAL_SECTIONS[@]}"; do
        [[ ",$(sed 's/, /,/g' <<< "$changed")," == *",$h,"* ]] || continue
        first="$(printf '%s\n' "$new" | section "$h" | sed '/^[[:space:]]*$/d' | head -1 | cut -c1-200)"
        echo "- $h: $first"
      done)"
    cbody="$line

$why ${summary:+The changed sections now open:
$summary

}Approve with \"$np\", or answer again; an approval given before this line no longer counts.

$(body_line "$new")"
    url="$(issue_comment "$repo" "$number" "$cbody")" \
      || die "the body of $who is revised but the amend comment was NOT posted (named above): the row still reads as not revised; rerun the same decision.sh revise"
    echo "revised $who: $changed"
    echo "$url"
    echo "approves with \"$np\""
    ;;
  restore)
    ref="${1:-}"; shift || true
    by=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --by) by="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "$ref" && -n "$by" ]] || die "usage: decision.sh restore <issue> --by <SEAT>"
    by="$(seat_id "$by")" || exit 1
    rn="$(parse_issue_ref "$ref")" || exit 1; read -r repo number <<< "$rn"
    coord_write_guard "$repo" "$by"
    rd="$(row_read "$repo" "$number")" || exit 1
    info="$(jq '.issue' <<< "$rd")"
    who="$repo#$number"
    [[ "$(jq -r .state <<< "$info")" == open ]] || die "$who is closed: a decided row is not restored"
    row_seat_require "$rd" "$by" "$who" "restores its body"
    pend="$(row_revise_pending "$rd")" || exit 1
    [[ -z "$pend" ]] || die "$who: the decider asked for a revision at $pend: decision.sh revise answers it (--body-file restores and revises in one act); a restore is not a revision"
    if jq -e '.pull_request != null' <<< "$info" >/dev/null; then list=("${PR_ROW_SECTIONS[@]}"); else list=("${ROW_SECTIONS[@]}"); fi
    # The last body a Beast script wrote: the newest body line (body_record_last), matched by digest against the body's
    # edit history (issue_body_versions). Restore never composes text: it writes that version back byte for byte.
    rec="$(body_record_last "$(jq -c .comments <<< "$rd")")" || die "$who: cannot read the row's comments"
    [[ -n "$rec" ]] || die "$who: no comment records a body a Beast script wrote (no BEAST-BODY line: filed before this plugin recorded one, or from a surface without a shell): there is nothing to restore from; the decider's revise: and decision.sh revise repair it"
    IFS=$'\t' read -r want recurl <<< "$rec"
    cur="$(jq -r '.body // ""' <<< "$info")"
    [[ "$(body_digest "$cur")" != "$want" ]] || die "$who: nothing to restore: the body already is the last body a Beast script wrote (recorded at $recurl)"
    vers="$(issue_body_versions "$repo" "$number")" || exit 1
    tmp="$(mktemp)"; found=0
    for ((i = $(jq length <<< "$vers") - 1; i >= 0; i--)); do
      jq -j --argjson i "$i" '.[$i].body' <<< "$vers" > "$tmp"
      if [[ "$(body_digest "$(cat "$tmp")")" == "$want" ]]; then found=1; break; fi
    done
    [[ $found -eq 1 ]] || { rm -f "$tmp"; die "$who: the body recorded at $recurl is not in the body's edit history ($(jq length <<< "$vers") version(s) read): nothing is restored"; }
    old="$(cat "$tmp")"
    for h in "${list[@]}"; do
      ( section_required "$h" "$old" "$who" >/dev/null ) 2>/dev/null \
        || { rm -f "$tmp"; die "$who: the last body a Beast script wrote (recorded at $recurl) is itself malformed: empty or missing '## $h'; restoring it repairs nothing; the decider's revise: and decision.sh revise --body-file repair it"; }
    done
    changed="$(for h in "${list[@]}"; do [[ "$(printf '%s\n' "$cur" | section "$h")" == "$(printf '%s\n' "$old" | section "$h")" ]] || echo "$h"; done | paste -sd, - | sed 's/,/, /g')"
    np="$(row_phrase "$who" "$(jq --arg b "$old" '.body = $b' <<< "$info")" 2>/dev/null)"
    # The amend line first, then the body: a failure between them leaves an earlier approval not counting (the safe
    # direction), and a rerun finds the body still broken and restores it.
    line="$(amend_line "restored the body recorded at $recurl; changed: ${changed:-the text outside the sections}")"
    cbody="$line

The row's body is restored by seat $by to the last body a Beast script wrote, from the issue's edit history: a hand edit had changed it. ${np:+Approve with \"$np\", or answer again; }an approval given before this line no longer counts.

$(body_line "$old")"
    url="$(issue_comment "$repo" "$number" "$cbody")" || { rm -f "$tmp"; die "$who: the amend comment was NOT posted (named above): nothing is restored; rerun decision.sh restore"; }
    issue_edit_body "$repo" "$number" "$tmp" || { rm -f "$tmp"; die "$who: the amend line is posted ($url) but the body was NOT restored (named above): rerun decision.sh restore"; }
    rm -f "$tmp"
    echo "restored $who to the body recorded at $recurl: ${changed:-the text outside the sections}"
    echo "$url"
    [[ -z "$np" ]] || echo "approves with \"$np\""
    ;;
  inbox)
    seat="${1:-}"; shift || true
    [[ -n "$seat" ]] || die "usage: decision.sh inbox <LABEL | login/LABEL>"
    [[ $# -eq 0 ]] || die "inbox takes no options: it is computed from the rows' acks, nothing local"
    seat="$(seat_rostered "$seat")" || exit 1
    home="$(seat_repo "$seat")" || exit 1
    flags="$(milestone_due_flags "$home")" || exit 1
    [[ -z "$flags" ]] || { echo "milestones of $home due within 3 days or overdue (move one with a why: milestone.sh move <title> --due <date> --why \"…\"):"; sed 's/^/  /' <<< "$flags"; echo; }
    scope="$(roster_user_terms)"
    since="$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)"
    rows="$(search_seat_issues "$seat" "label:$BOARD_ROW_LABELS is:open $scope")" || die "search failed"
    closed="$(search_seat_issues "$seat" "label:$BOARD_ROW_LABELS is:closed closed:>=$since $scope")" || die "search failed"
    n=0
    out_new=""; out_answered=""; out_closed=""
    while IFS=$'\t' read -r num url_ full kind title; do
      [[ -n "$num" ]] || continue
      rd="$(row_read "$full" "$num")"
      IFS=$'\t' read -r ev_at ev_kind < <(row_events "$rd")
      acks="$(seat_acks "$rd")"
      mine="$(printf '%s\n' "$acks" | awk -F'\t' -v s="$seat" '$1==s {print $2}')"
      if [[ -n "$mine" && ! "$mine" < "$ev_at" ]]; then continue; fi
      others="$(printf '%s\n' "$acks" | awk -F'\t' -v s="$seat" -v e="$ev_at" '$1!=s && $1!="" {printf "%s %s%s ", $1, ($2>=e?"✓":"—"), ($2>=e?$3:"")}')"
      line="  $kind $full#$num  $title  [$ev_kind $ev_at]  $url_${others:+  others: $others}"
      case "$ev_kind" in
        closed) out_closed="$out_closed$line"$'\n' ;;
        answered) out_answered="$out_answered$line"$'\n' ;;
        *) out_new="$out_new$line"$'\n' ;;
      esac
      n=$((n+1))
    done < <(jq -r '.[] | [.number, .html_url, (.repository_url | sub(".*/repos/"; "")), (if .pull_request then "PR" else "decision" end), (.title | sub("^Decision: "; ""))] | @tsv' <(jq -s 'add | unique_by(.html_url)' <(printf '%s\n' "$rows") <(printf '%s\n' "$closed")))
    if [[ $n -eq 0 ]]; then
      echo "board: nothing unacked for $seat (every decision or PR waiting on $seat carries its ack after the latest event)"
    else
      echo "board: unacked for $seat: $n row(s). Ack each with ack.sh <row> --seat $seat --state seen|executed|blocked --next \"<act>\" once acted on."
      [[ -z "$out_closed" ]] || { echo; echo "closed on the word (a PR: merged or rejected; read the close comment, execute, ack):"; printf '%s' "$out_closed"; }
      [[ -z "$out_answered" ]] || { echo; echo "answered by the decider, still open (approve on a PR: pr.sh close --merge; a revise: decision.sh revise <row>; a question back: reply on the row; then ack):"; printf '%s' "$out_answered"; }
      [[ -z "$out_new" ]] || { echo; echo "new rows naming you (read, ack seen):"; printf '%s' "$out_new"; }
    fi
    echo
    "$here/desk.sh" inbox "$seat"
    ;;
  record)
    newargs=(); words=""; rec=""; by=""; rejected=0; seatargs=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --words) words="$2"; shift 2 ;;
        --by) by="$2"; shift 2 ;;
        --rejected) rejected=1; shift ;;
        --record) rec="$2"; newargs+=(--record "$2"); shift 2 ;;
        --seat) seatargs+=(--seat "$2"); shift 2 ;;
        --hands|--project) die "record: a decided row carries no --hands or --project" ;;
        *) newargs+=("$1"); shift ;;
      esac
    done
    [[ -n "$words" && -n "$rec" && -n "$by" ]] || die "record needs --words, --record and --by besides the new row's fields"
    seat_id "$by" >/dev/null || exit 1   # a bad --by fails before the row is filed
    url="$("$0" new "${newargs[@]}" --by "$by" ${seatargs[@]+"${seatargs[@]}"} | tail -1)"
    [[ "$url" == https://github.com/* ]] || die "record: the row was not filed: $url"
    "$0" close "$url" --words "$words" --record "$rec" --by "$by" $([[ $rejected -eq 1 ]] && echo --rejected)
    ;;
  -h|--help|help)
    sed -n '2,/^source /p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    echo
    echo "A row's text (--title, the sections or --body-file) carries: $ASK_INLINE_RULE."
    exit 0 ;;
  *) die "usage: decision.sh new|close|revise|restore|record|inbox|--help — a row's text carries $ASK_INLINE_RULE" ;;
esac
