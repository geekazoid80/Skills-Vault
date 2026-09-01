---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from the current workspace, before executing an implementation plan, when about to create a worktree manually, or when deciding WHICH tree to edit in once a worktree exists. Triggers include "set up a worktree", "isolate this work", "branch off in a worktree", "git worktree add", "worktree for this PR", "worktree vs main clone", "which tree do I edit in", "edited the wrong tree", "dirty main tree". Also fires on the symptoms of having edited the main clone instead of the worktree, which is how most sessions actually meet this - "pull --ff-only aborting", "Aborting due to local changes", "would be overwritten by merge", "Please commit your changes or stash them before you merge", a main clone that refuses to fast-forward after its own PR merged, an uncommitted copy of content that is already on main. Also covers the cost of in-repo placement, where a tool that walks the tree without respecting .gitignore (plain find, grep -r, os.walk, a docs generator, a file-count or licence audit) counts the nested worktree as part of the repo, so prefer git-aware forms or exclude the directory. Also owns worktree DISPOSAL at session close, and corrects the common false premise that something else handles it. Triggers include "clear the worktree", "remove the worktree", "worktree cleanup", "leftover worktrees", "worktree residue", "who cleans up the worktree", "does archiving remove the worktree", "worktree remove refused", "contains modified or untracked files". A worktree is not disposed of for you; ending a session does not remove it and neither does archiving one, so the owning session clears its OWN as the LAST tool call, never a peer's, without --force, pinning any local-only commit to refs/archive first. NOT for choosing where on disk a repo or worktree lives (repo-safe-locations); NOT for peer-session and shared-ref coordination (multi-agent-repo-coordination); NOT for sweeping OTHER sessions' leftovers, which is a separate and expensive audit. Enforces detect-existing-isolation first, prefer-the-native-tool second, edit-in-the-worktree throughout, clear-your-own-at-close, never-fight-the-harness always. Localised lightweight version of obra/superpowers/skills/using-git-worktrees that drops the .worktrees/ fallback machinery and gitignore-verification logic since this vault uses Claude Code's native EnterWorktree tool throughout.
metadata:
  version: 1.3.0
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

Why: native tools handle directory placement, branch creation and harness state tracking, and a natively-created worktree is the only kind the native exit helper can later remove for you. Using `git worktree add` when `EnterWorktree` exists creates phantom state the harness cannot see or manage.

**What the native tool does NOT do is dispose of the worktree when the session finishes.** Read "Remove your own worktree at session close" below before assuming otherwise; that assumption is the single largest source of worktree residue.

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

**The one real cost of placing worktrees in-repo, stated so it is not a surprise: any tool that walks the repo tree WITHOUT respecting `.gitignore` now sees a full second copy of the repo inside it.** Git itself is fine, and so is anything built on git (`git grep`, `git ls-files`, `git clean` without a double `-f`, most linters and formatters that honour ignore files). What is not fine is the large class of tools that just walk a directory:

- a plain `find`, `grep -r`, `rg --no-ignore`, `os.walk`, a shell glob;
- documentation generators, sitemap or index builders, asset pipelines;
- "how many files / lines are in this repo" audits, licence scanners, duplicate-content checks;
- backup or upload jobs pointed at the repo path.

Each of those will count the worktree's content as part of the repo, and a worktree carries the whole tree, so the inflation is roughly a factor of two per live worktree, plus a nested `.git` file that some tools choke on. The failure is quiet and looks like real data: a doubled file count, a duplicate hit for every match, a doc index with everything twice.

Mitigations, cheapest first: prefer the git-aware form of the tool (`git grep` over `grep -r`, `git ls-files | wc -l` over `find | wc -l`); pass the exclusion explicitly when it is not (`--exclude-dir=.claude`, `rg -g '!.claude'`, a `prune` in `find`); and remove worktrees promptly on merge so there is usually nothing nested to hit. If a repo's own tooling cannot be made ignore-aware, that is a genuine reason to keep worktrees out of the tree for that repo, and it is the one case where a sibling is the lesser evil, provided you then check what the parent directory's rules do to it.

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

## Remove your own worktree at session close

**A worktree is not disposed of for you.** Ending a session does not remove it, and neither does archiving
one. The native exit helper only knows about worktrees it created in the CURRENT session, so a session that
resumed into an existing worktree, or that made one by hand because the native tool was unavailable or
resolved to the wrong repository, gets a clean no-op and the directory stays exactly where it was.

