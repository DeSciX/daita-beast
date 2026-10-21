#!/usr/bin/env bash
# pr.sh — a pull request on the decider's board: request their word, then merge or reject on it.
#   pr.sh request <owner/repo#N | url> --seat <LABEL | login/LABEL> --unblocks "<text>" --recommendation "<text>"
#             [--assignee <login>] [--milestone "<title>"]
#       --unblocks and --recommendation are required (refused before any write when either is missing or empty, or
#       points elsewhere for its substance: ask_inline_check): they are written into the PR body as its `## Unblocks` and
#       `## Recommendation` sections (PR_ROW_SECTIONS, section_replace; a rerun replaces them), the sections board.sh and
#       the board page show on the PR's row, as a decision row's.
#       --milestone files the PR under that open milestone of its repo; required when the repo has any (milestone_require)
#       then labels the PR `needs-review` and seat:<login>/<LABEL> of the requesting seat (read back: seat_labels_require
#       dies when it did not land), assigns the decider (default: the roster's
#       people[] owner; dies when that is not exactly one login). Every seat posts as the decider's login
#       today, and GitHub refuses a review request to, or an approval by, a PR's own author, so the label
#       plus the assignee is the request; the decider answers with a comment, as on a decision.
#   pr.sh close <owner/repo#N | url> --words "<verbatim>" --record "<comment url | repo commit>" --by <LABEL | login/LABEL>
#             [--merge | --rejected] [--board <owner/repo>] [--next "<act>"]
#       --merge merges (REST PUT pulls/{n}/merge) and dies naming GitHub's refusal when it will not, and refuses while the
#       decider's revise: stands unanswered by decision.sh revise (row_revise_pending); --rejected
#       closes unmerged with the label `rejected`; neither: the PR must already be merged. Then the close
#       comment (row_close_comment, the one writer shared with decision.sh close: the words, the record and the
#       closer's BEAST-ACK seen line), the board republished, the row's seats printed.
# Both refuse a pull request in a public or public-intended repo before any write (coord_write_guard): the
# decider's word on a public product's PR is asked for on a row in its private twin.
# The PR's approving phrase is the first quoted phrase of a `## Approve with` section of its body, else
# `approve` (row_phrase); answers are the decision forms: the phrase, `<phrase> — <comment>`, bare
# approve/approved, `revise: …`, `reject: …`.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq

