---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from the current workspace, before executing an implementation plan, or when about to create a worktree manually. Triggers include "set up a worktree", "isolate this work", "branch off in a worktree", "git worktree add", "worktree for this PR". Enforces detect-existing-isolation first, prefer-the-native-tool second, never-fight-the-harness always. Localised lightweight version of obra/superpowers/skills/using-git-worktrees that drops the .worktrees/ fallback machinery and gitignore-verification logic since this vault uses Claude Code's native EnterWorktree tool throughout.
metadata:
  version: 1.0.0
---

# Using Git Worktrees

> **Skill marker**: When applying this skill, begin your reply with `[skill: using-git-worktrees]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Ensure work happens in an isolated workspace. Detect existing isolation first; prefer the harness's native worktree tool over manual `git worktree add`.

**Core principle:** never fight the harness. If isolation is already provided, use it. If a native tool exists, use it. The manual fallback is a last resort.

## Step 0: Detect existing isolation

Before creating anything, check whether you are already in a linked worktree:

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**Submodule guard.** `GIT_DIR != GIT_COMMON` is also true inside git submodules. Before concluding "already in a worktree", verify you are not in a submodule:

```bash
git rev-parse --show-superproject-working-tree 2>/dev/null
```

If that prints a path, you are in a submodule, not a worktree; treat as a normal repo.

**If `GIT_DIR != GIT_COMMON` and not a submodule:** you are already in a linked worktree. Skip to "Project setup" below. Do NOT create another worktree (nesting worktrees creates phantom state the harness can't see).

**If `GIT_DIR == GIT_COMMON` or you are in a submodule:** you are in a normal repo checkout. Continue to Step 1 if isolation is wanted.

## Step 1: Use the native tool first

Claude Code provides `EnterWorktree`. Use it. Do not call `git worktree add` directly when the native tool is available.

Why: native tools handle directory placement, branch creation, harness state tracking, and cleanup automatically. Using `git worktree add` when `EnterWorktree` exists creates phantom state the harness cannot see, can't manage, and won't clean up at session end.

## Step 2: Manual fallback (only if no native tool)

If the harness has no worktree tool and you genuinely need a manual worktree, use `git worktree add` against an explicit branch name. Place the worktree somewhere outside the main checkout (e.g. `~/tmp/<branch>` or a project-local `.worktrees/<branch>` directory if the project conventions support it). The vault itself uses `.claude/worktrees/<harness-managed-name>/`; do not write into that directory by hand.

If `git worktree add` fails with a permission error (sandbox denial), tell the user the sandbox blocked worktree creation and you are working in the current directory instead.

## Project setup

Once you are in the right workspace (existing or freshly created), auto-detect and run the project's setup:

| Stack | Command |
|---|---|
| Node.js | `npm install` (or `pnpm install` / `yarn install` per lockfile) |
| Rust | `cargo build` |
| Python | `pip install -r requirements.txt` or `poetry install` per lockfile |
| Go | `go mod download` |

Skip if no relevant manifest exists.

## Verify clean baseline

Before claiming the worktree is ready, run the project's test command (or build, if no test suite). If tests fail at baseline, report the failures; do not silently proceed. The user needs to know whether failures are pre-existing or introduced.

## Quick reference

| Situation | Action |
|---|---|
| `GIT_DIR != GIT_COMMON` and not submodule | Already in a worktree; skip creation |
| In a submodule | Treat as normal repo |
| Native `EnterWorktree` tool available | Use it; do NOT call `git worktree add` |
| No native tool | Manual `git worktree add` to an out-of-tree path |
| Permission error on create | Sandbox fallback; work in place; report |
| Tests fail at baseline | Report failures; ask before proceeding |

## Red flags

- Creating a worktree when Step 0 detects existing isolation.
- Calling `git worktree add` when the harness provides `EnterWorktree`.
- Creating a worktree inside another worktree (nesting).
- Writing into `.claude/worktrees/<x>/` by hand (that path is the harness's, not the user's).
- Skipping baseline test verification on a fresh worktree.
- Removing a worktree the harness created (provenance check first; if path is under `.claude/worktrees/`, the harness owns cleanup).

## Bottom line

Detect first, prefer native, never fight the harness. The manual `git worktree add` path is a last-resort fallback, not the default.
