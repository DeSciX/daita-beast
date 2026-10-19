#!/usr/bin/env bash
# bootstrap.sh — make one app repo a Beast-coordinated workspace in one pass.
#   bootstrap.sh --repo <owner/repo> --path <checkout> --seat <LABEL> [--orchestrator <LABEL> --workstream <slug>] [--board <owner/repo>]
#                [--workspace <file.code-workspace>] [--install-plugins] [--kb <name>] [--token <SYMBOL>]
# Does, idempotently: labels + issue templates + roster skeleton (init-repo.sh; the award policy only with
# --token, filled, since the repo takes outside contributions only once it has a token); fills the
# roster's repo, board and people (and an orchestrator seat of this repo, role daita-beast:seat in the workstream
# --workstream names, only when --orchestrator names one; the app's own seat is created by seat.sh new once its
# workstream exists, which also makes its home); a VS Code workspace file beside the checkout;
# a KB corpus manifest skeleton when --kb is given and none exists; and, with --install-plugins, the
# daita marketplace and the daita + daita-beast plugins; and the committed cloud pointer skill
# .claude/skills/beast/SKILL.md (templates/cloud-skill.md), which is how a Claude Code cloud session,
# where nothing installs plugins, reaches Beast. Prints what remains for the person
# (descix-setup, the first workstream) rather than guessing at it.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh jq git
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo=""; path=""; seat=""; orch=""; board=""; ws=""; wslug=""; install=0; kb=""; token=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --seat) seat="$2"; shift 2 ;;
    --orchestrator) orch="$2"; shift 2 ;;
    --workstream) wslug="$2"; shift 2 ;;
    --board) board="$2"; shift 2 ;;
    --workspace) ws="$2"; shift 2 ;;
    --install-plugins) install=1; shift ;;
    --kb) kb="$2"; shift 2 ;;
    --token) token="$2"; shift 2 ;;
    *) die "unknown argument $1" ;;
  esac
done
[[ -n "$repo" && -n "$path" && -n "$seat" ]] || die "usage: bootstrap.sh --repo owner/repo --path <checkout> --seat LABEL [--orchestrator LABEL --workstream <slug>] [--board owner/repo] [--workspace f] [--install-plugins] [--kb name]"
[[ -z "$orch" || -n "$wslug" ]] || die "--orchestrator needs --workstream <slug>: a seat is an identity in one workstream (its tracking issue carries the labels workstream and ws:<slug>)"
[[ -z "$wslug" || "$wslug" =~ $WS_SLUG_RE ]] || die "--workstream '$wslug' is not a slug (a-z, 0-9, -)"
checkout_require_root "$path"
path="$(cd "$path" && pwd)"
me="$(user_login)"
[[ -n "$board" ]] || board="$repo"

echo "== labels, templates, roster, policy"
"$here/init-repo.sh" "$repo" --path "$path" ${token:+--token "$token"}

roster="$path/.beast/roster.json"
for l in "$seat" ${orch:+"$orch"}; do [[ "$l" =~ $SEAT_LABEL_RE ]] || die "--seat/--orchestrator take a LABEL (upper-case letters, digits, _ or -), not '$l': the seat is held by $me"; done
tmp="$(mktemp)"
jq --arg repo "$repo" --arg board "$board" --arg o "$orch" --arg w "$wslug" --arg me "$me" '
  .repo = $repo | .board = $board
  | .coordinates = (if (.coordinates | startswith("<")) then "this app'"'"'s own workstreams; cross-repo decisions go to the board repo" else .coordinates end)
  | .seats = ([.seats[] | select(((.label|startswith("<")) or ((.agent // "<")|startswith("<")) or (.github|startswith("<"))) | not)]
      + (if $o == "" then [] else [{label:$o, github:$me, repo:$repo, lane:"platform", agent:"daita-beast:seat", workstream:$w}] end) | unique_by([.github, .label]))
  | .people = ([.people[] | select(.github | startswith("<") | not)] + [{github:$me, name:$me, role:"owner"}] | unique_by(.github))' "$roster" > "$tmp" && mv "$tmp" "$roster"
echo "roster: repo, board and people written${orch:+; orchestrator seat $me/$orch (agent daita-beast:seat, workstream $wslug)}"
roster_check_unique "$roster"
checkouts_record "$path"

if [[ -n "$ws" ]]; then
  if [[ -f "$ws" ]]; then echo "workspace file present: $ws"; else
    jq -n --arg p "$path" '{folders:[{path:$p}], settings:{}}' > "$ws"; echo "workspace file written: $ws"
  fi
fi

cs="$path/.claude/skills/beast/SKILL.md"
if [[ -f "$cs" ]]; then echo "cloud pointer skill present: $cs"; else
  mkdir -p "$(dirname "$cs")"; cp "$here/../templates/cloud-skill.md" "$cs"; echo "cloud pointer skill written: $cs (commit it; a cloud session loads it, nothing else installs there)"
fi
if [[ -n "$kb" ]]; then
  m="$path/.descix/manifests/$kb.json"
  if [[ -f "$m" ]]; then echo "KB manifest present: $m"; else
    mkdir -p "$path/.descix/manifests"
    jq -n --arg k "$kb" '{kb_name:$k, sync_mode:"local", sources:[{path:"docs", ref:"main", tier:1, doc_type:"documentation"}, {path:"README.md", ref:"main", tier:1, doc_type:"documentation"}]}' > "$m"
    echo "KB manifest skeleton written: $m (name the sources, commit, then: npx -y -p @descix/cli@3.0.0 descix kb corpus sync -a <app> -k $kb --dry-run)"
  fi
fi

if [[ $install -eq 1 ]]; then
  command -v claude >/dev/null || die "claude is not on PATH"
  claude plugin marketplace add DeSciX/DAITA 2>&1 | tail -1 || true
  claude plugin install daita@daita 2>&1 | tail -1 || true
  claude plugin install daita-beast@daita 2>&1 | tail -1 || true
fi

cat <<EOF

== next, by hand (each is the person's act)
1. commit $path/.beast and $path/.github (git add .beast .github && git commit)
2. first workstream (its tracking issue is the seat's): $here/workstream.sh new --slug <slug> --owner <org> --title "WS: <name>" --repo $repo --northstar-file <f> --milestone "<title>|<YYYY-MM-DD>|<what it delivers>"
3. the seat and its home, from $path: $here/seat.sh new $seat --repo-path $path --agent <name | daita-beast:seat> --workstream <slug>
4. start a session anywhere in the workspace and run: $here/join.sh $seat --address "<ListAgents name [ref]>"   (SEATED at the home; the CLAUDE.md block, address, resume; every session)
5. DeSciX: /descix-setup (connector + account), then npx -y -p @descix/cli@3.0.0 descix whoami from $path
6. relay: $here/install-relay.sh --status (one per machine; it already covers every roster seat)
EOF
