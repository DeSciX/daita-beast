#!/usr/bin/env bash
# surface_candidates.sh — read-only drift-candidate finder for a realign pass (daita-beast skill realign).
#
# This is a FLASHLIGHT, NOT A GUILLOTINE. It only reports. It never edits or deletes.
# It groups likely-drift candidates by artifact class so a human (or the realign skill)
# can judge each one against the repo's canonical source of truth before removing it.
#
# Git-aware: inside a git repo it scans ONLY tracked files (`git ls-files`), which
# automatically excludes gitignored build/vendor trees (.venv, target/, node_modules,
# sdk/*/dist, caches) and never wastes attention on generated output. It also skips
# agent worktree mirrors (.claude/worktrees/) so candidates aren't double/triple-counted.
# Outside a git repo it falls back to a filtered filesystem walk.
#
# Usage:  bash surface_candidates.sh [repo-root]   (defaults to current dir)

set -uo pipefail
ROOT="${1:-.}"
ROOT="${ROOT%/}"

EXCLUDE_RE='(^|/)(\.git|node_modules|\.realign-quarantine)/|(^|/)\.claude/worktrees/'

# --- Build the candidate file list (absolute paths), git-scoped when possible -------
MODE="filesystem walk"
FILES=()
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  MODE="git-tracked files (gitignored + worktrees excluded)"
  while IFS= read -r rel; do
    [[ "$rel" =~ $EXCLUDE_RE ]] && continue
    FILES+=("$ROOT/$rel")
  done < <(cd "$ROOT" && git ls-files)
else
  while IFS= read -r f; do
    [[ "$f" =~ $EXCLUDE_RE ]] && continue
    FILES+=("$f")
  done < <(find "$ROOT" -type f \
      -not -path '*/.git/*' -not -path '*/node_modules/*' \
      -not -path '*/dist/*' -not -path '*/.realign-quarantine/*' 2>/dev/null)
fi

LIST="$(mktemp)"; trap 'rm -f "$LIST"' EXIT
if [ "${#FILES[@]}" -gt 0 ]; then printf '%s\n' "${FILES[@]}" > "$LIST"; else : > "$LIST"; fi

# grep the candidate pattern across the (tracked) file list, batched for large repos.
# Prefer ripgrep (fast, skips binary); cap filesize so giant tracked data blobs don't
# stall the sweep. Fall back to grep where rg is unavailable.
if command -v rg >/dev/null 2>&1; then
  SEARCH() { tr '\n' '\0' < "$LIST" | xargs -0 rg --no-messages -nH -i --max-filesize 1M -e "$1" 2>/dev/null; }
else
  SEARCH() { tr '\n' '\0' < "$LIST" | xargs -0 grep -nIHE -i -e "$1" 2>/dev/null; }
fi
# filter the file list by a path/name regex (case-insensitive); read paths from $LIST only.
PICK()   { grep -iE -- "$1" "$LIST" 2>/dev/null; }

section() { printf '\n========== %s ==========\n' "$1"; }

echo "realign candidate sweep over: $ROOT"
echo "Scan scope: $MODE  (${#FILES[@]} files)"
echo "(read-only — nothing here is deleted; judge each against the canonical anchor)"

# 1) Superseded / tombstone markers — the #1 thing to DELETE not keep.
section "1. Superseded / tombstone / deprecated markers"
R=$(SEARCH 'superseded|deprecated|tombstone|do not use|no longer (used|valid|true)|old approach|obsolete|outdated|to be removed|kept for now|just in case')
echo "${R:-  (none)}"

# 2) Dead-code / fallback patterns left "just in case".
section "2. Dead code / fallback / disabled blocks"
R=$(SEARCH 'fallback|dead code|unreachable|TODO: *remove|FIXME: *remove|commented out|if *\(false\)|#if 0|xxx:')
echo "${R:-  (none)}"

# 3) Agent-instruction files present (review these for stale invariants).
section "3. Agent-instruction files (review for stale instructions)"
PICK '(^|/)(CLAUDE|AGENTS|SKILL)\.md$' | sed 's/^/  /' || true
echo "  --- .claude / .cursor config files (tracked) ---"
PICK '(^|/)\.(claude|cursor)/' | sed 's/^/  /' | head -40 || true

# 4) Candidate stale docs — versioned / dated / *_OLD / *_v2 siblings = frankenstein.
section "4. Possibly-superseded docs (versioned / dated / *_old / *_v2 siblings)"
PICK '(_old|-old|_v[0-9]|deprecated|backup|_copy|\bcopy)' | sed 's/^/  /' | head -60 || true

# 5) Broken intra-repo references (markdown links to relative paths — spot-check).
section "5. Possible relative-link references in docs (spot-check target exists)"
R=$(SEARCH '\]\(\.{0,2}/[^)]+\)')
echo "${R:-  (none)}" | head -60

# 6) "Living audit" / status / handoff docs — UPDATE in place, do not duplicate or delete.
section "6. Living-audit / status / handoff docs (update in place — do NOT delete)"
PICK 'audit.*\.md$|status.*\.md$|handoff.*\.md$|asbuilt.*\.md$|workstate.*\.md$' | sed 's/^/  /' | head -40 || true

# 7) PROTECTED-PATH heads-up — these usually must NOT be auto-deleted.
section "7. Protected-path heads-up (do NOT auto-delete; regenerate/keep as policy)"
PICK '(^|/)(archive|Archive|dist|Dev)/' | sed 's@/[^/]*$@/@' | sort -u | sed 's/^/  protected? /' | head -40 || true
echo "  NOTE: 'protected' does not mean 'unreferenced'. Before treating an archive/-style"
echo "  dir as a pure graveyard in your report, confirm live code doesn't depend on it"
echo "  (e.g. \`git grep <dir>\`) — archived-looking paths are sometimes still imported."

section "Done"
echo "Next: for each candidate above, compare against the canonical anchor."
echo "Delete only what contradicts/duplicates it; quarantine first if no git net;"
echo "never touch protected paths; flag anything you are unsure about."
