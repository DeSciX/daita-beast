#!/usr/bin/env bash
# check_memory_drift.sh — make SILENT memory drift visible.
#
# Agent memory accretes invisibly: per-session gate memos pile up, newer ones silently
# contradict older ones, and the index carries "flagged but NOT reconciled" entries. This
# audits each agent's memory dir and flags the bloat so it can be consolidated (the merge itself is
# the realign skill's memory step). Read-only.
#
# Signals:
#   - too many topic files (default warn > 15 project_*.md)
#   - version clusters (same stem with m2/m3/m4, incr1/incr2, phaseN, _v2 … = likely-superseded)
#   - index red-flags in MEMORY.md (stale / not reconciled / supersedes / contradict / deprecated)
#
# Modes: (default) REPORT exit 0;  --strict exit 1 if any agent is over threshold (close-out gate).
#
# Usage:  bash check_memory_drift.sh [repo-root|agent-memory-dir] [--strict]

set -uo pipefail
ROOT="."; STRICT=0; MAX="${MEM_MAX_FILES:-15}"
for a in "$@"; do case "$a" in --strict) STRICT=1 ;; *) ROOT="$a" ;; esac; done

# Collect agent-memory dirs (depth-limited so we don't crawl node_modules).
DIRS=()
if [ -f "$ROOT/MEMORY.md" ] || ls "$ROOT"/project_*.md >/dev/null 2>&1; then
  DIRS=("$ROOT")                                   # ROOT is itself an agent-memory dir
else
  while IFS= read -r d; do DIRS+=("$d"); done \
    < <(find "$ROOT" -maxdepth 4 -type d -path '*agent-memory/*' 2>/dev/null | sort)
fi

[ "${#DIRS[@]}" -eq 0 ] && { echo "No agent-memory directories under $ROOT."; exit 0; }

over=0
for D in "${DIRS[@]}"; do
  agent="$(basename "$D")"
  files=$(find "$D" -maxdepth 1 -type f -name 'project_*.md' 2>/dev/null | wc -l | tr -d ' ')
  total=$(find "$D" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')

  # version/phase clusters: strip trailing variant tokens, group, keep stems with >=3 members
  clusters=$(find "$D" -maxdepth 1 -type f -name 'project_*.md' 2>/dev/null \
      | sed -E 's#.*/project_##; s#\.md$##' \
      | sed -E 's/_(m[0-9]+|incr[0-9]+|phase[ab0-9]+|v[0-9]+[a-z]?|step[0-9]+|p[0-9]+|asbuilt|design|gate|gateback|recheck|final)$//g' \
      | sed -E 's/_(m[0-9]+|incr[0-9]+|phase[ab0-9]+|v[0-9]+[a-z]?|step[0-9]+|p[0-9]+|asbuilt|design|gate|gateback|recheck|final)$//g' \
      | sort | uniq -c | awk -v n=3 '$1>=n {print "      "$1"x  "$2}')

  redflags=0
  [ -f "$D/MEMORY.md" ] && redflags=$(grep -icE 'stale|not reconciled|supersed|contradict|deprecated|flagged' "$D/MEMORY.md" 2>/dev/null || true)

  flagged=0
  printf '\n• %s — %s files (%s project memos), index red-flags: %s\n' "$agent" "$total" "$files" "$redflags"
  if [ "$files" -gt "$MAX" ]; then echo "    ✗ BLOAT: $files project memos > $MAX — consolidate (fold durable conclusions into MEMORY.md, DELETE landed/superseded memos)."; flagged=1; fi
  if [ -n "$clusters" ]; then echo "    ✗ VERSION CLUSTERS (older variants almost certainly superseded — keep one canonical, delete the rest):"; echo "$clusters"; flagged=1; fi
  if [ "${redflags:-0}" -gt 0 ]; then echo "    ✗ INDEX carries $redflags stale/superseded/contradiction marker(s) — 'flagged NOT reconciled' is not an acceptable end state; reconcile or delete."; flagged=1; fi
  [ "$flagged" -eq 0 ] && echo "    ✓ within limits."
  [ "$flagged" -eq 1 ] && over=$((over+1))
done

echo
if [ "$over" -gt 0 ]; then
  echo "→ $over agent memory store(s) need consolidation (the realign skill's memory step): fold, then DELETE"
  echo "  superseded/landed gate memos (git is the undo) — do not leave contradictory files to silently re-weight."
else
  echo "✓ all agent memory stores within limits."
fi
[ "$STRICT" -eq 1 ] && [ "$over" -gt 0 ] && { echo "STRICT: failing (memory-drift close-out gate)."; exit 1; }
exit 0
