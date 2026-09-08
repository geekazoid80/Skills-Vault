#!/usr/bin/env bash
#
# reap-worktrees.sh — safe, re-runnable cleanup of merged local branches and
# dead worktree admin entries for a Claude-Code-managed repo.
#
# What it does NOT do (by design, this is the whole safety story):
#   - It never deletes a branch that is checked out in ANY worktree (live chip).
#   - It never removes a worktree directory that still exists on disk.
#   - It never touches `main`.
#   - It never force-deletes on a plain run. Ancestry-merged branches go via
#     `git branch -d` (which itself refuses anything not truly merged).
#
# Two buckets:
#   1. MERGED   — local branches whose tip is an ancestor of origin/main.
#                 Safe to `-d`. Reaped on --apply.
#   2. GONE     — local branches whose upstream is [gone] but tip is NOT an
#                 ancestor of origin/main. These are almost always squash-merged
#                 (PR landed, remote branch deleted, squash rewrote the SHA so
#                 ancestry can't see it). They need `-D` (force), so they are
#                 only ever LISTED here — never auto-deleted — and you confirm
#                 per branch. Pass --apply-gone to force-delete them too, once
#                 you have eyeballed the list.
#
# Usage:
#   reap-worktrees.sh                 # dry-run against the current repo
#   reap-worktrees.sh --apply         # reap MERGED branches + prune dead worktrees
#   reap-worktrees.sh --apply-gone    # also force-delete the GONE bucket (implies --apply)
#   reap-worktrees.sh <repo_path> ... # operate on another repo instead of cwd
#
set -euo pipefail

APPLY=0
APPLY_GONE=0
REPO="$PWD"
for arg in "$@"; do
  case "$arg" in
    --apply)      APPLY=1 ;;
    --apply-gone) APPLY=1; APPLY_GONE=1 ;;
    -*)           echo "unknown flag: $arg" >&2; exit 2 ;;
    *)            REPO="$arg" ;;
  esac
done

cd "$REPO"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo: $REPO" >&2; exit 2; }
REPO_TOP="$(git rev-parse --show-toplevel)"
echo "repo: $REPO_TOP"
[ "$APPLY" = 1 ] && echo "mode: APPLY" || echo "mode: DRY-RUN (nothing will be deleted; pass --apply to act)"
echo

# Refresh so 'merged' and '[gone]' reflect the real remote state.
echo "fetching origin --prune ..."
git fetch --prune origin >/dev/null 2>&1 || echo "  (fetch failed; results reflect last-known remote state)"
echo

# Branches currently checked out in ANY worktree — these are off-limits.
# (git itself also refuses to delete a checked-out branch, so this is belt-and-braces.)
# Built portably for macOS bash 3.2 (no mapfile).
CHECKED_OUT=()
while IFS= read -r line; do
  [ -n "$line" ] && CHECKED_OUT+=("$line")
done < <(git worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2); print $2}')
protected() {
  local b="$1"
  [ "$b" = "main" ] && return 0
  if [ "${#CHECKED_OUT[@]}" -gt 0 ]; then
    local c
    for c in "${CHECKED_OUT[@]}"; do [ "$b" = "$c" ] && return 0; done
  fi
  return 1
}

# ---- bucket 1: MERGED into origin/main -------------------------------------
echo "=== MERGED into origin/main (safe delete) ==="
merged_any=0
while IFS= read -r b; do
  [ -z "$b" ] && continue
  if protected "$b"; then
    echo "  keep    $b  (checked out or main)"
    continue
  fi
  merged_any=1
  if [ "$APPLY" = 1 ]; then
    git branch -d "$b" >/dev/null && echo "  deleted $b" || echo "  FAILED  $b (left in place)"
  else
    echo "  would delete  $b"
  fi
done < <(git branch --merged origin/main --format='%(refname:short)')
[ "$merged_any" = 0 ] && echo "  (none)"
echo

# ---- bucket 2: GONE upstream, not ancestor-merged (squash-merge suspects) ---
echo "=== GONE upstream, review before deleting (likely squash-merged) ==="
gone_any=0
while IFS= read -r line; do
  b="${line%% *}"
  track="${line#* }"
  case "$track" in *'[gone]'*) ;; *) continue ;; esac
  # Skip any that ancestry already counted as merged (handled above).
  if git merge-base --is-ancestor "$b" origin/main 2>/dev/null; then continue; fi
  if protected "$b"; then echo "  keep    $b  (checked out or main)"; continue; fi
  gone_any=1
  if [ "$APPLY_GONE" = 1 ]; then
    git branch -D "$b" >/dev/null && echo "  FORCE-deleted $b" || echo "  FAILED  $b"
  else
    echo "  review  $b  (force-delete with --apply-gone once confirmed via its PR)"
  fi
done < <(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads)
[ "$gone_any" = 0 ] && echo "  (none)"
echo

# ---- prune dead worktree admin entries (dirs already gone from disk) --------
echo "=== worktree prune (admin entries whose directory is gone) ==="
if [ "$APPLY" = 1 ]; then
  git worktree prune -v || true
  echo "  pruned (see above; empty = nothing to prune)"
else
  git worktree prune -n -v || true
  echo "  dry-run (lines above are what --apply would prune; empty = nothing)"
fi
echo
echo "done."
