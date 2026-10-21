#!/usr/bin/env bash
# wrapup.sh — wrap up a milestone of a private repo: release notes for outside readers, the closed decisions folded into
# the docs, then the coordination traffic of the milestone deleted, so the board starts the next milestone clean.
# Run in a checkout of the repo (the twin). Default repo: the roster "repo" (the home).
#
#   wrapup.sh plan "<milestone>" [--repo <owner/repo>] [--carry "<next milestone>"]
#       writes the plan to .beast/wrapup/<slug>/plan.json in the checkout and prints it; posts nothing. The plan lists
#       exactly what a run deletes: the closed decision rows and the closed PR rows' coordination comments (BEAST- lines
#       and close comments) under the milestone; on the repo's desks, the asks answered or withdrawn (the ask and its
#       answer: those under the milestone, and those under none answered before the plan) and the messages older than
#       the plan; on the tracking issues of the repo's seats, the BEAST-STATUS and BEAST-ACK comments older than the
#       plan except each seat's newest handoff (BEAST-NOTES and the watchdog's BEAST-WATCHDOG-NOTES are never deleted, and the plan
#       lists them under keep); the record files (RECORD_PATH_RE) named on
#       the closed rows that exist in the repo; and the plan's own directory. What it keeps: the open items (carried to
#       --carry, by default the soonest other open milestone; the plan refuses open items with nowhere to carry them).
#       What the fold-in must cover: each closed row's title, words and record, and the milestone's Report: line.
#   wrapup.sh request "<milestone>" --seat <SEAT> [--repo <owner/repo>] [--milestone "<row's milestone>"]
#       commits the plan file to the repo's default branch (the contents API: that one path, nothing else) and files ONE
#       decision row in the repo, approved with "wrap up <milestone>", whose Decision links the plan at that commit
#       with its digest. The row's milestone defaults to the plan's carry milestone, else the milestone itself.
#   wrapup.sh brief "<milestone>" [--repo <owner/repo>]
#       what the fold-in must cover (the realign skill, scope b): each closed row's url, title, words and record.
#   wrapup.sh notes "<milestone>" [--repo <owner/repo>]
#       the generated release notes (merged PRs, approved decisions, outside contributors), to edit and pass to run.
#   wrapup.sh run "<milestone>" --words "<verbatim approve>" --by <SEAT> --fold-in <sha> [--notes <f>] [--tag <tag>] [--repo <owner/repo>]
#       refuses unless the decider's standing answer on the row approves (row_answer_url) and the words do; reads the
#       plan the row links and refuses unless its digest matches; refuses unless every closed row of the plan is cited
#       by its url in the fold-in commit's message or listed "dropped: <url> — <why>" in .beast/wrapup/<slug>/fold-in.md
#       at that commit, and unless the release notes pass the scrub gate. Only then does it write: (1) the release on the
#       publishes_to repo through publish.sh release (printed when the roster has no pair); (2) the deletes, each through
#       wrapup_delete and logged: issues by GraphQL deleteIssue, comments by REST, files in one commit on the default
#       branch; (3) the touched desks republished; (4) the milestone closed, open items carried; (5) one comment on --by's
#       tracking issue, "milestone <M> closed: <release link>, <n> rows folded" (once); (6) the row closed on the words
#       (the board republishes); (7) the DeSciX KB manifests whose sources cover a changed file, with the sync command.
# Deleting an issue needs admin rights and cannot be undone: nothing is deleted that the approved plan does not list, and
# every delete re-reads its target and asserts it belongs to the plan's repo.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq git python3
here="$(dirname "${BASH_SOURCE[0]}")"

PLAN_SHAPE="beast-wrapup-plan/1"
WRAPUP_DIR=".beast/wrapup"

# ---- names: the one owner of every path and title the wrap-up uses -------------------------------------------
ms_slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
wrapup_dir() { echo "$WRAPUP_DIR/$(ms_slug "$1")"; }
plan_file() { echo "$(wrapup_dir "$1")/plan.json"; }
manifest_file() { echo "$(wrapup_dir "$1")/fold-in.md"; }
wrapup_row_title() { echo "Decision: Wrap up $1"; }
wrapup_phrase() { echo "wrap up $1"; }
lc() { tr 'A-Z' 'a-z' <<< "$1"; }

# contents_path, default_branch and gh_status_of live in lib.sh (the workstream block render shares them).