The accumulation is quiet. Each leftover is a full second copy of the repository under
`.claude/worktrees/`, indistinguishable from a live workspace, and nothing reports it. They are found only
by someone enumerating the filesystem, and the reason nobody enumerates is that everyone believes the
disposal already happened. One sweep of an estate found nineteen across eleven of sixty-eight repositories,
several belonging to sessions that had been closed for weeks, with nobody having done anything wrong in any
single session.

So the owning session clears its own, while it is still around to know which one is its own.

**Only your own. Never a peer's.** From outside, a live peer's worktree is indistinguishable from abandoned
residue: no process holds it and no file descriptors are open, because a parked session holds neither.
Removing it destroys uncommitted work irrecoverably. If you notice others, report them and leave them
alone. That hazard is precisely why a sweep is expensive, and it is not something to take on at a close.
Reducing what YOU leave behind is the whole of this step.

**It is the LAST tool call of the session.** You cannot remove the tree you are standing in partway through
a turn: the shell's working directory vanishes underneath you and every remaining step is stranded. Finish
everything else first, the commits, the flush, the tracker update, the closing gate, then remove, then
write the closing message from memory without reaching for a tool again.

**Preserve before removing:**

1. **Push anything worth keeping.** A branch that exists on the remote is not at risk.
2. **Pin any commit that exists only locally**, a detached HEAD or a branch never pushed, to a permanent
   ref BEFORE removing anything:

   ```bash
   git -C <canonical> update-ref refs/archive/<date>/<name> <sha>
   ```

   A SHA recorded only in a transcript dies with the transcript, and the reflog expires. Then say in a
   durable place that the ref exists and why, or the next reader meets an unexplained `refs/archive/*`.
3. **Remove without `--force`**, run from the canonical clone rather than from inside the worktree, since
   the shell resets into the worktree on every call and a removal launched from there leaves later calls
   with a missing directory:

   ```bash
   git -C <canonical> worktree remove .claude/worktrees/<name>
   git -C <canonical> worktree prune
   ```

   **A refusal is information, not an obstacle.** The dirty guard declining means the tree holds something
   that exists nowhere else, and it is the last line of defence. Read what it names and resolve it, which is
   a decision for the human per `completion-gate` Layer 4 Step 5, or leave the worktree in place and say so.
   Never `--force` past it on your own initiative.

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
| Session closing and it owns a worktree | Push, pin any local-only commit to `refs/archive/...`, then `worktree remove` without `--force` as the LAST tool call |
| `worktree remove` refused (modified or untracked files) | The guard is right: something exists only there. Resolve with the human, or leave the worktree and say so. Never `--force` |
| A worktree you did not create | Leave it alone. Report it; never remove a peer's |

## Red flags

- Creating a worktree when Step 0 detects existing isolation.
- Counting, indexing or scanning a repo with a tool that does not respect `.gitignore` while a worktree
  is nested inside it, so the worktree's copy is silently included (use `git grep` / `git ls-files`, or
  exclude the directory explicitly).
- Calling `git worktree add` when the harness provides `EnterWorktree`.
- Creating a worktree inside another worktree (nesting).
- Writing into `.claude/worktrees/<x>/` by hand (that path is the harness's, not the user's).
- Skipping baseline test verification on a fresh worktree.
- Removing a worktree this session did not create (provenance check first; a peer's live workspace looks exactly like abandoned residue from outside, and the removal is unrecoverable).
- Assuming a worktree under `.claude/worktrees/` gets disposed of on its own. Ending a session does not remove it and neither does archiving one, so the owning session clears its own at close.
- Clearing your own worktree anywhere other than as the LAST tool call, which strands the rest of the close when the working directory disappears.
- Reaching for `worktree remove --force` after a refusal, instead of reading what the guard named.
- Editing a doc, WORKLOG entry, or README in the main clone when the change is going to ship through a worktree branch.
- A dirty main clone during a worktree chunk (its job is fetch, ff-only pull, read).
- Reaching for `git reset`, `checkout -f`, or a forced pull to clear "Your local changes would be overwritten by merge".
- Discarding a modified path in a shared clone without first confirming you wrote it and that the content already landed.

## Bottom line

Detect first, prefer native, never fight the harness. The manual `git worktree add` path is a last-resort fallback, not the default. Once a worktree exists, edit in it: a change made in the main clone strands an uncommitted twin of content that lands by another path, and the post-merge `pull --ff-only` aborts on it. Recover with `git restore` only for content you wrote and that is already merged; otherwise surface it.
