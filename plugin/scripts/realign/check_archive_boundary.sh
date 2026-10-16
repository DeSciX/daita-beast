#!/usr/bin/env bash
# check_archive_boundary.sh — enforce the ONE-WAY SINK invariant.
#
# The graveyard is a destination, never a source: no live code OUTSIDE an archive
# directory may import / include / read a path INSIDE it. A reference into archive/
# from outside is a drift violation — the thing is still alive and belongs back in the
# canonical surface, or the caller is dead.
#
# PRECISION: only real references count — a quoted module path / relative path inside a
# SOURCE file (`require('../archive/x')`, `import … from 'lib/…/deprecated/…'`,
# `path.join(root,'archive/old_sdk',…)`). Prose in .md/.txt, comments, JSON data,
# and agent memory are NOT violations and are deliberately excluded — otherwise the gate
# would block every commit on legacy debt and documentation.
#
# Modes:
#   (default)         REPORT over the whole repo, exit 0. Used by the realignment pass.
#   --strict          exit 1 if any violation is found (whole repo).
#   --staged --strict block only NEWLY ADDED violations in the commit. Used by pre-commit.
#
# Graveyard dir names (override: ARCHIVE_DIRS="archive Archive deprecated legacy"):
#   archive Archive deprecated
#
# Usage:  bash check_archive_boundary.sh [repo-root] [--strict] [--staged]

set -uo pipefail
ROOT="."; STRICT=0; STAGED=0
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    --staged) STAGED=1 ;;
    *) ROOT="$a" ;;
  esac
done
cd "$ROOT" 2>/dev/null || { echo "check_archive_boundary: cannot cd into $ROOT" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "check_archive_boundary: $ROOT is not a git repo: nothing was checked" >&2; exit 1; }

NAMES="${ARCHIVE_DIRS:-archive Archive deprecated}"
NAME_RE="$(echo "$NAMES" | tr ' ' '|')"

# A real reference: graveyard name as a path segment inside a quote (', ", or `).
REF_RE="['\"\`][^'\"\`]*(^|/)(${NAME_RE})/"

# Source extensions where an import/read actually executes (prose/data excluded).
CODE_RE='\.(js|mjs|cjs|jsx|ts|tsx|vue|svelte|py|rb|php|go|rs|java|kt|c|h|cc|cpp|hpp|cs|swift|scss|css|html)$'

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

is_inside_graveyard() { echo "$1" | grep -qE "(^|/)(${NAME_RE})/"; }

if [ "$STAGED" -eq 1 ]; then
  # Only newly ADDED lines in staged source files (block introducing, not legacy debt).
  while IFS= read -r f; do
    echo "$f" | grep -qE "$CODE_RE" || continue
    is_inside_graveyard "$f" && continue
    git diff --cached -U0 -- "$f" 2>/dev/null \
      | grep -E '^\+' | grep -vE '^\+\+\+' \
      | grep -E "$REF_RE" | sed "s#^+#  $f: +#" >> "$TMP" || true
  done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
else
  # Whole-repo report over tracked source files outside any graveyard.
  while IFS= read -r f; do
    echo "$f" | grep -qE "$CODE_RE" || continue
    is_inside_graveyard "$f" && continue
    grep -nHE "$REF_RE" "$f" 2>/dev/null >> "$TMP" || true
  done < <(git ls-files)
fi

sort -u "$TMP" -o "$TMP"
n=$(grep -c . "$TMP"); n=${n:-0}

if [ "$n" -gt 0 ]; then
  echo "✗ $n one-way-sink VIOLATION(s) — live source referencing a graveyard ($NAMES):"
  sed 's/^/    /' "$TMP"
  echo
  echo "Fix each: promote the still-needed item back into the canonical surface (e.g. lib/)"
  echo "and repoint the caller, OR delete the now-dead caller. Never keep the archive import."
else
  echo "✓ clean — no live source references into the graveyard${STAGED:+ (staged changes)}."
fi

if [ "$STRICT" -eq 1 ] && [ "$n" -gt 0 ]; then
  echo "STRICT: failing (one-way-sink hard gate)."
  exit 1
fi
exit 0