# ---- the plan: the one owner of its shape --------------------------------------------------------------------
# plan_build <repo> <title> <carry | "">: the plan as JSON on stdout. Reads only; every read through gh_get.
plan_build() {
  local repo="$1" title="$2" carry="$3" m num cutoff db tmp items rd n
  m="$(milestone_get "$repo" "$title")" || exit 1
  [[ "$(jq -r .state <<< "$m")" == open ]] || die "milestone \"$title\" of $repo is closed: a wrap-up plans an open milestone (its close is the run's last act)"
  num="$(jq -r .number <<< "$m")"; cutoff="$(utc_now)"; db="$(default_branch "$repo")" || exit 1
  tmp="$(mktemp -d)"
  : > "$tmp/issues"; : > "$tmp/comments"; : > "$tmp/files"; : > "$tmp/keep"; : > "$tmp/fold"; : > "$tmp/merged"
  items="$(issues_list "$repo" -f milestone="$num" -f state=all)" || die "cannot list the items of milestone \"$title\" in $repo"
  local open_n=0
  while IFS= read -r it; do
    [[ -n "$it" ]] || continue
    n="$(jq -r .number <<< "$it")"
    local kind state url ttl
    kind="$(jq -r 'if .pull_request then "PR" else "issue" end' <<< "$it")"; state="$(jq -r .state <<< "$it")"
    url="$(jq -r .html_url <<< "$it")"; ttl="$(jq -r .title <<< "$it")"
    if [[ "$kind" == PR ]] && jq -e '.pull_request.merged_at' <<< "$it" >/dev/null; then jq -c '{number, url: .html_url, title}' <<< "$it" >> "$tmp/merged"; fi
    if [[ "$state" == open ]]; then
      open_n=$((open_n+1)); jq -nc --arg u "$url" --arg w "open $kind \"$ttl\": carried forward" '{url: $u, why: $w}' >> "$tmp/keep"; continue
    fi
    local row=""
    if [[ "$kind" == issue ]] && jq -e 'any(.labels[]; .name == "decision")' <<< "$it" >/dev/null; then row=decision
    elif [[ "$kind" == PR ]] && jq -e 'any(.labels[]; .name == "needs-review")' <<< "$it" >/dev/null; then row=PR; fi
    if [[ -z "$row" ]]; then jq -nc --arg u "$url" --arg w "closed $kind \"$ttl\", not a board row" '{url: $u, why: $w}' >> "$tmp/keep"; continue; fi
    rd="$(row_read "$repo" "$n")" || exit 1
    # the words and the record: the newest close comment's (close_last, lib.sh; a latitude close has no words, its record
    # the link in its close line), else the body's ## Record
    tag_jq -c --arg row "$row" '
      close_last(.comments) as $c
      | {url: .issue.html_url, number: .issue.number, title: .issue.title, kind: $row,
         state: (if $row == "PR" then (if .issue.pull_request.merged_at then "merged" else "closed unmerged" end)
                 else (if (.issue.state_reason == "not_planned" or any(.issue.labels[]; .name == "rejected")) then "rejected" else "closed" end) end),
         words: ($c.words // null),
         record: ($c.record // null),
         node_id: .issue.node_id}' <<< "$rd" > "$tmp/row"
    if [[ "$(jq -r .record "$tmp/row")" == null ]]; then
      jq -c --arg r "$(jq -r '.issue.body // ""' <<< "$rd" | section Record | sed '/^[[:space:]]*$/d')" '.record = (if $r == "" then null else $r end)' "$tmp/row" > "$tmp/row2" && mv "$tmp/row2" "$tmp/row"
    fi
    jq -c 'del(.node_id)' "$tmp/row" >> "$tmp/fold"
    if [[ "$row" == decision ]]; then
      jq -c '{number, url, node_id, title, why: "closed decision row (\(.state))"}' "$tmp/row" >> "$tmp/issues"
    else
      tag_jq -c --arg u "$url" '.comments[] | select(((.body // "") | test("^BEAST-[A-Z]+ ")) or close_of(.body) != null) | {id, url: .html_url, on: $u, why: "PR row: \((.body // "") | split("\n")[0] | .[:60])"}' <<< "$rd" >> "$tmp/comments"
      local phrase asg cid curl clogin cfirst
      phrase="$(row_phrase "$repo#$n" "$(jq -c .issue <<< "$rd")" 2>/dev/null)" || true
      asg="$(jq -r '[.issue.assignees[].login] | join(" ")' <<< "$rd")"
      while IFS=$'\t' read -r cid curl clogin cfirst; do
        [[ -n "$cid" && " $asg " == *" $clogin "* && -n "$(answer_kind "$cfirst" "$phrase")" ]] || continue
        jq -nc --argjson i "$cid" --arg c "$curl" --arg u "$url" --arg f "${cfirst:0:60}" '{id: $i, url: $c, on: $u, why: "PR row: the decider'"'"'s answer \"\($f)\""}' >> "$tmp/comments"
      done < <(jq -r '.comments[] | [.id, .html_url, .user.login, ((.body // "") | split("\n")[0])] | @tsv' <<< "$rd")
    fi
    # record files named on the row that exist in this repo (the dated records only)
    local p st info
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      st="$(gh_status_of "repos/$repo/contents/$(contents_path "$p")?ref=$(uri "$db")")" || exit 1
      [[ "$st" == 200 ]] || continue
      info="$(gh_get "repos/$repo/contents/$(contents_path "$p")?ref=$(uri "$db")")" || exit 1
      jq -e 'type == "object" and .type == "file"' <<< "$info" >/dev/null || continue
      jq -c --arg u "$url" '{path, sha, named_on: $u}' <<< "$info" >> "$tmp/files"
    done < <( { jq -r '.record // ""' "$tmp/row"; jq -r '.issue.body // ""' <<< "$rd" | section Record; } | python3 -I -c '
import re, sys
repo, rec = sys.argv[1].lower(), sys.argv[2]
text, out = sys.stdin.read(), []
for m in re.finditer(r"https://github\.com/([^/\s]+/[^/\s]+)/(?:blob|tree)/[^/\s]+/([^\s)\]>\"\x27`,;]+)", text):
    if m.group(1).lower() == repo: out.append(m.group(2))
text = re.sub(r"https?://\S+", " ", text)
for m in re.finditer(r"(?<![A-Za-z0-9_./-])(?:\./)?([A-Za-z0-9_.-][A-Za-z0-9_./-]*)", text):
    out.append(m.group(1).rstrip(".,;:"))
for p in dict.fromkeys(out):
    if re.search(rec, p): print(p)
' "$repo" "$RECORD_PATH_RE")
  done < <(jq -c '.[]' <<< "$items")
  # the desks of the repo
  local d seat parsed open_asks
  while IFS=$'\t' read -r d seat; do
    [[ -n "$d" ]] || continue
    [[ -n "$seat" && "$seat" != *' '* ]] || die "$repo#$d is a desk without exactly one seat: label"
    parsed="$(desk_parse "$seat" "$(row_read "$repo" "$d")")" || exit 1
    jq -c --arg t "$title" --arg cut "$cutoff" --arg s "$seat" --arg d "$d" '
      def cid: capture("#issuecomment-(?<i>[0-9]+)$").i | tonumber;
      (.asks[] | select(.state != "open" and (.milestone == $t or (.milestone == null and .answer.at <= $cut)))
        | (.url, .answer.url) as $u | {id: ($u | cid), url: $u, on: "desk \($s)", why: "ask n=\(.n) \(.state)\(if .milestone then " under \"\(.milestone)\"" else ", no milestone" end)"}),
      (.messages[] | select(.at < $cut) | {id: (.url | cid), url, on: "desk \($s)", why: "message from \(.from) at \(.at)"})' <<< "$parsed" >> "$tmp/comments"
    open_asks="$(jq -c --arg t "$title" --arg s "$seat" '.asks[] | select(.state == "open" and .milestone == $t) | {url, why: "open ask n=\(.n) on the desk of \($s): carried forward"}' <<< "$parsed")"
    if [[ -n "$open_asks" ]]; then printf '%s\n' "$open_asks" >> "$tmp/keep"; open_n=$((open_n + $(wc -l <<< "$open_asks"))); fi
    jq -nc --arg s "$seat" --arg d "$d" --arg r "$repo" '{desk: $s, url: "https://github.com/\($r)/issues/\($d)"}' >> "$tmp/desks"
  done < <(issues_list "$repo" -f labels=desk -f state=open | jq -r '.[] | select(.pull_request == null) | [.number, ([.labels[].name | select(startswith("seat:")) | ltrimstr("seat:")] | join(" "))] | @tsv')
  [[ -f "$tmp/desks" ]] || : > "$tmp/desks"
  # the tracking issues of the repo's seats
  local tr tn cs
  while IFS= read -r tr; do
    [[ -n "$tr" ]] || continue
    read -r _ tn < <(parse_issue_ref "$tr")
    cs="$(issue_comments "$repo" "$tn")" || die "cannot read the comments of $tr"
    jq -c --arg cut "$cutoff" --arg tr "$tr" '
      [.[] | {id, url: .html_url, at: .created_at, first: ((.body // "") | split("\n")[0])}] as $all
      | ([$all[] | select(.first | test("^BEAST-STATUS seat=\\S+ at=\\S+ state=handoff( |$)")) | . + {seat: (.first | capture("^BEAST-STATUS seat=(?<s>\\S+)").s)}]
         | group_by(.seat) | map(max_by(.at) | .id)) as $newest
      | ($all[] | select((.first | test("^BEAST-(STATUS|ACK) ")) and .at <= $cut)
         | .id as $i | if any($newest[]; . == $i) then {keep: {url, why: "the newest handoff of \(.first | capture("seat=(?<s>\\S+)").s)"}}
           else {del: {id, url, on: $tr, why: (.first | .[:60])}} end),
        ($all[] | select(.first | test("^BEAST-(NOTES|WATCHDOG-NOTES) ")) | {keep: {url, why: "notes, kept across milestones: \(.first | .[:60])"}})' <<< "$cs" > "$tmp/t"
    jq -c 'select(.del) | .del' "$tmp/t" >> "$tmp/comments"
    jq -c 'select(.keep) | .keep' "$tmp/t" >> "$tmp/keep"
  done < <(jq -r --arg r "$(lc "$repo")" '[.seats[]? | select((.repo // "" | ascii_downcase) == $r) | .workstream] | unique | .[]' "$(roster_path)" \
           | while IFS= read -r w; do t="$(workstream_issue "$w")" || exit 1; [[ "$(lc "${t%%#*}")" == "$(lc "$repo")" ]] && echo "$t"; done)
  # where open items go
  if [[ $open_n -gt 0 && -z "$carry" ]]; then
    carry="$(milestone_all "$repo" open | jq -r --arg t "$title" '[.[] | select(.title != $t)] | sort_by(.due_on // "9999") | .[0].title // empty')" || exit 1
    [[ -n "$carry" ]] || { rm -rf "$tmp"; die "milestone \"$title\" has $open_n open item(s) and $repo has no other open milestone to carry them to: set the next one first (milestone.sh new)"; }
  fi
  [[ -z "$carry" ]] || { milestone_require "$repo" "$carry" >/dev/null || exit 1; [[ "$carry" != "$title" ]] || die "--carry names the milestone being wrapped up"; }
  jq -n --arg shape "$PLAN_SHAPE" --arg repo "$repo" --argjson m "$m" --arg cut "$cutoff" --arg carry "$carry" --arg db "$db" \
    --arg dir "$(wrapup_dir "$title")" --arg man "$(manifest_file "$title")" --arg rep "$(milestone_field "$m" Report)" \
    --slurpfile issues "$tmp/issues" --slurpfile comments "$tmp/comments" --slurpfile files "$tmp/files" \
    --slurpfile keep "$tmp/keep" --slurpfile fold "$tmp/fold" --slurpfile merged "$tmp/merged" --slurpfile desks "$tmp/desks" '
    {shape: $shape, repo: $repo, default_branch: $db,
     milestone: {title: $m.title, number: $m.number, url: $m.html_url, due: ($m.due_on // "" | .[:10])},
     cutoff: $cut, carry: (if $carry == "" then null else $carry end),
     delete: {issues: ($issues | unique_by(.number)), comments: ($comments | unique_by(.id)), files: ($files | unique_by(.path)), dir: $dir},
     keep: $keep, desks: ($desks | unique_by(.desk)),
     fold_in: {rows: $fold, report: (if $rep == "" then null else $rep end), manifest: $man},
     release: {merged_prs: ($merged | unique_by(.number))}}'
  rm -rf "$tmp"
}

# plan_check <plan-json> <repo> <title>: dies unless it is a plan of this shape, repo and milestone.
plan_check() {
  jq -e --arg s "$PLAN_SHAPE" --arg r "$(lc "$2")" --arg t "$3" '.shape == $s and (.repo | ascii_downcase) == $r and .milestone.title == $t
    and (.delete.issues | type) == "array" and (.delete.comments | type) == "array" and (.delete.files | type) == "array"
    and (.fold_in.rows | type) == "array"' <<< "$1" >/dev/null \
    || die "not a $PLAN_SHAPE plan of milestone \"$3\" in $2"
}

# plan_show <plan-json>: the plan for a human, one line per item.
plan_show() {
  jq -r '
    "Wrap-up plan: milestone \"\(.milestone.title)\" of \(.repo) (\(.milestone.url)), cutoff \(.cutoff)\(if .carry then ", open items carried to \"\(.carry)\"" else "" end)",
    "",
    "DELETE \(.delete.issues | length) issue(s):", (.delete.issues[] | "  \(.url)  \(.title)  [\(.why)]"),
    "DELETE \(.delete.comments | length) comment(s):", (.delete.comments[] | "  \(.url)  [\(.on): \(.why)]"),
    "DELETE \(.delete.files | length) record file(s), and the directory \(.delete.dir)/ (this plan, the fold-in manifest):", (.delete.files[] | "  \(.path)  [named on \(.named_on)]"),
    "",
    "KEEP \(.keep | length):", (.keep[] | "  \(.url)  [\(.why)]"),
    "",
    "FOLD IN \(.fold_in.rows | length) closed row(s) (cite each url in the fold-in commit message, or \"dropped: <url> — <why>\" in \(.fold_in.manifest)):",
    (.fold_in.rows[] | "  \(.url)  \(.title)  [\(.state)]\n    words: \(.words // "(none on the row)")\n    record: \(.record // "(none)")"),
    "  Report: \(.fold_in.report // "(the milestone carries no Report: line)")",
    "",
    "RELEASE NOTES from \(.release.merged_prs | length) merged PR(s) and the approved decisions"' <<< "$1"
}

# plan_ref_lines <blob url> <digest>: the two lines of the row's Decision that name the approved plan; plan_ref_read reads them.
plan_ref_lines() { printf 'Plan: %s\nPlan digest: sha256:%s\n' "$1" "$2"; }
plan_ref_read() {   # <row body> -> "<blob url> <digest>"
  local u d
  u="$(sed -nE 's#^Plan: (https://github\.com/[^ ]+)$#\1#p' <<< "$1" | head -1)"
  d="$(sed -nE 's#^Plan digest: sha256:([0-9a-f]{40})$#\1#p' <<< "$1" | head -1)"
  [[ -n "$u" && -n "$d" ]] || die "the wrap-up row carries no 'Plan: <url>' and 'Plan digest: sha256:<hex>' lines"
  echo "$u $d"
}

# wrapup_row <repo> <title>: the open wrap-up row's number, or nothing; dies when there are two.
wrapup_row() {
  local got
  got="$(issues_list "$1" -f labels=decision -f state=open | jq -r --arg t "$(wrapup_row_title "$2")" '[.[] | select(.pull_request == null and .title == $t) | .number] | join(" ")')" || die "cannot list the open decision rows of $1"
  [[ "$got" != *" "* ]] || die "several open rows \"$(wrapup_row_title "$2")\" in $1: #${got// /, #}; close the extra ones"
  echo "$got"
}

# plan_from_row <repo> <row number>: the approved plan's JSON, read at the commit the row links; dies unless its digest matches.
plan_from_row() {
  local repo="$1" n="$2" body ref u d sha path got
  body="$(issue_get "$repo" "$n" | jq -r '.body // ""')" || exit 1
  ref="$(plan_ref_read "$body")" || exit 1; read -r u d <<< "$ref"
  [[ "$u" =~ ^https://github\.com/([^/]+/[^/]+)/blob/([0-9a-f]{40})/(.+)$ ]] || die "the plan link $u is not a blob at a commit"
  [[ "$(lc "${BASH_REMATCH[1]}")" == "$(lc "$repo")" ]] || die "the plan link $u is not in $repo"
  sha="${BASH_REMATCH[2]}"; path="${BASH_REMATCH[3]}"
  got="$(gh_get "repos/$repo/contents/$(contents_path "$path")?ref=$sha" | python3 -I -c 'import sys, json, base64; sys.stdout.write(base64.b64decode(json.load(sys.stdin)["content"]).decode("utf-8"))')" \
    || die "cannot read the plan $u"
  [[ "$(beast_sha "$got")" == "$d" ]] || die "the plan at $u does not carry the digest the row names (sha256:$d): the plan was changed after it was filed"
  printf '%s\n' "$got"
}

# plan_load <repo> <title>: the plan of the open wrap-up row when there is one, else the local plan file.
plan_load() {
  local n f; n="$(wrapup_row "$1" "$2")" || exit 1
  if [[ -n "$n" ]]; then plan_from_row "$1" "$n"; return; fi
  f="$(repo_root)/$(plan_file "$2")"
  [[ -f "$f" ]] || die "no open wrap-up row for \"$2\" in $1 and no plan at $f: wrapup.sh plan \"$2\" first"
  cat "$f"
}

# notes_render <plan-json> <repo> <title>: the release notes for outside readers: merged PRs, approved decisions (titles
# only: a private row's link never leaves the twin), outside contributors (report.sh milestone --outside-notes).
notes_render() {
  local outside
  outside="$("$here/report.sh" milestone "$3" --repo "$2" --outside-notes)" || die "report.sh milestone --outside-notes failed (named above)"
  jq -r '
    "## \(.milestone.title)", "",
    (if (.release.merged_prs | length) > 0 then ("### Changes", "", (.release.merged_prs[] | "- \(.title)"), "") else empty end),
    ([.fold_in.rows[] | select(.kind == "decision" and .state == "closed")] as $d
      | if ($d | length) > 0 then ("### Decided", "", ($d[] | "- \(.title | sub("^Decision: "; ""))"), "") else empty end),
    (if (.release.merged_prs | length) == 0 and ([.fold_in.rows[] | select(.kind == "decision" and .state == "closed")] | length) == 0 then ("No changes in this milestone.", "") else empty end)' <<< "$1"
  [[ -z "$outside" ]] || printf '%s\n' "$outside"
}

# ---- deletes: the one owner -----------------------------------------------------------------------------------
# wrapup_delete <plan repo> issue <repo> <number> <node id>
# wrapup_delete <plan repo> comment <repo> <comment id>
# wrapup_delete <plan repo> files <repo> <branch> <message> <path>...
# Every delete of the plugin. It asserts the target repo is the plan's repo, re-reads the target and asserts it is what the
# plan names (an issue: closed, same node; a comment: on an issue of that repo; a file: present), deletes, and logs one line
# to stdout and to $WRAPUP_LOG. A target already gone (404 or 410) is logged as such and is not an error, so a rerun
# finishes what an interrupted run began.
wrapup_delete() {
  local plan_repo="$1" kind="$2" repo="$3" line st info
  [[ -n "$plan_repo" && "$(lc "$repo")" == "$(lc "$plan_repo")" ]] || die "wrapup_delete: refused: the target repo '$repo' is not the plan's repo '$plan_repo'"
  case "$kind" in
    issue)
      local n="$4" node="$5"
      [[ "$n" =~ ^[0-9]+$ && -n "$node" ]] || die "wrapup_delete issue: needs <number> <node id>"
      st="$(gh_status_of "repos/$repo/issues/$n")" || exit 1
      if [[ "$st" == 404 || "$st" == 410 ]]; then line="already gone ($st): issue $repo#$n"
      else
        [[ "$st" == 200 ]] || die "wrapup_delete: cannot read $repo#$n (HTTP $st)"
        info="$(gh_get "repos/$repo/issues/$n")" || exit 1
        [[ "$(jq -r .node_id <<< "$info")" == "$node" ]] || die "wrapup_delete: $repo#$n is not the issue the plan names (node $(jq -r .node_id <<< "$info"), the plan's $node)"
        [[ "$(jq -r .state <<< "$info")" == closed ]] || die "wrapup_delete: $repo#$n is open: an open issue is never deleted"
        [[ "$(lc "$(jq -r '.repository_url | sub(".*/repos/"; "")' <<< "$info")")" == "$(lc "$plan_repo")" ]] || die "wrapup_delete: $repo#$n answers as an issue of another repo"
        gh_send POST graphql -f query='mutation($id:ID!){ deleteIssue(input:{issueId:$id}){ clientMutationId } }' -F id="$node" >/dev/null
        line="deleted issue $repo#$n ($(jq -r .title <<< "$info"))"
      fi ;;
    comment)
      local id="$4"
      [[ "$id" =~ ^[0-9]+$ ]] || die "wrapup_delete comment: '$id' is not a comment id"
      st="$(gh_status_of "repos/$repo/issues/comments/$id")" || exit 1
      if [[ "$st" == 404 || "$st" == 410 ]]; then line="already gone ($st): comment $id of $repo"
      else
        [[ "$st" == 200 ]] || die "wrapup_delete: cannot read the comment $id of $repo (HTTP $st)"
        info="$(gh_get "repos/$repo/issues/comments/$id")" || exit 1
        [[ "$(lc "$(jq -r .issue_url <<< "$info")")" == "https://api.github.com/repos/$(lc "$plan_repo")/issues/"* ]] || die "wrapup_delete: comment $id is not on an issue of $plan_repo ($(jq -r .issue_url <<< "$info"))"
        gh_send DELETE "repos/$repo/issues/comments/$id" >/dev/null
        line="deleted comment $(jq -r .html_url <<< "$info") ($(jq -r '(.body // "") | split("\n")[0] | .[:60]' <<< "$info"))"
      fi ;;
    files)
      local br="$4" msg="$5" p head tree j present=() newtree commit; shift 5
      [[ -n "$br" && -n "$msg" ]] || die "wrapup_delete files: needs <branch> <message> <path>..."
      for p in "$@"; do
        st="$(gh_status_of "repos/$repo/contents/$(contents_path "$p")?ref=$(uri "$br")")" || exit 1
        if [[ "$st" == 200 ]]; then present+=("$p"); else echo "already gone ($st): $repo:$p" | tee -a "$WRAPUP_LOG"; fi
      done
      [[ ${#present[@]} -gt 0 ]] || return 0
      head="$(gh_get "repos/$repo/git/ref/heads/$br" | jq -er .object.sha)" || die "cannot read $repo $br"
      tree="$(gh_get "repos/$repo/git/commits/$head" | jq -er .tree.sha)" || die "cannot read the commit $head of $repo"
      j="$(mktemp)"
      printf '%s\n' "${present[@]}" | jq -R . | jq -s --arg t "$tree" '{base_tree: $t, tree: map({path: ., mode: "100644", type: "blob", sha: null})}' > "$j"
      newtree="$(gh_send POST "repos/$repo/git/trees" --input "$j" | jq -er .sha)" || die "cannot write the tree of the deletion"
      jq -n --arg m "$msg" --arg t "$newtree" --arg h "$head" '{message: $m, tree: $t, parents: [$h]}' > "$j"
      commit="$(gh_send POST "repos/$repo/git/commits" --input "$j" | jq -er .sha)" || die "cannot write the deletion commit"
      rm -f "$j"
      gh_send PATCH "repos/$repo/git/refs/heads/$br" -f sha="$commit" >/dev/null || die "cannot move $repo $br to the deletion commit $commit (it moved since $head?): nothing was deleted from the branch"
      for p in "${present[@]}"; do echo "deleted file $repo:$p (commit $commit)" | tee -a "$WRAPUP_LOG"; done
      return 0 ;;
    *) die "wrapup_delete: kind is issue, comment or files, not '$kind'" ;;
  esac
  echo "$line" | tee -a "$WRAPUP_LOG"
}

# ---- verbs ----------------------------------------------------------------------------------------------------
cmd="${1:-}"; shift || true
case "$cmd" in plan|request|brief|notes|run) ;; *) die "usage: wrapup.sh plan|request|brief|notes|run \"<milestone>\" … (see the header of $0)" ;; esac
title="${1:-}"; shift || true
milestone_title_check "$title"
repo=""; carry=""; seat=""; rms=""; words=""; by=""; fold=""; notes=""; tag=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --carry) carry="$2"; shift 2 ;;
    --seat) seat="$2"; shift 2 ;;
    --milestone) rms="$2"; shift 2 ;;
    --words) words="$2"; shift 2 ;;
    --by) by="$2"; shift 2 ;;
    --fold-in) fold="$2"; shift 2 ;;
    --notes) notes="$2"; shift 2 ;;
    --tag) tag="$2"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$repo" ]] || repo="$(roster_repo)" || exit 1
root="$(repo_root)"
[[ "$(lc "$(repo_slug "$root")")" == "$(lc "$repo")" ]] || die "wrapup.sh runs in a checkout of $repo; $root is $(repo_slug "$root")"
coord_write_guard "$repo"

case "$cmd" in
  plan)
    plan="$(plan_build "$repo" "$title" "$carry")" || exit 1
    f="$root/$(plan_file "$title")"
    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$(jq . <<< "$plan")" > "$f"
    plan_show "$plan"
    echo
    echo "plan written to $f (posted nowhere). Next: wrapup.sh request \"$title\" --seat <SEAT>"
    ;;
  brief)
    plan="$(plan_load "$repo" "$title")" || exit 1; plan_check "$plan" "$repo" "$title"
    jq -r '
      "Fold-in brief: milestone \"\(.milestone.title)\" of \(.repo). Run the realign skill (scope b) on this repo:",
      "fold each closed row below into the as-built docs and the instruction surfaces as current truth, delete what it",
      "supersedes, and commit the doc changes (one fold-in commit, pushed to \(.default_branch)). In that commit message, cite the",
      "url of every row you folded. A row that leaves nothing to fold (superseded, rejected, a one-off act) is listed in",
      "\(.fold_in.manifest), committed in the same commit, as one line \"dropped: <url> — <why>\".",
      "A red-team or investigation record survives only if you write its useful content into docs here: its file is deleted.",
      "",
      (.fold_in.rows[] | "\(.url)\n  \(.title)  [\(.kind), \(.state)]\n  words: \(.words // "(none on the row)")\n  record: \(.record // "(none)")\n"),
      "Report: \(.fold_in.report // "(the milestone carries no Report: line)")",
      "",
      "Then: wrapup.sh run \"\(.milestone.title)\" --words \"<the decider'"'"'s words>\" --by <SEAT> --fold-in <sha>"' <<< "$plan"
    ;;
  notes)
    plan="$(plan_load "$repo" "$title")" || exit 1; plan_check "$plan" "$repo" "$title"
    notes_render "$plan" "$repo" "$title"
    ;;
  request)
    [[ -n "$seat" ]] || die "usage: wrapup.sh request \"<milestone>\" --seat <SEAT> [--repo <owner/repo>] [--milestone \"<row's milestone>\"]"
    seat="$(seat_rostered "$seat")" || exit 1
    decider="$(roster_decider)" || exit 1
    f="$root/$(plan_file "$title")"
    [[ -f "$f" ]] || die "no plan at $f: wrapup.sh plan \"$title\" first"
    plan="$(cat "$f")"; plan_check "$plan" "$repo" "$title"
    w="$(wrapup_row "$repo" "$title")" || exit 1
    [[ -z "$w" ]] || die "an open wrap-up row for \"$title\" exists in $repo (#$w): answer or close it before filing another"
    [[ "$(gh_get "repos/$repo/milestones/$(jq -r .milestone.number <<< "$plan")" | jq -r .state)" == open ]] || die "milestone \"$title\" of $repo is no longer open"
    [[ -n "$rms" ]] || rms="$(jq -r '.carry // .milestone.title' <<< "$plan")"
    milestone_require "$repo" "$rms" >/dev/null || exit 1
    db="$(default_branch "$repo")" || exit 1
    path="$(plan_file "$title")"; enc="$(contents_path "$path")"
    args=(-f message="wrap-up plan: milestone \"$title\" (wrapup.sh plan; deleted by the wrap-up itself)" -f branch="$db" -f content="$(base64 < "$f" | tr -d '\n')")
    st="$(gh_status_of "repos/$repo/contents/$enc?ref=$(uri "$db")")" || exit 1
    [[ "$st" != 200 ]] || args+=(-f sha="$(gh_get "repos/$repo/contents/$enc?ref=$(uri "$db")" | jq -r .sha)")
    commit="$(gh_send PUT "repos/$repo/contents/$enc" "${args[@]}" | jq -er .commit.sha)" || die "cannot commit the plan to $repo $db"
    blob="https://github.com/$repo/blob/$commit/$path"
    digest="$(beast_sha "$plan")"
    counts="$(jq -r '"\(.delete.issues | length) issue(s), \(.delete.comments | length) comment(s), \(.delete.files | length) record file(s)"' <<< "$plan")"
    url="$("$here/decision.sh" new --repo "$repo" --title "$(wrapup_row_title "$title")" --assignee "$decider" --by "$seat" --milestone "$rms" \
      --decision "Wrap up milestone \"$title\" of $repo: publish its release notes, fold its $(jq '.fold_in.rows | length' <<< "$plan") closed row(s) into the docs, then delete $counts and the plan's own directory, listed in the plan. Deleting an issue cannot be undone.
