#!/usr/bin/env bash
# seat.sh — a seat's roster row and its home: the directory the seat works in once seated (join.sh, from any
# directory), so its CLAUDE.md and its working tree never mix with another seat's.
#   seat.sh new <LABEL> --repo-path <checkout> --agent <name> --workstream <slug> [--kind checkout|worktree|wrapper | --kind subdir --dir <dir>]
#       from the repo's main checkout. Refuses a public or public-intended repo before any write. Adds the roster row
#       {github: gh login, label, repo, lane (CLAUDE.md LANE:), agent (the role: <repo>/.claude/agents/<name>.md, or
#       daita-beast:seat), workstream (the slug whose tracking issue carries the labels workstream and ws:<slug>),
#       home: {kind, branch} | {kind: subdir, dir}}, creates the home, then adds the seat to the workstream issue's
#       `## Seats` table (workstream.sh seat-add) and renders the master's CLAUDE.md block (workstream.sh render): one
#       act writes the row, the home, the table and the master block. Kind, when not given:
#       checkout when no other seat of this login in this repo is homed in the checkout; else worktree; else (the
#       repo has submodules or nested git repos, which a worktree would not carry) wrapper. subdir is only explicit:
#       --dir is a directory inside the checkout (relative to it) that has its own CLAUDE.md and is not a repo root.
#       A roster row written before homes (no "home") of this repo is given its home by the same command.
#   seat.sh where <LABEL | id>     the home path and kind on this machine, from any directory (seat_locate)
#   seat.sh retire <LABEL | id>    removes the seat from its workstream's `## Seats` table and sets "retired": "<date>"
#                                  on the roster row; the home, the branch and the comments are kept
# The home path is derived by seat_home_path (lib.sh), never stored in the roster.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need jq git
here="$BEAST_SCRIPTS"

