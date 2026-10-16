#!/usr/bin/env bash
# seat.sh — a seat's roster row and its home: the directory its sessions run in, so its memory, its
# CLAUDE.md and its working tree never mix with another seat's.
#   seat.sh new <LABEL> --repo-path <checkout> --role "<text>" --tracking <owner/repo#N> [--kind checkout|worktree|wrapper | --kind subdir --dir <dir>]
#       from the repo's main checkout. Adds the roster row {github: gh login, label, role, repo, lane (CLAUDE.md
#       LANE:), tracking, home: {kind, branch} | {kind: subdir, dir}} and creates the home. Kind, when not given:
#       checkout when no other seat of this login in this repo is homed in the checkout; else worktree; else (the
#       repo has submodules or nested git repos, which a worktree would not carry) wrapper. subdir is only explicit:
#       --dir is a directory inside the checkout (relative to it) that has its own CLAUDE.md and is not a repo root.
#       A roster row written before homes (no "home") of this repo is given its home by the same command.
#   seat.sh where <LABEL | id>     the home path and kind on this machine
#   seat.sh retire <LABEL | id>    role becomes "retired: <date>"; nothing is removed
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
    [[ "$label" =~ $SEAT_LABEL_RE ]] || die "usage: seat.sh new <LABEL> --repo-path <checkout> --role \"<text>\" --tracking <owner/repo#N> [--kind checkout|worktree|wrapper | --kind subdir --dir <dir>] (LABEL: upper-case letters, digits, _ or -)"
    role=""; tracking=""; kind=""; target=""; dir=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --repo-path) target="$2"; shift 2 ;;
        --role) role="$2"; shift 2 ;;
        --tracking) tracking="$2"; shift 2 ;;
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
    [[ -d "$target/.git" || -f "$target/.git" ]] || die "--repo-path $target is not a git checkout"
    cd "$target"
    root="$(repo_main_root)"
    [[ "$(cd "$(repo_root)" && pwd -P)" == "$(cd "$root" && pwd -P)" ]] || die "run seat.sh new from the repo's main checkout $root, not from $(repo_root)"
    roster="$(roster_path)"
    [[ -f "$roster" ]] || die "no roster at $roster — run $here/bootstrap.sh for this repo first"
    roster_check_unique "$roster"
    remote="$(repo_slug "$root")" || exit 1
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
      [[ -z "$role" && -z "$tracking" ]] || die "seat $id already exists: --role and --tracking change it through join.sh --role / --tracking, not seat.sh new"
      rd="$(jq -r '.home.dir // empty' <<< "$row")"
      [[ "$rk" != subdir || -n "$dir" ]] || dir="$rd"
      kind="$rk"; materialize=1
      echo "seat $id exists (home kind $kind): creating its home on this machine"
    elif [[ -n "$row" ]]; then
      [[ "$(jq -r .repo <<< "$row")" == "$remote" ]] || die "seat $id is already in $roster, working in $(jq -r .repo <<< "$row"): a label is unique per login"
      legacy=1
    else
      [[ -n "$role" && -n "$tracking" ]] || die "a new seat needs --role \"<what it owns>\" and --tracking <owner/repo#N>"
    fi
    if [[ -n "$tracking" ]]; then
      tracking="$(tracking_ref "$tracking")" || exit 1
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
      [[ ! -e "$dirp/.git" ]] || die "--dir $dir is a repo root ($dirp/.git): a subdir home is a directory of this checkout, never another repo's checkout"
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
      jq --arg g "$me" --arg l "$label" --argjson h "$homej" --arg r "$role" --arg t "$tracking" \
        "($sel) |= (.home = \$h | (if \$r != \"\" then .role = \$r else . end) | (if \$t != \"\" then .tracking = \$t else . end))" "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
      echo "roster: home recorded on $id${role:+, role updated}${tracking:+, tracking $tracking}"
    else
      jq --arg l "$label" --arg r "$role" --arg repo "$remote" --arg lane "$lane" --arg g "$me" --arg t "$tracking" --argjson h "$homej" \
        '.seats += [{label:$l, role:$r, repo:$repo, lane:$lane, github:$g, tracking:$t, home:$h}]' "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
      echo "roster: added $id (repo $remote, lane $lane, tracking $tracking, home $homej)"
    fi
    fi
    roster_check_unique "$roster"
    tracking="$(jq -r --arg g "$me" --arg l "$label" "$sel | .tracking // empty" "$roster")"

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
      claude_block_write "$home/CLAUDE.md"
    else
      jq -n --arg id "$id" --arg k "$kind" '{id:$id, kind:$k}' > "$home/.beast/seat.json"
      if [[ "$kind" == subdir ]]; then gitignore_seat_json "$root" "$dir/.beast/seat.json"; else gitignore_seat_json "$home"; fi
    fi
    echo "seat.json: $home/.beast/seat.json"
    echo
    echo "== open a session in the home of $id"
    case "$kind" in
      wrapper) echo "  $home/claude.sh     (a wrapper is opened with its launcher; a VS Code folder on the wrapper does not load the repo's agents)" ;;
      *)       echo "  VS Code: File > Open Folder > $home    or a terminal: cd $home && claude" ;;
    esac
    echo "  then the session's first act: $here/join.sh $label --address \"<ListAgents name [ref]>\""
    case "$kind" in
      wrapper) echo "  commit $roster" ;;
      subdir)  echo "  commit $roster and $root/.gitignore if changed" ;;
      *)       echo "  commit $roster and $home/.gitignore if changed" ;;
    esac
    ;;
  where)
    id="$(seat_rostered "${1:-}")" || exit 1
    kind="$(seat_home_kind "$id")" || exit 1
    home="$(seat_home_path "$id")" || exit 1
    echo "home $home"
    if [[ "$kind" == legacy ]]; then echo "kind checkout (no home recorded in the roster: record it with $here/seat.sh new $(seat_label "$id") --kind checkout)"
    else echo "kind $kind"; fi
    [[ -d "$home" ]] || echo "absent on this machine"
    ;;
  retire)
    id="$(seat_rostered "${1:-}")" || exit 1
    roster="$(roster_path)"
    jq --arg g "$(seat_login "$id")" --arg l "$(seat_label "$id")" --arg r "retired: $(date -u +%Y-%m-%d)" \
      '(.seats[] | select(.github == $g and .label == $l) | .role) = $r' "$roster" > "$roster.tmp" && mv "$roster.tmp" "$roster"
    echo "$id retired in $roster (role \"retired: $(date -u +%Y-%m-%d)\"); its home, branch and comments are kept"
    ;;
  *) die "usage: seat.sh new <LABEL> --repo-path <checkout> --role \"<text>\" --tracking <owner/repo#N> [--kind checkout|worktree|wrapper | --kind subdir --dir <dir>] | where <seat> | retire <seat>" ;;
esac