$(plan_ref_lines "$blob" "$digest")" \
      --unblocks "the wrap-up run: release notes, the deletes, the milestone's close$(jq -r 'if .carry then " (open items carried to \"\(.carry)\")" else "" end' <<< "$plan")" \
      --waits "your review of the plan" \
      --recommendation "Approve when every listed item may go: what is kept is listed under KEEP, and the fold-in must cite or drop each closed row before anything is deleted." \
      --approve-with "$(wrapup_phrase "$title")" \
      --record "$blob" | tail -1)" || exit 1
    rm -f "$f"; rmdir "$(dirname "$f")" 2>/dev/null || true
    echo "plan committed: $blob (sha256:$digest); the local copy is removed (git pull brings it)"
    echo "row: $url"
    ;;
  run)
    [[ -n "$words" && -n "$by" && -n "$fold" ]] || die "usage: wrapup.sh run \"<milestone>\" --words \"<verbatim approve>\" --by <SEAT> --fold-in <sha> [--notes <f>] [--tag <tag>] [--repo <owner/repo>]"
    by="$(seat_rostered "$by")" || exit 1
    coord_write_guard "$repo" "$by"
    phrase="$(wrapup_phrase "$title")"
    [[ "$(answer_kind "$words" "$phrase")" == approve ]] || die "refused: the words \"$words\" do not approve \"$phrase\""
    row="$(wrapup_row "$repo" "$title")" || exit 1
    [[ -n "$row" ]] || die "refused: no open row \"$(wrapup_row_title "$title")\" in $repo (wrapup.sh request files it)"
    rec="$(row_answer_url "$(row_read "$repo" "$row")" "$phrase" approve)" || exit 1
    [[ -n "$rec" ]] || die "refused: $repo#$row is not approved: the decider's standing answer on it is not \"$phrase\" (or a bare approve)"
    plan="$(plan_from_row "$repo" "$row")" || exit 1
    plan_check "$plan" "$repo" "$title"
    PLAN_REPO="$(jq -r .repo <<< "$plan")"
    ms="$(gh_get "repos/$repo/milestones/$(jq -r .milestone.number <<< "$plan")")" || exit 1
    [[ "$(jq -r .title <<< "$ms")" == "$title" && "$(jq -r .state <<< "$ms")" == open ]] || die "refused: milestone #$(jq -r .milestone.number <<< "$plan") of $repo is not the open \"$title\""
    db="$(jq -r .default_branch <<< "$plan")"
    # -- the fold-in: every closed row cited by its url in the fold-in commit's message, or dropped in the manifest --
    fc="$(gh_get "repos/$repo/commits/$fold")" || die "refused: the fold-in commit $fold is not on GitHub in $repo (push it)"
    fsha="$(jq -r .sha <<< "$fc")"
    cmp="$(gh_get "repos/$repo/compare/$fsha...$(uri "$db")" | jq -r .status)" || die "cannot compare $fsha with $db"
    [[ "$cmp" == ahead || "$cmp" == identical ]] || die "refused: the fold-in commit ${fsha:0:12} is not on $db of $repo ($cmp)"
    fmsg="$(jq -r .commit.message <<< "$fc")"
    man="$(jq -r .fold_in.manifest <<< "$plan")"
    mst="$(gh_status_of "repos/$repo/contents/$(contents_path "$man")?ref=$fsha")" || exit 1
    mtext=""
    if [[ "$mst" == 200 ]]; then
      mtext="$(gh_get "repos/$repo/contents/$(contents_path "$man")?ref=$fsha" | python3 -I -c 'import sys, json, base64; sys.stdout.write(base64.b64decode(json.load(sys.stdin)["content"]).decode("utf-8"))')" || die "cannot read $man at ${fsha:0:12}"
    fi
    acc="$(FMSG="$fmsg" MTEXT="$mtext" PLAN="$plan" python3 -I - "$man" <<'PY'
