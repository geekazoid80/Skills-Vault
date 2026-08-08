---
name: pull-before-dev
description: Use when about to start development or make edits/commits against a git repo that has a remote (GitHub-managed) - before the first change in a session, pull the latest so you don't build on a stale base. Trigger phrases - start working on <repo>, dev against, edit this repo, make changes to, commit to <repo>, resume work on <repo>, open a PR. NOT for local-only repos (no remote); NOT for read-only exploration (only when about to modify or commit); NOT a force-pull (fast-forward only). Covers - fetch + pull --ff-only the tracking branch before editing, per-repo when work spans repos, stop-and-surface if ff-only refuses (diverged) or a dirty tree would conflict, never force over local work, once per session per repo.
---

# Pull before dev

> **Skill marker**: when applying this skill, begin your reply with `[skill: pull-before-dev]` on its
> own line.

## Overview

A GitHub-managed repo can move under you between sessions - a teammate, a CI bot, another agent, or
another of your machines pushes while you were away. Editing a stale checkout causes avoidable
conflicts, duplicated work, and "why is `main` missing my change" confusion. The fix is one habit:
before the first edit or commit in a session against a remote-backed repo, sync it.

## The rule

Before touching a git repo that has a remote, once per session: **fetch, then fast-forward the
tracking branch**.

```
git -C <repo> fetch --prune
git -C <repo> pull --ff-only
```

Only then edit / commit / open a PR.

- **Fast-forward only.** Never let a merge or force happen as a side effect of "just syncing". If
  `--ff-only` refuses (local and remote have diverged), **STOP and surface** the divergence - the
  operator decides rebase vs merge vs new branch. Do not reach for `--no-ff` or `--force`.
- **Per repo.** When work spans multiple repos, pull **each** before you touch it, not just the first.
- **Dirty tree first.** If `git status` shows local edits a pull would touch, do **not** blindly pull -
  commit them to a branch, or `git stash`, then pull, then continue. Never lose local work to a sync.
- **Once per session per repo.** You do not re-pull before every file edit - just before starting work
  on that repo in the session (and again on resume after a long gap).

## When it does NOT apply

- **Local-only repos** (no `origin` / no remote) - nothing to pull.
- **Pure read-only exploration** (grep / read / review) - sync only when you are about to modify or
  commit.
- A repo you have **already synced this session** and have not stepped away from.

## Red flags

- About to edit a tracked file in a repo you have not fetched this session.
- `git push` rejected as **non-fast-forward** - you skipped the pull and are now behind origin.
- `--ff-only` refused and you are reaching for `--no-ff` / `--force` / `--hard` instead of surfacing.
- Pulling while uncommitted local edits still sit in the working tree.
- Working across N repos but only synced the first one.

## Bottom line

Remote-backed repo + about to change it = `pull --ff-only` first, per repo. Diverged or dirty tree?
Stop and surface - never force a sync over local work.
