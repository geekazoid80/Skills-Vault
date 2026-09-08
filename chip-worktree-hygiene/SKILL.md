---
name: chip-worktree-hygiene
description: "Use when Claude Code background sessions (chips, spawned tasks, parallel Code-tab sessions) share or collide over git worktrees under .claude/worktrees/. Fires on a session's working tree vanishing or being repointed when another session archives (the rug-pull), a worktree directory recycled across sessions (its name matches neither its branch nor any branch that existed), merged claude/* branches piling up undeleted, uncommitted work discarded when a slot is recycled, or a .git/worktrees/<dir>/logs/HEAD reflog showing several \"checkout: moving\" entries. Trigger phrases include \"chips pull the same tree\", \"worktree recycled\", \"worktree removed under me\", \"one chip archives and deletes another's work\", \"wrong worktree\", \"worktree pool\", \"rebindWorktree\", \"branch pile-up\", \"reap merged branches\", \".claude/worktrees churn\", \"directory repointed\", \"worktree dir name does not match branch\". Covers proving the recycling from per-worktree reflogs, the safe bulk reap (delete only origin/main-merged branches not checked out in any live worktree, force-delete gone-upstream squash-merges only after review, prune dead worktrees), running the reap only when chips are quiet, and reporting the behaviour. NOT for your OWN worktree lifecycle or disposal-at-close (using-git-worktrees), NOT for peer-session shared-ref coordination (multi-agent-repo-coordination), NOT for where a repo lives on disk (repo-safe-locations)."
metadata:
  version: 1.0.0
---

# Chip Worktree Hygiene

> **Skill marker**: When applying this skill, begin your reply with `[skill: chip-worktree-hygiene]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Claude Code background sessions (chips, spawned tasks, parallel Code-tab sessions) do not each get a stable, dedicated git worktree. The desktop app keeps a **pool** of worktree directories under `.claude/worktrees/` and recycles them across sessions by repointing a directory's HEAD to a new branch, sometimes tearing a directory down while another session still occupies it.

**Core principle: the worktree directory name is a recycled pool label, never a session identity. Never trust it. Bind to the branch, which is stable; the folder path is a slot whose contents change.**

Two symptoms follow, and they are the same root cause:

1. **The rug-pull.** When one session archives, its teardown removes or repoints a directory that a *different* live session is checked into, so the second session's working tree, and any uncommitted work in it, disappears underneath it.
2. **The branch pile-up.** Because slots are repurposed instead of removed with their branch, merged `claude/*` branches accumulate undeleted, alongside the recycled directories.

This is app behaviour, not something a repo convention causes or fully fixes. As of 2026-09 it is tracked upstream in `anthropics/claude-code` as **#91405** ("Worktree pool assigns relaunched sessions to the wrong worktree ... can discard uncommitted work") plus a cluster (#76590, #92084, closed #64605). Search existing issues before filing anything; this is almost certainly already reported.

## When this fires

- A session reports its files gone, or is working against code it did not expect, after another session closed.
- `git worktree list` shows a directory whose name does not match its branch.
- Merged `claude/*` branches are piling up in a repo and nobody deleted them.
- You are about to bulk-clean worktrees or branches across sessions' leftovers.

## When this does NOT fire

- Managing your OWN worktree's lifecycle, or disposing of it at session close: that is `using-git-worktrees`.
- Coordinating shared refs and concurrent edits with peer sessions: that is `multi-agent-repo-coordination`.
- Choosing where on disk a repo or worktree should live: that is `repo-safe-locations`.

## Prove it first

Do not assume recycling from a symptom; confirm it from git's own metadata, which is platform-neutral and needs no app logs.

```
git worktree list --porcelain          # current worktrees and their branches
ls -la .git/worktrees/                 # the registered admin directories
cat .git/worktrees/<dir>/logs/HEAD     # the per-worktree HEAD reflog = the recycling trail
```

The tells:

- A `.git/worktrees/<dir>/logs/HEAD` with **more than one** `checkout: moving ...` entry: the slot has hosted more than one branch.
- A directory whose name matches **neither** its current branch **nor** any branch that ever existed: the name is a pool label, not a session.
- A branch you know a session used, now checked out in a **differently-named** directory: the slot was rebound.

A cleanly created, never-recycled worktree shows a single reflog entry and a name that matches its branch.

## Reap safely

The pile-up is cleaned with the bundled `scripts/reap-worktrees.sh`. It is safe and re-runnable, and its safety story is the whole point:

- It **never** deletes a branch checked out in **any** worktree (a live chip), never touches `main`, and never force-deletes on a plain run.
- **MERGED bucket** (tip is an ancestor of `origin/main`): deleted via `git branch -d` on `--apply`.
- **GONE bucket** (`[gone]` upstream but not ancestor-merged, i.e. squash-merged): only ever **listed**, never auto-deleted, unless you pass `--apply-gone` after eyeballing each against its PR.
- It prunes only worktree admin entries whose directory is already gone.

```
scripts/reap-worktrees.sh                 # dry-run (current repo)
scripts/reap-worktrees.sh --apply         # reap MERGED + prune dead worktrees
scripts/reap-worktrees.sh --apply-gone    # also force-delete the reviewed GONE bucket
scripts/reap-worktrees.sh <repo_path>     # operate on another repo
```

**Run the reap only when chips are quiet.** The checked-out set is a moving target while sessions churn; a branch caught *between* worktrees at the instant of a run looks reapable when it is not. The script re-reads the live checked-out set every run rather than trusting anything cached, but running against a quiet estate is what makes the guard airtight.

## Report it, without duplicating

If you hit a fresh variant worth reporting:

- **Search first.** GitHub's own duplicate detector on the new-issue form surfaces the cluster; the bug is already open as #91405. Do not tick "hasn't been reported" and do not file a duplicate.
- **Add value instead.** A confirmation on a *different platform* (the tracked issue was Windows-first; a macOS or Linux repro matters), or a platform-neutral reflog proof, is worth a comment. A restated mechanism is not.
- **Channel.** The desktop app's "Get support", or `anthropics/claude-code/issues`. Include `git worktree list --porcelain`, the `.git/worktrees/<dir>/logs/HEAD` reflog, and the exact app version.

## Red flags

- Trusting a worktree directory name to tell you which session or branch it holds.
- Running the reap, or any bulk `git worktree`/`git branch -D`, while chips are live.
- `git branch -D` on a `claude/*` branch without first checking it is merged into `origin/main` and not checked out anywhere.
- Assuming archiving a session cleaned up its worktree; it recycles the slot instead, and leaves the branch.
- Filing a new bug for this without searching existing issues; it is already tracked.
- "Fixing" the rug-pull with a SessionEnd hook: the hook lacks the worktree path and branch, and races the app's own pool sweep. Binding sessions to branches is the app-side fix, not a user hook.

## Bottom line

The directory under `.claude/worktrees/` is a recycled slot, not a session. Prove recycling from `.git/worktrees/<dir>/logs/HEAD`, reap merged branches and dead slots only when chips are quiet with the bundled script, and if you report it, confirm it on a new platform rather than duplicating the open upstream issue.
