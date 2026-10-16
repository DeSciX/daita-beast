#!/usr/bin/env bash
# check_branch_base.sh — read-only branch & worktree hygiene report.
#
# Light-touch by design: this NEVER mutates git state and NEVER deletes a branch or
# worktree. It reports so a human can spot wrong-base or orphaned-branch drift.
#
# Usage:  bash check_branch_base.sh [repo-root]   (defaults to current dir)

set -uo pipefail
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "cannot cd into $ROOT"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not a git repo: $ROOT  (branch hygiene is a no-op here)"
  exit 0
fi

BASE="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')"
[ -z "$BASE" ] && BASE="origin/main"
echo "Repo: $ROOT"
echo "Assumed canonical base: $BASE"
echo "Current branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

echo
echo "===== Local branches (ahead/behind canonical base) ====="
git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | while read -r b; do
  if git rev-parse --verify "$BASE" >/dev/null 2>&1; then
    counts=$(git rev-list --left-right --count "$BASE"..."$b" 2>/dev/null)
    behind=$(echo "$counts" | awk '{print $1}')
    ahead=$(echo "$counts" | awk '{print $2}')
    last=$(git log -1 --format='%cr' "$b" 2>/dev/null)
    flag=""
    [ "${ahead:-0}" -eq 0 ] 2>/dev/null && flag="  <- 0 commits ahead: stale/merged? (flag, do NOT auto-delete)"
    printf '  %-40s behind:%-5s ahead:%-5s last:%s%s\n' "$b" "${behind:-?}" "${ahead:-?}" "$last" "$flag"
  else
    printf '  %-40s (base %s not found locally)\n' "$b" "$BASE"
  fi
done

echo
echo "===== Worktrees ====="
git worktree list 2>/dev/null | sed 's/^/  /' || echo "  (none)"
echo "  Note: orphaned/old agent worktrees are flagged for human review — never auto-removed."

echo
echo "===== Branch-base sanity ====="
echo "Before cutting a new branch, confirm you are basing off the right tip of: $BASE"
echo "(report only — no git state was changed)"
