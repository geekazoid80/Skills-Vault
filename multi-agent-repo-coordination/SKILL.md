---
name: multi-agent-repo-coordination
description: Use before the first edit, commit, or push in any git repo that a concurrent agent or person may also be touching this session - peer Claude sessions, a shared estate or knowledge base, or a repo whose `.git` is shared by other worktrees. Trigger phrases and symptoms - "worktree", "concurrent session", "peer is editing", "shared checkout", "multi-agent", a branch ref that shuffled mid-commit, a commit that landed on the wrong branch, "cannot lock ref", "'<base>' is already used by worktree", a push that seemed to vanish, `git rev-parse origin/<branch>` failing after a push that landed, two local clones of one repo under different names, a stale clone serving old code, a parallel session that merged the same feature. Covers worktree-per-session, ff-only sync, branch-per-task, verify-the-pushed-ref via `ls-remote`, SHA recovery after a ref shuffle, append-not-rewrite for shared docs and memory, and clone-not-assume (one canonical local clone). NOT for solo repos with no concurrent actors; NOT for choosing where on disk a repo lives (that is repo-safe-locations). Composes with using-git-worktrees and pull-before-dev.
metadata:
  version: 1.0.0
---

# Multi-Agent Repo Coordination

> **Skill marker**: When applying this skill, begin your reply with `[skill: multi-agent-repo-coordination]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

A git repo worked by more than one agent or person at once is a shared, moving surface. A peer session may be editing the same files, moving a branch ref, or merging the same feature while you work, and none of it announces itself. The failures are silent: your edits revert, your commit lands on the wrong branch, your push targets a stale ref, two clones drift apart, or you re-do work a peer already merged.

**Core principle:** assume a peer may change any shared file or branch ref at any moment. Isolate your work (own worktree, own branch), sync fast-forward-only, verify every push against server truth, and treat shared docs and memory as append-not-rewrite. This skill is the coordination layer; `using-git-worktrees` owns worktree creation mechanics and `pull-before-dev` owns the ff-only sync, so cross-reference them rather than re-deriving.

## When this fires

- Before the first edit, commit, or push in a repo a peer session or person may share (a shared estate, a knowledge base, a repo whose `.git` other worktrees link).
- On any symptom of a shared-`.git` race: edits reverting mid-session, a branch ref that shuffled, a commit on the wrong branch, `cannot lock ref`, a push that seems to have vanished.
- Before opening a PR, when a parallel session may have shipped the same change.
- When you find, or an all-org clone script produces, more than one local clone of the same repo.

## When this does NOT fire

- Solo repos with no concurrent actors: the isolation ceremony is overhead you do not need.
- Choosing where on disk to put a repo, or diagnosing a repo that reverts because of a two-way file sync (iCloud, NAS rsync, Syncthing): that is `repo-safe-locations`.
- Pure read-only exploration with no intent to modify.

## Worktree per task

Never edit in a shared main checkout. Work in your own linked worktree so a peer's checkout cannot move your branch under you (a worktree has its own HEAD and index). Prefer the harness-native tool per `using-git-worktrees`; the manual form is:

```
git -C <repo> fetch --prune origin main
git -C <repo> worktree add ../wt-<task> -b <area>/<task> origin/main
# edit, commit, push, open the PR in ../wt-<task>, then:
git -C <repo> worktree remove ../wt-<task>
```

All Edit / Write / Read use the worktree-prefixed absolute path, never the main-repo path.

## Sync fast-forward-only, per repo

Before the first edit, `fetch --prune` then `pull --ff-only` (or branch straight off `origin/main`), per `pull-before-dev`. Fast-forward only, never a merge or force as a side effect of syncing. If `--ff-only` refuses because local and remote diverged, or a dirty tree would conflict, STOP and surface it rather than force. When work spans several repos, sync each before touching it, not just the first.

## Branch per task, commit immediately, verify the pushed ref

One branch per task off `main`. Commit early: pushed blobs are immune to a local ref shuffle, uncommitted edits are not. After pushing, verify the ref actually landed against **server truth**:

```
git ls-remote origin refs/heads/<branch>   # server truth, shallow-safe
git rev-parse HEAD                          # compare to your commit
```

Use `ls-remote`, NOT `git rev-parse origin/<branch>`. A shallow or single-branch clone has no tracking ref, so `rev-parse origin/<branch>` fails ("Needed a single revision") even when the push landed, which can leave an orphan branch with no PR under a `check=True` guard. Gate the next step on the artifact (the server ref), never on the push command's exit code alone.

## Recover from a ref shuffle

If a commit lands on the wrong branch because a shared `.git` shuffled refs mid-commit, do not re-stage from scratch. Push the SHA explicitly to the branch you meant:

```
git push origin <sha>:refs/heads/<branch>
```

Then re-verify with `ls-remote`. On any file-revert race, run `git worktree list` to see live peers, re-anchor your tree with `git reset --hard <sha>`, and confirm against server truth before continuing. A NUC-side `cannot lock ref 'refs/remotes/origin/<branch>': is at X but expected Y` on fetch is usually a transient concurrent-fetch race (often racing a weekly-pull cron); it self-resolves, just retry.

## Append, do not rewrite, shared docs and memory

Shared docs and project memory are a live surface a peer may be mid-edit on. Prefer small, targeted edits over wholesale rewrites; on a conflict, reconcile rather than clobber. In a multi-worktree estate the project memory index and its linked files can change while you work (a peer adds a coordination hold, chips a follow-up, or supersedes a note), so re-read them fresh from disk at every boundary (per `boundary-check`), never trust the session-start snapshot. `git worktree list` plus `gh pr list` shows the live peers.

## Clone, do not assume: one canonical local clone

The same GitHub repo can end up cloned **twice** into one working root under **different directory names** (a hand-named `Some Repo` beside the GitHub-slug `Some-Repo` that an all-org clone script produces). Both have their own `.git` pointing at the same `origin`; one drifts behind while the other tracks `origin/main`, and a session that opens the **stale** clone reads old code (wrong line numbers, missing merged changes) with no error.

Before the first edit in a repo under a multi-repo root, confirm there is only ONE local clone and that you are in the canonical one:

```
cd <root>; for d in */; do d="${d%/}"; u=$(git -C "$d" remote get-url origin 2>/dev/null) \
  && printf '%s\t%s\n' "$(basename "$u" .git)" "$d"; done | sort | awk -F'\t' \
  '{c[$1]++; m[$1]=m[$1]" | "$2} END{for(k in c) if(c[k]>1) print k": "m[k]}'