import json, os, re, sys
plan = json.loads(os.environ["PLAN"]); man = sys.argv[1]
msg, mtext = os.environ["FMSG"], os.environ["MTEXT"]
urls = {r["url"]: r for r in plan["fold_in"]["rows"]}
dropped, bad = {}, []
for i, l in enumerate(mtext.split("\n"), 1):
    if not l.startswith("dropped:"): continue
    m = re.match(r"^dropped: (https://github\.com/\S+) — (.*\S.*)$", l.rstrip())
    if not m: bad.append("%s:%d is not \"dropped: <url> — <why>\": %s" % (man, i, l)); continue
    if m.group(1) not in urls: bad.append("%s:%d names %s, which is not a closed row of the plan" % (man, i, m.group(1))); continue
    dropped[m.group(1)] = m.group(2)
cited = [u for u in urls if u not in dropped and re.search(re.escape(u) + r"(?![0-9])", msg)]
missing = [u for u in urls if u not in cited and u not in dropped]
print(json.dumps({"cited": cited, "dropped": dropped, "missing": [{"url": u, "title": urls[u]["title"]} for u in missing], "bad": bad}))
PY
)" || die "cannot check the fold-in"
    if [[ "$(jq '.bad | length' <<< "$acc")" -gt 0 ]]; then jq -r '.bad[] | "  " + .' <<< "$acc" >&2; die "refused: the fold-in manifest $man has lines that are not the shape (named above): nothing was written"; fi
    if [[ "$(jq '.missing | length' <<< "$acc")" -gt 0 ]]; then
      echo "daita-beast: refused: $(jq '.missing | length' <<< "$acc") closed row(s) of the plan are unaccounted for in the fold-in ${fsha:0:12}: cite each url in the fold-in commit's message, or add \"dropped: <url> — <why>\" to $man in that commit:" >&2
      jq -r '.missing[] | "  \(.url)  \(.title)"' <<< "$acc" >&2
      die "refused: nothing was written"
    fi
    changed="$(jq -r --arg d "$(jq -r .delete.dir <<< "$plan")/" '[.files[]?.filename | select(startswith($d) | not)] | .[]' <<< "$fc")"
    [[ "$(jq '.cited | length' <<< "$acc")" -eq 0 || -n "$changed" ]] || die "refused: the fold-in ${fsha:0:12} cites rows as folded but changes no file outside $(jq -r .delete.dir <<< "$plan")/: folding is writing them into the docs"
    # -- the release notes, scrubbed before anything is written --
    pub="$(jq -r '.publishes_to // empty' "$(roster_path)")"
    nf="$(mktemp)"
    if [[ -n "$notes" ]]; then [[ -f "$notes" ]] || die "no notes file $notes"; cp "$notes" "$nf"; else notes_render "$plan" "$repo" "$title" > "$nf" || exit 1; fi
    [[ -n "$tag" ]] || tag="$(ms_slug "$title")"
    if [[ -n "$pub" ]]; then
      "$here/publish.sh" release "$tag" --title "$title" --notes-file "$nf" --check || die "refused: the release notes do not pass the scrub gate (named above): nothing was written. Edit them (wrapup.sh notes prints the draft) and pass --notes <file>"
    fi
    if [[ "$(jq -r '.carry // empty' <<< "$plan")" == "" ]]; then
      left="$(issues_list "$repo" -f milestone="$(jq -r .milestone.number <<< "$plan")" -f state=open | jq -r '.[] | .html_url')" || die "cannot list the open items of \"$title\""
      [[ -z "$left" ]] || die "refused: the plan carries nothing forward, but \"$title\" now has open items: $(tr '\n' ' ' <<< "$left")— plan again with --carry"
    fi
    WRAPUP_LOG="$(git -C "$root" rev-parse --absolute-git-dir)/beast/wrapup-$(ms_slug "$title").log"
    mkdir -p "$(dirname "$WRAPUP_LOG")"
    echo "# wrapup.sh run \"$title\" of $repo at $(utc_now), approved $rec, plan sha256:$(beast_sha "$plan")" >> "$WRAPUP_LOG"
    # (1) the release
    if [[ -n "$pub" ]]; then
      rel="$("$here/publish.sh" release "$tag" --title "$title" --notes-file "$nf" | tail -1)" || die "the release was not published (named above): nothing was deleted"
      rel="${rel##* }"
      echo "release: $rel"
    else
      rel="no public repo (the roster has no publishes_to): the notes are printed here"
      echo "release notes (no public pair; deliver them yourself):"; sed 's/^/  /' "$nf"
    fi
    rm -f "$nf"
    # (2) the deletes, each through wrapup_delete
    while IFS=$'\t' read -r n node; do [[ -z "$n" ]] || wrapup_delete "$PLAN_REPO" issue "$repo" "$n" "$node"; done < <(jq -r '.delete.issues[] | [.number, .node_id] | @tsv' <<< "$plan")
    while IFS= read -r id; do [[ -z "$id" ]] || wrapup_delete "$PLAN_REPO" comment "$repo" "$id"; done < <(jq -r '.delete.comments[].id' <<< "$plan")
    dirfiles="$(gh_get "repos/$repo/contents/$(contents_path "$(jq -r .delete.dir <<< "$plan")")?ref=$(uri "$db")" 2>/dev/null | jq -r 'if type == "array" then .[] | select(.type == "file") | .path else empty end')" || dirfiles=""
    delfiles=(); while IFS= read -r x; do delfiles+=("$x"); done < <( { jq -r '.delete.files[].path' <<< "$plan"; [[ -z "$dirfiles" ]] || printf '%s\n' "$dirfiles"; } | sed '/^$/d' | awk '!seen[$0]++')
    [[ ${#delfiles[@]} -eq 0 ]] || wrapup_delete "$PLAN_REPO" files "$repo" "$db" "wrap-up of milestone \"$title\": delete its record files and the wrap-up plan (approved $rec)" "${delfiles[@]}"
    nfold="$(jq '.cited | length' <<< "$acc")"; ndrop="$(jq '.dropped | length' <<< "$acc")"
    # (3) the desks republished
    while IFS= read -r s; do [[ -z "$s" ]] || "$here/desk.sh" publish "$s"; done < <(jq -r '.desks[].desk' <<< "$plan")
    # (4) the milestone closed, open items carried (before the row's close, so an interrupted run is rerun on the open row)
    if [[ "$(gh_get "repos/$repo/milestones/$(jq -r .milestone.number <<< "$plan")" | jq -r .state)" == open ]]; then
      cargs=(); [[ -z "$(jq -r '.carry // empty' <<< "$plan")" ]] || cargs=(--carry "$(jq -r .carry <<< "$plan")")
      "$here/milestone.sh" close "$title" --repo "$repo" ${cargs[@]+"${cargs[@]}"} || die "the milestone was not closed (named above): rerun wrapup.sh run, which skips what is done"
    else echo "milestone \"$title\" already closed"; fi
    # (5) the tracking issue's one summary (not posted twice by a rerun)
    tracking="$(seat_tracking "$by")" || exit 1
    read -r tr_r tr_n < <(parse_issue_ref "$tracking")
    coord_write_guard "$tr_r" "$by"
    summ="milestone $title closed: $rel, $nfold rows folded$([[ "$ndrop" -eq 0 ]] || echo ", $ndrop dropped")"
    had="$(issue_comments "$tr_r" "$tr_n" | jq -r --arg b "$summ" '[.[] | select(.body == $b) | .html_url] | .[0] // empty')" || die "cannot read $tracking"
    if [[ -n "$had" ]]; then echo "summary: already posted $had"; else echo "summary: $(issue_comment "$tr_r" "$tr_n" "$summ")"; fi
    # (6) the row closed on the words (the board republishes)
    "$here/decision.sh" close "$repo#$row" --words "$words" --record "$rec" --by "$by" --next "start the next milestone; run the KB syncs printed below"
    # (7) the DeSciX KB manifests whose sources cover a changed file
    allchanged="$( { printf '%s\n' "$changed"; printf '%s\n' ${delfiles[@]+"${delfiles[@]}"}; } | sed '/^$/d' | sort -u)"
    mst="$(gh_status_of "repos/$repo/contents/.descix/manifests?ref=$(uri "$db")")" || exit 1
    if [[ "$mst" != 200 ]]; then echo "KB: $repo has no .descix/manifests: nothing to re-sync"
    else
      app="$(gh_get "repos/$repo/contents/.descix/workspace.json?ref=$(uri "$db")" 2>/dev/null | python3 -I -c 'import sys, json, base64; print(json.loads(base64.b64decode(json.load(sys.stdin)["content"]))["env"]["app"]["appId"])' 2>/dev/null)" || app="<app_id>"
      hit=0
      while IFS= read -r mp; do
        [[ -n "$mp" ]] || continue
        mj="$(gh_get "repos/$repo/contents/$(contents_path "$mp")?ref=$(uri "$db")" | python3 -I -c 'import sys, json, base64; sys.stdout.write(base64.b64decode(json.load(sys.stdin)["content"]).decode())')" || die "cannot read $mp"
        cov="$(jq -r --arg c "$allchanged" '[.sources[]?.path] as $s | [$c | split("\n")[] | select(length > 0) | . as $f | select(any($s[]; . as $p | ($f == $p or ($f | startswith(($p | rtrimstr("/")) + "/")))))] | join(", ")' <<< "$mj")" || die "$mp is not a KB manifest"
        [[ -n "$cov" ]] || continue
        hit=1; kb="$(jq -r '.kb_name // empty' <<< "$mj")"; [[ -n "$kb" ]] || kb="$(basename "$mp" .json)"
        echo "KB $kb ($mp) covers changed: $cov"
        echo "  run (after pushing $db): $(descix_cmd kb corpus sync -a "$app" -k "$kb" --dry-run)"
        echo "  then:                    $(descix_cmd kb corpus sync -a "$app" -k "$kb")"
      done < <(gh_get "repos/$repo/contents/.descix/manifests?ref=$(uri "$db")" | jq -r '.[] | select(.type == "file" and (.name | endswith(".json"))) | .path')
      [[ $hit -eq 1 ]] || echo "KB: no manifest of $repo covers a changed file"
    fi
    echo "wrap-up of \"$title\" done; the log: $WRAPUP_LOG"
    ;;
esac