# pr_get <repo> <N>: the issue JSON of <repo>#<N>, dying unless it is a pull request.
pr_get() {
  local info; info="$(issue_get "$1" "$2")"
  jq -e '.pull_request != null' <<< "$info" >/dev/null || die "$1#$2 is an issue, not a pull request (a decision issue is closed with decision.sh close)"
  printf '%s\n' "$info"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  request)
    ref="${1:-}"; shift || true
    seat=""; assignee=""; ms=""; secs=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --seat) seat="$2"; shift 2 ;;
        --assignee) assignee="$2"; shift 2 ;;
        --milestone) ms="$2"; shift 2 ;;
        --unblocks) secs+=("Unblocks" "$2"); shift 2 ;;
        --recommendation) secs+=("Recommendation" "$2"); shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    usage="usage: pr.sh request <owner/repo#N | url> --seat <LABEL | login/LABEL> --unblocks \"<text>\" --recommendation \"<text>\" [--assignee <login>] [--milestone \"<title>\"]"
    [[ -n "$ref" && -n "$seat" ]] || die "$usage"
    # sec_text <section>: the text given for one of PR_ROW_SECTIONS (the last flag wins), or nothing.
    sec_text() { local i out=""; for ((i = 0; i < ${#secs[@]}; i += 2)); do [[ "${secs[$i]}" == "$1" ]] && out="${secs[$((i+1))]}"; done; printf '%s' "$out"; }
    for h in "${PR_ROW_SECTIONS[@]}"; do
      [[ -n "$(sec_text "$h" | tr -d '[:space:]')" ]] || die "pr.sh request needs --$(tr 'A-Z ' 'a-z-' <<< "$h") \"<text>\": a PR on the board carries a non-empty '## $h' as a decision row does; nothing was written. $usage"
      ask_inline_check "pr.sh request: --$(tr 'A-Z ' 'a-z-' <<< "$h")" "$(sec_text "$h")"
    done
    seat="$(seat_id "$seat")" || exit 1
    [[ -n "$assignee" ]] || assignee="$(roster_decider)" || exit 1
    rn="$(parse_issue_ref "$ref")" || exit 1; read -r repo number <<< "$rn"
    coord_write_guard "$repo" "$seat"
    info="$(pr_get "$repo" "$number")"
    [[ "$(jq -r .state <<< "$info")" == open ]] || die "$repo#$number is not open"
    [[ -z "$ms" ]] || milestone_title_check "$ms"
    msn="$(milestone_require "$repo" "$ms")" || exit 1
    # The body first, so a row is never on the board without its sections: each of PR_ROW_SECTIONS replaced (or appended).
    body="$(jq -r '.body // ""' <<< "$info")"
    for h in "${PR_ROW_SECTIONS[@]}"; do body="$(printf '%s\n' "$body" | section_replace "$h" "$(sec_text "$h")")" || die "$repo#$number: cannot write '## $h' into the body"; done
    for h in "${PR_ROW_SECTIONS[@]}"; do section_required "$h" "$body" "$repo#$number" >/dev/null; done
    tmp="$(mktemp)"; printf '%s\n' "$body" > "$tmp"
    issue_edit_body "$repo" "$number" "$tmp"; rm -f "$tmp"
    label_ensure_template "$repo" needs-review
    seat_label_ensure "$repo" "$seat"
    issue_add_labels "$repo" "$number" needs-review "seat:$seat"
    seat_labels_require "$repo" "$number" "$seat"
    issue_add_assignees "$repo" "$number" "$assignee"
    [[ -z "$msn" ]] || milestone_set "$repo" "$number" "$msn"
    # The requester's seen ack (ack_line, lib.sh): the seat is current on the row it put on the board, and the relay
    # never sends the request back to it (event_actors, lib.sh). A rerun posts it again; the newest ack stands.
    line="$(ack_line "$seat" seen "review requested; waits on the decider's word")" || exit 1
    issue_comment "$repo" "$number" "$line" >/dev/null || die "$repo#$number is requested but the requester's ack was NOT posted (named above): rerun pr.sh request"
    echo "requested: $(jq -r .html_url <<< "$info") labelled needs-review + seat:$seat, assigned $assignee; approves with \"$(row_phrase "$repo#$number" "$info")\""
    ;;
  close)
    ref="${1:-}"; shift || true
    words=""; rec=""; by=""; board=""; mode=""; next="execute on the words"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --words) words="$2"; shift 2 ;;
        --record) rec="$2"; shift 2 ;;
        --by) by="$2"; shift 2 ;;
        --board) board="$2"; shift 2 ;;
        --next) next="$2"; shift 2 ;;
        --merge|--rejected) [[ -z "$mode" ]] || die "--merge and --rejected exclude each other"; mode="${1#--}"; shift ;;
        *) die "unknown argument $1" ;;
      esac
    done
    [[ -n "$ref" && -n "$words" && -n "$rec" && -n "$by" ]] || die "usage: pr.sh close <pr> --words \"<verbatim>\" --record <url|commit> --by <SEAT> [--merge | --rejected]"
    by="$(seat_id "$by")" || exit 1
    [[ -n "$board" ]] || board="$(board_repo)"
    rn="$(parse_issue_ref "$ref")" || exit 1; read -r repo number <<< "$rn"
    coord_write_guard "$repo" "$by"
    info="$(pr_get "$repo" "$number")"
    merged_at="$(jq -r '.pull_request.merged_at // empty' <<< "$info")"
    case "$mode" in
      merge)
        [[ -z "$merged_at" ]] || die "$repo#$number was already merged at $merged_at: close it without --merge"
        [[ "$(jq -r .state <<< "$info")" == open ]] || die "$repo#$number is closed unmerged: reopen it before merging"
        pend="$(row_revise_pending "$(row_read "$repo" "$number")")" || exit 1
        [[ -z "$pend" ]] || revise_pending_refusal "$pend"
        sha="$(gh_send PUT "repos/$repo/pulls/$number/merge" | jq -r .sha)" || die "$repo#$number: GitHub refused the merge (named above) — nothing was commented or closed"
        echo "merged $repo#$number at $sha"
        row_close_comment "$repo" "$number" "$words" "$rec" "$by" "$next" closed
        ;;
      rejected)
        [[ -z "$merged_at" ]] || die "$repo#$number was merged at $merged_at: a merged PR cannot be rejected (revert it in a new PR)"
        row_close_comment "$repo" "$number" "$words" "$rec" "$by" "$next" rejected
        row_mark_rejected "$repo" "$number"
        gh_send PATCH "repos/$repo/pulls/$number" -f state=closed >/dev/null || die "$repo#$number: cannot close the pull request"
        echo "closed unmerged $repo#$number (rejected)"
        ;;
      "")
        [[ -n "$merged_at" ]] || die "$repo#$number is not merged: pass --merge to merge it on the words, or --rejected to close it unmerged"
        row_close_comment "$repo" "$number" "$words" "$rec" "$by" "$next" closed
        echo "recorded the words on $repo#$number (merged at $merged_at)"
        ;;
    esac
    row_after_close "$repo" "$number" "$by" "$board"
    ;;
  *) die "usage: pr.sh request|close (see the header of $0)" ;;
esac