# has_nested_repos <root>: submodules, or any .git under the root other than its own (maxdepth 3).
has_nested_repos() {
  [[ -n "$(git -C "$1" submodule status 2>/dev/null)" ]] && return 0
  [[ -n "$(find "$1" -mindepth 2 -maxdepth 3 -name .git -not -path "$1/.git/*" -print -quit 2>/dev/null)" ]]
}

# gitignore_seat_json <tree> [<entry>]: a seat.json is machine-local; the tree's .gitignore must ignore it.
# <entry> defaults to .beast/seat.json (the tree's own); a subdir home passes <dir>/.beast/seat.json.
gitignore_seat_json() {
  local gi="$1/.gitignore" e="${2:-.beast/seat.json}"
  if [[ -f "$gi" ]] && grep -qxF -- "$e" "$gi"; then return 0; fi
  if [[ -s "$gi" && -n "$(tail -c1 "$gi")" ]]; then echo >> "$gi"; fi
  echo "$e" >> "$gi"
  echo "added $e to $gi (commit it)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  new)
    need gh
    label="${1:-}"; shift || true
    [[ "$label" =~ $SEAT_LABEL_RE ]] || die "usage: seat.sh new <LABEL> --repo-path <checkout> --agent <name> --workstream <slug> [--kind checkout|worktree|wrapper | --kind subdir --dir <dir>] (LABEL: upper-case letters, digits, _ or -)"
    agent=""; ws=""; kind=""; target=""; dir=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo-path) target="$2"; shift 2 ;;
        --agent) agent="$2"; shift 2 ;;
        --workstream) ws="$2"; shift 2 ;;
        --role|--tracking) die "$1 is gone: the role is an agent file (--agent <name>) and the tracking issue is found by its labels (--workstream <slug>)" ;;
        --kind) kind="$2"; shift 2 ;;
        --dir) dir="$2"; shift 2 ;;
        *) die "unknown argument $1" ;;
      esac
    done
    case "$kind" in ""|checkout|worktree|wrapper|subdir) ;; *) die "--kind must be checkout, worktree, wrapper or subdir, not '$kind'" ;; esac
    [[ "$kind" != subdir || -n "$dir" ]] || die "--kind subdir needs --dir <a directory inside the checkout with its own CLAUDE.md>: a subdir home is always named explicitly"
    [[ -z "$dir" || "$kind" == subdir ]] || die "--dir is only for --kind subdir (got --kind ${kind:-none}): a subdir home is never picked automatically"
    # The target repo is a parameter, never the shell's cwd by accident: a seat is scoped deliberately.
    [[ -n "$target" ]] || die "seat.sh new needs --repo-path <the main checkout of the repo this seat works in>; scope it first (the seat skill's scoping step)"
    checkout_require_root "$target"
    cd "$target"
    root="$(repo_main_root)"
    [[ "$(cd "$(repo_root)" && pwd -P)" == "$(cd "$root" && pwd -P)" ]] || die "run seat.sh new from the repo's main checkout $root, not from $(repo_root)"
    roster="$(roster_path)"
    [[ -f "$roster" ]] || die "no roster at $roster — run $here/bootstrap.sh for this repo first"
    roster_check_unique "$roster"
    remote="$(repo_slug "$root")" || exit 1
    why="$(repo_public_why "$remote")" || exit 1
    [[ -z "$why" ]] || die "refused: $remote is $why. A seat's repo is private: its rows, desk and status are coordination writes, which never go to a public repo (the twin's roster names the public one in \"publishes_to\")"
    me="$(user_login)" || die "cannot read the gh login (gh auth status)"
    id="$me/$label"
    sel='.seats[] | select(.github == $g and .label == $l)'
    row="$(jq -c --arg g "$me" --arg l "$label" "$sel" "$roster")"
    legacy=0; materialize=0; rd=""
    if [[ -n "$row" && "$(jq -r 'has("home")' <<< "$row")" == true ]]; then
      # The row exists with a home: this is a second machine (or a deleted home). Re-create the home from the
      # recorded kind; the roster is not written.
      rk="$(jq -r .home.kind <<< "$row")"
      [[ -z "$kind" || "$kind" == "$rk" ]] || die "seat $id is recorded with home kind $rk, not $kind: change the roster row first if the seat is moving"
      [[ -z "$agent" && -z "$ws" ]] || die "seat $id already exists: --agent and --workstream change it through join.sh --agent / --workstream, not seat.sh new"
      rd="$(jq -r '.home.dir // empty' <<< "$row")"
      [[ "$rk" != subdir || -n "$dir" ]] || dir="$rd"
      kind="$rk"; materialize=1
      echo "seat $id exists (home kind $kind): creating its home on this machine"
    elif [[ -n "$row" ]]; then
      [[ "$(jq -r .repo <<< "$row")" == "$remote" ]] || die "seat $id is already in $roster, working in $(jq -r .repo <<< "$row"): a label is unique per login"
      legacy=1
    else
      [[ -n "$agent" && -n "$ws" ]] || die "a new seat needs --agent <name> (its role: $remote/.claude/agents/<name>.md, or daita-beast:seat) and --workstream <slug> (an open issue labelled workstream and ws:<slug>; workstream.sh new opens one)"
    fi
    if [[ $legacy -eq 1 ]]; then
      [[ -n "$agent" ]] || agent="$(jq -r '.agent // empty' <<< "$row")"
      [[ -n "$ws" ]] || ws="$(jq -r '.workstream // empty' <<< "$row")"
      [[ -n "$agent" && -n "$ws" ]] || die "seat $id's row has no agent or workstream yet: pass --agent <name> --workstream <slug>"
    fi
    if [[ $materialize -eq 0 ]]; then
      [[ "$ws" =~ $WS_SLUG_RE ]] || die "--workstream '$ws' is not a slug (a-z, 0-9, -)"
      seat_agent_check "$remote" "$agent" || exit 1
      tracking="$(workstream_issue "$ws")" || exit 1
    fi
    lane="$(sed -n 's/^LANE: *\([a-z]*\).*/\1/p' "$root/CLAUDE.md" 2>/dev/null | head -1)"
    [[ -n "$lane" ]] || die "cannot read the lane: $root/CLAUDE.md has no 'LANE: <platform|rnd|app>' line"

    # A subdir home: a directory of this checkout (never another repo's root) with its own CLAUDE.md, homing no other seat.
    if [[ "$kind" == subdir ]]; then
      [[ "$dir" != /* ]] || die "--dir $dir must be relative to the checkout $root"
      [[ -d "$root/$dir" ]] || die "--dir $dir: $root/$dir is not a directory inside the checkout"
      rootp="$(cd "$root" && pwd -P)"; dirp="$(cd "$root/$dir" && pwd -P)"
      [[ "$dirp" == "$rootp"/* ]] || die "--dir $dir resolves to $dirp, not to a directory inside the checkout $rootp (the checkout itself is --kind checkout)"
      dir="${dirp#"$rootp"/}"
      [[ "$(checkout_root "$dirp")" != "$dirp" ]] || die "--dir $dir is a repo root ($dirp): a subdir home is a directory of this checkout, never another repo's checkout"
      top="$(git -C "$dirp" rev-parse --show-toplevel 2>/dev/null)" && top="$(cd "$top" && pwd -P)" || die "--dir $dir is not inside a git working tree"
      [[ "$top" == "$rootp" ]] || die "--dir $dir is inside the repo at $top, not in the checkout $rootp: a subdir home is a directory of this checkout"
      [[ -f "$dirp/CLAUDE.md" ]] || die "--dir $dir has no CLAUDE.md: a subdir home is a directory with its own CLAUDE.md (the seat's Beast block is written there)"
      [[ $materialize -eq 0 || "$dir" == "$rd" ]] || die "seat $id is recorded with home dir $rd, not $dir: change the roster row first if the seat is moving"
      at_dir="$(jq -r --arg r "$remote" --arg g "$me" --arg l "$label" --arg d "$dir" \
        '[.seats[] | select(.repo == $r and .github == $g and .label != $l and .home.kind? == "subdir" and .home.dir == $d) | "\(.github)/\(.label)"] | join(" ")' "$roster")"
      [[ -z "$at_dir" ]] || die "the directory $dir is already the home of $at_dir: two seats never share a directory"
    fi

    # Other seats homed in this checkout: kind checkout, or a row without a home (read as checkout).
    in_checkout="$(jq -r --arg r "$remote" --arg g "$me" --arg l "$label" \
      '[.seats[] | select(.repo == $r and .github == $g and .label != $l and ((has("home") | not) or .home.kind == "checkout")) | "\(.github)/\(.label)"] | join(" ")' "$roster")"
    if [[ -z "$kind" ]]; then
      if [[ -z "$in_checkout" ]]; then kind=checkout
      elif has_nested_repos "$root"; then kind=wrapper
      else kind=worktree; fi
      echo "kind: $kind (seats of $me homed in this checkout: ${in_checkout:-none}$([[ "$kind" == wrapper ]] && echo "; the repo has submodules or nested git repos"))"
    fi
    [[ "$kind" != checkout || -z "$in_checkout" || $materialize -eq 1 ]] || die "the checkout $root is already the home of $in_checkout: two seats never share a directory (use --kind worktree or wrapper, or --kind subdir --dir <dir>)"
    home="$(seat_home_path_of "$kind" "$me" "$label" "$root" "$dir")"
    branch=null; [[ "$kind" == worktree ]] && branch="seat/$label"

    # Refusals before any write.
    if [[ -e "$home" ]]; then
      sj="$(seat_json_id "$home")" || exit 1
      if [[ "$kind" == checkout || "$kind" == subdir ]]; then
        [[ -z "$sj" || "$sj" == "$id" ]] || die "$home is the home of $sj (its .beast/seat.json): two seats never share a directory"
      else
        [[ "$sj" == "$id" ]] || die "$home exists and is not the home of $id (.beast/seat.json: ${sj:-absent}): move it or choose another kind"
      fi
    fi
    if [[ "$kind" == worktree && ! -e "$home" ]]; then
      at="$(git -C "$root" worktree list --porcelain | awk -v b="branch refs/heads/$branch" '/^worktree /{w=substr($0,10)} $0==b{print w}')"
      if [[ -n "$at" ]]; then
        [[ -z "$(git -C "$at" status --porcelain)" ]] || die "branch $branch is checked out with uncommitted changes at $at: a dirty branch is not given a second worktree; commit or stash there first"
        die "branch $branch is already checked out at $at, not at the home $home: remove that worktree (git worktree remove $at) or move it to $home"
      fi
    fi

    # Roster row (skipped when only materializing an existing seat's home).
    if [[ $materialize -eq 1 ]]; then :; else
    if [[ "$kind" == subdir ]]; then homej="$(jq -nc --arg d "$dir" '{kind:"subdir", dir:$d}')"
    else homej="$(jq -nc --arg k "$kind" --arg b "$branch" '{kind:$k, branch:(if $b == "null" then null else $b end)}')"; fi
    if [[ $legacy -eq 1 ]]; then
      jq --arg g "$me" --arg l "$label" --argjson h "$homej" --arg a "$agent" --arg w "$ws" \
        "($sel) |= (.home = \$h | .agent = \$a | .workstream = \$w)" "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
      echo "roster: home recorded on $id (agent $agent, workstream $ws)"
    else
      jq --arg l "$label" --arg repo "$remote" --arg lane "$lane" --arg g "$me" --arg a "$agent" --arg w "$ws" --argjson h "$homej" \
        '.seats += [{label:$l, github:$g, repo:$repo, lane:$lane, agent:$a, workstream:$w, home:$h}]' "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
      echo "roster: added $id (repo $remote, lane $lane, agent $agent, workstream $ws, tracking $tracking, home $homej)"
    fi
    fi
    roster_check_unique "$roster"
    ws="$(roster_field "$id" workstream)"; agent="$(roster_field "$id" agent)"

    # The home.
    case "$kind" in
      checkout|subdir) : ;;
      worktree)
        if [[ -e "$home" ]]; then echo "worktree present: $home"
        elif git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then git -C "$root" worktree add "$home" "$branch" >/dev/null 2>&1 || die "git worktree add $home $branch failed"; echo "worktree $home on the existing branch $branch"
        else git -C "$root" worktree add "$home" -b "$branch" >/dev/null 2>&1 || die "git worktree add $home -b $branch failed"; echo "worktree $home on the new branch $branch"; fi
        ;;
      wrapper)
        mkdir -p "$home/.beast"
        printf '@%s/CLAUDE.md\n\n' "$root" > "$home/CLAUDE.md"
        printf '#!/usr/bin/env bash\n# Generated by daita-beast seat.sh: a wrapper home is opened with --add-dir, which loads the repo'"'"'s agents, skills and imports.\ncd %q && exec claude --add-dir %q "$@"\n' "$home" "$root" > "$home/claude.sh"
        chmod +x "$home/claude.sh"
        echo "wrapper $home: CLAUDE.md (imports $root/CLAUDE.md) and claude.sh"
        ;;
    esac
    mkdir -p "$home/.beast"
    if [[ "$kind" == wrapper ]]; then
      jq -n --arg id "$id" --arg k "$kind" --arg root "$root" '{id:$id, kind:$k, root:$root}' > "$home/.beast/seat.json"
    else
      jq -n --arg id "$id" --arg k "$kind" '{id:$id, kind:$k}' > "$home/.beast/seat.json"
      if [[ "$kind" == subdir ]]; then gitignore_seat_json "$root" "$dir/.beast/seat.json"; else gitignore_seat_json "$home"; fi
    fi
    echo "seat.json: $home/.beast/seat.json"
    checkouts_record "$root"
    # The seat map: the workstream issue's `## Seats` table (the one owner), then the master's CLAUDE.md block.
    if [[ $materialize -eq 0 ]]; then
      homeword="$(ws_home_word "$kind" "$([[ "$kind" == subdir ]] && echo "$dir" || { [[ "$kind" == worktree ]] && echo "$branch" || true; })")" || exit 1
      if ws_seats_parse "$ws" | grep -q "^$id	"; then echo "table: $id is already in the \`## Seats\` table of workstream $ws"
      else "$here/workstream.sh" seat-add "$ws" "$id" --repo "$remote" --home "$homeword" --agent "$agent" || die "the roster row and the home are written, the \`## Seats\` table is not (named above): rerun $here/workstream.sh seat-add $ws $id --repo $remote --home \"$homeword\" --agent $agent, then workstream.sh render $ws"; fi
      "$here/workstream.sh" render "$ws" || die "the \`## Seats\` table is written, the master's CLAUDE.md block is not (named above): rerun $here/workstream.sh render $ws"
    fi
    [[ "$kind" != wrapper ]] || claude_block_write "$home/CLAUDE.md" "$id"
    echo
    echo "== take the seat: start a session anywhere in the workspace and run"
    echo "  $here/join.sh $label --address \"<ListAgents name [ref]>\"     (it prints SEATED $id at $home; the home is the seat's root from then on)"
    [[ "$kind" != wrapper ]] || echo "  optional, for terminal users: $home/claude.sh starts a session in the wrapper with the repo's agents and skills (claude --add-dir)"
    case "$kind" in
      wrapper) echo "  commit $roster" ;;
      subdir)  echo "  commit $roster and $root/.gitignore if changed" ;;
      *)       echo "  commit $roster and $home/.gitignore if changed" ;;
    esac
    ;;
  where)
    loc="$(seat_locate "${1:-}" "$PWD")" || exit 1
    id="${loc%%$'\t'*}"; cd "${loc#*$'\t'}"
    kind="$(seat_home_kind "$id")" || exit 1
    home="$(seat_home_path "$id")" || exit 1
    echo "home $home"
    if [[ "$kind" == legacy ]]; then echo "kind checkout (no home recorded in the roster: record it with $here/seat.sh new $(seat_label "$id") --repo-path $(pwd -P) --kind checkout)"
    else echo "kind $kind"; fi
    [[ -d "$home" ]] || echo "absent on this machine: $here/seat.sh new $(seat_label "$id") --repo-path $(pwd -P) creates it"
    ;;
  retire)
    need gh
    id="$(seat_rostered "${1:-}")" || exit 1
    roster="$(roster_path)"
    ws="$(roster_field "$id" workstream)"
    if ws_seats_parse "$ws" | grep -q "^$id	"; then "$here/workstream.sh" seat-remove "$ws" "$id" || exit 1; "$here/workstream.sh" render "$ws" || exit 1
    else echo "table: $id is not in the \`## Seats\` table of workstream $ws"; fi
    jq --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" --arg d "$(date -u +%Y-%m-%d)" \
      '(.seats[] | select(.github == $g and .label == $l) | .retired) = $d' "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
    echo "$id retired in $roster (\"retired\": \"$(date -u +%Y-%m-%d)\"); its home, branch and comments are kept"
    ;;
  *) die "usage: seat.sh new <LABEL> --repo-path <checkout> --agent <name> --workstream <slug> [--kind checkout|worktree|wrapper | --kind subdir --dir <dir>] | where <seat> | retire <seat>" ;;
esac
