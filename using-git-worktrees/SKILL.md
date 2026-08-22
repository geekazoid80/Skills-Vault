---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from the current workspace, before executing an implementation plan, when about to create a worktree manually, or when deciding WHICH tree to edit in once a worktree exists. Triggers include "set up a worktree", "isolate this work", "branch off in a worktree", "git worktree add", "worktree for this PR", "worktree vs main clone", "which tree do I edit in", "edited the wrong tree", "dirty main tree". Also fires on the symptoms of having edited the main clone instead of the worktree, which is how most sessions actually meet this - "pull --ff-only aborting", "Aborting due to local changes", "would be overwritten by merge", "Please commit your changes or stash them before you merge", a main clone that refuses to fast-forward after its own PR merged, an uncommitted copy of content that is already on main. NOT for choosing where on disk a repo or worktree lives (repo-safe-locations); NOT for peer-session and shared-ref coordination (multi-agent-repo-coordination). Enforces detect-existing-isolation first, prefer-the-native-tool second, edit-in-the-worktree throughout, never-fight-the-harness always. Localised lightweight version of obra/superpowers/skills/using-git-worktrees that drops the .worktrees/ fallback machinery and gitignore-verification logic since this vault uses Claude Code's native EnterWorktree tool throughout.
metadata:
  version: 1.1.0
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

If the harness has no worktree tool and you genuinely need a manual worktree, use `git worktree add` against an explicit branch name.

**Place it UNDER the repo, at a gitignored path, not beside it.** `<repo>/.claude/worktrees/<branch>` is the default; a project with its own convention (`.worktrees/<branch>`) is equally fine. What matters is that the worktree sits inside the repo directory.

Why, and this is the part that bites: **a sibling worktree inherits the PARENT directory's treatment, not the repo's.** Every protection scoped to the repo path stops at its boundary, so `../wt-<branch>` silently opts out of all of them at once:

- backup and sync rules that name the repo (`--exclude='/MyRepo/'` does not match `MyRepo-worktrees/`, and a backup job listing `MyRepo` as a root does not cover a sibling);
- ignore rules, since the parent directory is governed by whatever is above it, not by the repo's `.gitignore`;
- anything keyed on the repo path at all, including permissions and tooling that resolves paths into the clone.

A worktree under the repo inherits all of them for free, and being gitignored keeps it out of the index. Worked case: a vault whose repo sat directly inside a two-way-synced folder had every `../wt-<task>` worktree land in that synced folder with live `.git` state, which reverted refs mid-session and resurrected deleted worktrees; the fix was placement, not more excludes.

**Put the ignore rule in the tracked `.gitignore`, not `.git/info/exclude`.** `info/exclude` is local-only and never travels, so a cold clone would show every worktree as untracked and the convention would quietly fail for the next person.

Do not hand-write files into a directory the harness manages, `.claude/worktrees/<harness-managed-name>/`; create your own named worktree there instead.

If `git worktree add` fails with a permission error (sandbox denial), tell the user the sandbox blocked worktree creation and you are working in the current directory instead.

## Edit in the worktree, not the main clone

Once the shipping path is a worktree branch and a PR, **every edit belongs in the worktree**. Editing the main clone first leaves an uncommitted copy of content that is about to reach `main` by a different path, and once the PR merges, `pull --ff-only` in the main clone aborts:

```
error: Your local changes to the following files would be overwritten by merge:
        docs/design/ot-assets.md
Please commit your changes or stash them before you merge.
Aborting
```

The two copies are identical in intent, but git cannot know that, so it refuses the fast-forward to protect the local edit. Nothing is lost, but the block has to be reasoned about from scratch every time, and "is it safe to discard this?" is exactly the question that goes wrong in a tree that also holds someone else's uncommitted work.

**Decide the shipping path first.** If it is a PR, create the worktree, then edit inside it. Never make the change in the main clone intending to route it through the branch later.

**Docs and bookkeeping are where this actually bites.** WORKLOG entries, design notes, READMEs. Code edits go to the worktree without thinking; doc edits feel incidental, so reflex puts them in the main tree.

**During a worktree chunk the main clone has exactly one job: stay clean and current.** Fetch, `pull --ff-only`, read. A dirty main tree during worktree work is an anomaly to investigate, not a normal working state.

### Recovery once the slip has happened

```bash
git -C <main-clone> status --short      # which paths are modified
git -C <main-clone> diff -- <path>      # confirm the content is yours and already merged
git -C <main-clone> restore <path>
git -C <main-clone> pull --ff-only
```

`git restore` is safe here **only** because the content is your own and is already on `main`. Two hard limits:

- **Never restore a file you did not write.** From the outside, a peer's uncommitted work looks exactly like your own stranded copy.
- **Never `git reset` the tree to clear the block.** It discards every modified path, including a peer's.

If the modified path is not yours, or you cannot confirm its content already landed, stop and surface it rather than discarding.

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
| No native tool | Manual `git worktree add` to a gitignored path UNDER the repo (`<repo>/.claude/worktrees/<branch>`), never a sibling |
| Permission error on create | Sandbox fallback; work in place; report |
| Tests fail at baseline | Report failures; ask before proceeding |
| Change ships via a worktree branch and PR | Edit in the worktree; main clone stays clean and current |
| `pull --ff-only` aborts on a locally-modified file | Confirm the content is yours and merged, then `git restore <path>` and pull |
| The modified path is not yours, or you cannot confirm it landed | Stop and surface; never `git reset` the shared tree |

## Red flags

- Creating a worktree when Step 0 detects existing isolation.
- Calling `git worktree add` when the harness provides `EnterWorktree`.
- Creating a worktree inside another worktree (nesting).
- Writing into `.claude/worktrees/<x>/` by hand (that path is the harness's, not the user's).
- Skipping baseline test verification on a fresh worktree.
- Removing a worktree the harness created (provenance check first; if path is under `.claude/worktrees/`, the harness owns cleanup).
- Editing a doc, WORKLOG entry, or README in the main clone when the change is going to ship through a worktree branch.
- A dirty main clone during a worktree chunk (its job is fetch, ff-only pull, read).
- Reaching for `git reset`, `checkout -f`, or a forced pull to clear "Your local changes would be overwritten by merge".
- Discarding a modified path in a shared clone without first confirming you wrote it and that the content already landed.

## Bottom line

Detect first, prefer native, never fight the harness. The manual `git worktree add` path is a last-resort fallback, not the default. Once a worktree exists, edit in it: a change made in the main clone strands an uncommitted twin of content that lands by another path, and the post-merge `pull --ff-only` aborts on it. Recover with `git restore` only for content you wrote and that is already merged; otherwise surface it.