```

Determine canonical by three signals, **not by the name**: (1) `git rev-parse --short origin/main` after a `fetch` versus local HEAD (canonical is at or fast-forwardable to `origin/main`); (2) last-commit date (`git log -1 --format=%ci`); (3) which clone holds the active session or live worktree (`git worktree list`). The clone that is current AND actively used is canonical. If you already read from the other, discard those reads and re-read from the canonical clone.

Resolve the duplicate so the next session cannot pick wrong: verify the stale clone has no uncommitted changes and no unpushed commits (every worktree HEAD reachable from an `origin` branch, or a squash-merge leftover whose subject matches a commit on `origin/main`), then **move it to Trash** (`mv "<stale>" ~/.Trash/...`, reversible), not `rm -rf`. Record the canonical-clone fact in project memory so a future all-org clone that recreates the twin knows which to keep.

## Concurrent duplicate PR: check main, close yours, do not clobber

When a change you just built hits a "not mergeable" conflict, a parallel session may have already merged the same feature. Before assuming an unrelated conflict, `git log --oneline origin/main` for a commit whose **subject** matches your feature. If found, close YOUR PR as a duplicate (comment plus delete branch) and pivot to the shared outcome (deploy or live-test the merged version); never force-merge over the landed work. Detection is not always possible upfront (a true race), so gate on the artifact.

## `gh pr merge --delete-branch` from a worktree

`gh pr merge <N> --delete-branch` run from inside a linked worktree of the same repo errors `'<base>' is already used by worktree` (gh cannot check out the base held by the canonical clone), but the **API merge still succeeds**. Verify `state=MERGED`, then clean up by hand: `worktree remove`, `pull --ff-only` the canonical base, `branch -D` plus `push origin --delete` the head. Gate on the merged-state artifact, not the `gh` exit code.

## Red Flags

- About to edit in a shared main checkout instead of your own worktree.
- Trusting `git push`'s exit code as proof the ref landed, without an `ls-remote` verify.
- Using `git rev-parse origin/<branch>` to verify a push in a shallow or single-branch clone (it fails even on success).
- Wholesale-rewriting a shared doc or memory file a peer may be mid-edit on.
- Reasoning off a session-start memory snapshot at a boundary instead of a fresh disk re-read.
- Assuming one local dir per repo without a dedup scan; editing the stale twin.
- Force-merging your PR over a "not mergeable" conflict without checking whether a peer already merged the same subject.
- Treating a worktree `gh pr merge --delete-branch` error as a failed merge (it merged; only local cleanup failed).
- `rm -rf` on a "stale" clone before verifying it has no unique or uncommitted work (move to Trash instead).

## Bottom Line

Assume a peer is changing the shared repo right now. Isolate in your own worktree and branch, sync ff-only, and verify every push against `ls-remote` server truth, not the push exit code. On a ref shuffle, push the SHA explicitly and re-anchor. Append, do not rewrite, shared docs and memory, and re-read them fresh at each boundary. Keep exactly one canonical local clone; dedup-scan by origin, determine canonical by state not name, and Trash (never `rm -rf`) the stale twin. Before force-merging a conflict, check whether a peer already shipped it. Composes with `using-git-worktrees` (creation) and `pull-before-dev` (sync).
