---
name: multi-agent-repo-coordination
description: "Use before the first edit, commit, or push in any git repo that a concurrent agent or person may also be touching this session - peer Claude sessions, a shared estate or knowledge base, or a repo whose `.git` is shared by other worktrees. Trigger phrases and symptoms - \"worktree\", \"concurrent session\", \"peer is editing\", \"shared checkout\", \"multi-agent\", a branch ref that shuffled mid-commit, a commit that landed on the wrong branch, \"cannot lock ref\", \"'<base>' is already used by worktree\", a push that seemed to vanish, `git rev-parse origin/<branch>` failing after a push that landed, two local clones of one repo under different names, \"rename the repo directory\", \"mv the clone\", a folder-name cleanup or space-to-hyphen rename batch, a session whose cwd vanished mid-run, \"no such file or directory\" right after a directory was moved, a stale clone serving old code, a parallel session that merged the same feature, a merged change that reads back as absent from whatever consumes the repo, \"the rebuild did not pick it up\", a symlink farm or editable install or PATH entry pointing into a clone, a clone left parked on a feature branch. Covers worktree-per-session, ff-only sync, branch-per-task, verify-the-pushed-ref via `ls-remote`, SHA recovery after a ref shuffle, append-not-rewrite for shared docs and memory, clone-not-assume (one canonical local clone), treating a clone that something resolves through by path as a live serving surface (it serves the checked-out working tree, so branch in a worktree and keep it on main; regenerating the integration does not rescue it and `pull --ff-only` refuses), and treating a repo-directory rename as a multi-session operation (check every session cwd before each move, record the old-to-new mapping durably). NOT for solo repos with no concurrent actors; NOT for choosing where on disk a repo lives (that is repo-safe-locations). Composes with using-git-worktrees and pull-before-dev."
metadata:
  version: 1.3.1
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
- Before renaming or moving any repo directory in a working root other sessions may be using.
- Before branching in a clone that something resolves through by path, and when a change you know merged reads back as absent through such a consumer.

## When this does NOT fire

- Solo repos with no concurrent actors: the isolation ceremony is overhead you do not need. **One carve-out**: a clone that something else on the machine resolves through (a symlink farm, an editable install, a `PATH` or config entry into the tree) has consumers even when it has no peers, so the worktree rule still applies to it. See A clone something resolves through is a live serving surface.
- Choosing where on disk to put a repo, or diagnosing a repo that reverts because of a two-way file sync (iCloud, NAS rsync, Syncthing): that is `repo-safe-locations`.
- Pure read-only exploration with no intent to modify.

## Worktree per task

Never edit in a shared main checkout. Work in your own linked worktree so a peer's checkout cannot move your branch under you (a worktree has its own HEAD and index). Prefer the harness-native tool per `using-git-worktrees`; the manual form is:

```
git -C <repo> fetch --prune origin main
git -C <repo> worktree add .claude/worktrees/<task> -b <area>/<task> origin/main
# edit, commit, push, open the PR in that worktree, then:
git -C <repo> worktree remove .claude/worktrees/<task>
```

**Put the worktree UNDER the repo at a gitignored path, never beside it as `../wt-<task>`.** A sibling
inherits the parent directory's treatment rather than the repo's, so it silently escapes every protection
scoped to the repo path at once: backup roots and sync excludes that name the repo, ignore rules, and
anything else keyed on that path. `using-git-worktrees` carries the full reasoning and the worked case.

All Edit / Write / Read use the worktree-prefixed absolute path, never the main-repo path. Editing the main clone instead also strands an uncommitted copy that blocks its post-merge `pull --ff-only`; `using-git-worktrees` carries that rule, its symptoms, and the restore-then-pull recovery.

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

## A clone something resolves through is a live serving surface

Some clones are not only a place you work. Something else on the machine reads **through a path into the tree**: a symlink farm that links `<clone>/<item>/` into a consumer directory, an editable install (`pip install -e`), a workspace or `node_modules` link, a `PATH` entry into the repo's `bin/`, a config `include` naming a file in the tree, a daemon whose working directory is the clone.

Every one of those resolves a **path**, and a path points at the **working tree**, not at a ref. So the checked-out branch, plus any uncommitted edit, is what all of those consumers see. Branch-per-task inside such a clone quietly republishes an unreviewed branch to everything on the machine, for every user and every session, for as long as it stays checked out.

Three properties make it hard to catch:

- **Nothing errors.** The consumer loads successfully; it just loads the wrong content. There is no failure to investigate, only behaviour that seems off.
- **Regenerating the integration does not fix it.** Re-running the linker, builder, or installer relinks the same paths, so the rebuild reports success and changes nothing about what is served.
- **The obvious recovery is refused.** `git pull --ff-only` refuses outright when HEAD is not the branch you meant to update, so the reflex of "pull and rebuild" fails in a way that reads as a sync problem rather than a checkout problem.

**The tell, worth reaching for early: a change you know merged reads back as absent through the consumer, while the repo itself looks perfectly healthy.** Before hunting the merge, ask what the consumer actually resolves:

```
git -C <clone> rev-parse --abbrev-ref HEAD   # the branch every consumer is being served
git -C <clone> status --porcelain             # uncommitted edits are served too
```

- **Identify the serving clones before you branch in one**, and do the work in a linked worktree with the canonical clone left parked on `main`. This is why worktree-per-task matters even with no peer anywhere near the repo: the isolation is protecting the consumers, not only the refs.
- **Move the ref without touching the tree** when someone else may hold the checkout: `git fetch origin main:main` fast-forwards the local `main` ref and leaves the working tree alone. Only checking `main` out makes the consumers current, and that IS a shared-surface act, so confirm the tree is clean and the branch's PR is merged before doing it.
- **A clone deliberately parked on a branch is a legitimate state.** Exercising a change through the real consumer is often the only way to learn whether it works. What makes it a defect is being parked on an already-merged branch, or being parked with nobody told. Record the park, its owner, and the condition for returning to `main` somewhere the person who meets the surprising behaviour will actually look, not only in the parking session's transcript.

## Renaming or moving a repo directory is a multi-session operation

Renaming a repo directory is not a local act when several sessions run at once. Any process whose working directory is at or under the moved path is left holding a directory that no longer exists under that name, and nothing announces it: the session does not fail at the moment of the `mv`, it fails at its next filesystem call, later and with an error that points nowhere near the rename.

Git itself survives the move, and a GitHub-side repo rename leaves a redirect so remotes keep working. What does not survive is the process-level cwd, linked-worktree metadata, and every absolute path already written into a plan file, a memory note, or a PR body.

Before moving any repo directory, for EACH directory in scope:

1. **Confirm no session is working in it.** Session working directories and running state are discoverable (`mcp__ccd_session_mgmt__list_sessions` returns `cwd` and `isRunning` per session); a match AT or UNDER the path counts as occupied. Re-verify immediately before each `mv`, not once for the whole batch: a session idle when you started the sweep can wake mid-batch.
2. **Confirm the tree is clean and no linked worktree points into it** (`git -C <dir> status --porcelain`, `git -C <dir> worktree list`). A linked worktree records absolute paths at both ends (`.git/worktrees/<name>/gitdir` and the main repo's list), so moving either end breaks the link. Use `git worktree move` to relocate one, and `git worktree repair` to fix a link already broken by a hand-move.
3. **For an occupied directory, message the owning session** to pause and re-enter the new path afterwards, or defer that directory to a later pass. Do not move it and hope.

`isRunning: false` means idle, not finished. A recently-active session still counts as occupied; it resumes into the path it remembers.

**A move also breaks build artefacts that recorded the old path, and those fail silently long afterwards.** A Python virtualenv is the common case: every console-script wrapper in its `bin/` hard-codes an absolute interpreter path at creation time, so after the directory moves, `./.venv/bin/pytest`, `./.venv/bin/pip` and the rest die with `No such file or directory` on a path that no longer exists. Three properties make this mislead badly:

- **The interpreter beside them is fine.** `.venv/bin/python -m pytest` works, so it reads as a broken test-runner install rather than a moved directory, and the obvious fix (reinstall the tool) fails too, because `pip` is one of the broken wrappers.
- **The venv is usually gitignored**, so the damage lives on the host and can never appear in a diff, a review, or CI.
- **A genuinely fresh clone is unaffected**, so verifying the bootstrap the honest way, in a new venv, reports green while every existing clone stays broken.

Detect it by scanning for **`pyvenv.cfg`**, not for `.venv/` under repo roots: a repo-directory walk misses environments inside linked worktrees, which is exactly how a sweep reports fewer environments than exist. For each one found, test whether the path each wrapper actually execs still resolves, rather than matching against the old name you expect. Repair by recreating the environment rather than editing the wrappers, and capture the installed set first (`.venv/bin/python -m pip freeze`) so a project with no requirements file does not lose its dependency list along with its wrappers.

The same shape applies to anything else that recorded the absolute path: check the environment's own `home` value still resolves, and check any scheduled job that invokes an interpreter by full path, since a cron entry calling a moved venv fails on its next run with nobody watching.

Afterwards, record the old-name-to-new-name mapping somewhere durable (project memory, the tracking task, the estate's coordination board), not only in the moving session's transcript. A later session reading a stale absolute path needs a way to find where it went; without the mapping it concludes the repo is missing and re-clones it, which is exactly how the duplicate twin above appears in the first place.

## Concurrent duplicate PR: check main, close yours, do not clobber

When a change you just built hits a "not mergeable" conflict, a parallel session may have already merged the same feature. Before assuming an unrelated conflict, `git log --oneline origin/main` for a commit whose **subject** matches your feature. If found, close YOUR PR as a duplicate (comment plus delete branch) and pivot to the shared outcome (deploy or live-test the merged version); never force-merge over the landed work. Detection is not always possible upfront (a true race), so gate on the artifact.

## `gh pr merge --delete-branch` from a worktree

`gh pr merge <N> --delete-branch` run from inside a linked worktree of the same repo errors `'<base>' is already used by worktree` (gh cannot check out the base held by the canonical clone), but the **API merge still succeeds**. Verify `state=MERGED`, then clean up by hand: `worktree remove`, `pull --ff-only` the canonical base, `branch -D` plus `push origin --delete` the head. Gate on the merged-state artifact, not the `gh` exit code.

## Deciding a branch is finished: the tree test and the PR state answer different questions

Before deleting any branch in a shared repo, know which question you are asking. `git merge-tree --write-tree <base> <branch>` compared against the base tree answers **"would merging this change the base"**. That is not the same as **"is this branch finished"**, and the gap runs both ways:

- **A landed branch can read as unmerged work.** After a squash merge the base keeps moving; once a later commit touches the same files, merging the old branch would *revert* them, so the trees differ and the branch looks like work worth keeping. It is in fact the safest to delete, and the most dangerous to keep, because keeping it invites someone to merge a revert.
- **A live branch can read as unremarkable.** A branch whose PR is still **open**, possibly with a peer working in it, tests exactly like a spent one.

So resolve the PR state, and resolve it **at the moment of deletion** rather than when you audited, because a peer can open or merge one in between. Delete only on a merged PR; skip an open one; treat "no PR ever opened" as needing a human.

Then confirm the local tip is what actually merged, by comparing the branch tip against the PR's head ref. A local branch carrying commits *beyond* its merged PR head is indistinguishable from a fully-landed one under every other test, and that is the case where deleting loses real work.

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
- Renaming or moving a repo directory without first checking whether any session's cwd is at or under it.
- Reading `isRunning: false` as "finished" rather than "idle, and will resume into the old path".
- Hand-moving a directory a linked worktree points into, without `git worktree move` or a follow-up `repair`.
- Completing a batch rename without recording the old-name-to-new-name mapping anywhere durable.
- Moving or renaming a repo directory without checking what recorded its absolute path (virtualenv wrappers, scheduled jobs, interpreter paths).
- Scanning for `.venv/` under repo roots instead of for `pyvenv.cfg`, and so missing environments inside linked worktrees.
- Counting or scanning a repo with an ignore-blind tool while a worktree is nested in it, so the count
  or the match list silently doubles (see `using-git-worktrees`).
- Creating a worktree as a sibling (`../wt-<task>`) instead of under the repo, so it inherits the parent directory's backup, sync and ignore rules rather than the repo's.
- Branching in a clone that something resolves through by path, so an unreviewed branch is served machine-wide for as long as it stays checked out.
- Re-running a linker, builder, or installer to "refresh" a consumer that resolves a path, when the checked-out branch is what actually decides the content.
- Reading "the merged change is missing from the consumer" as a merge or sync problem before checking what branch the clone is on.
- Leaving a clone parked on a branch with no record of who parked it, why, or when it returns to `main`.
- Deleting a branch on the tree test alone, without resolving its PR state at the moment of deletion.
- Reading a `merge-tree` difference as unmerged work when the base has simply moved on past a squash merge.

## Bottom Line

Assume a peer is changing the shared repo right now. Isolate in your own worktree and branch, sync ff-only, and verify every push against `ls-remote` server truth, not the push exit code. On a ref shuffle, push the SHA explicitly and re-anchor. Append, do not rewrite, shared docs and memory, and re-read them fresh at each boundary. Keep exactly one canonical local clone; dedup-scan by origin, determine canonical by state not name, and Trash (never `rm -rf`) the stale twin. Where something resolves through a clone by path, it is serving that clone's working tree, so keep it on `main` and branch in a worktree; a merged change reading back as absent through a consumer is a checkout question before it is a merge one. Before force-merging a conflict, check whether a peer already shipped it. Treat renaming or moving a repo directory as a multi-session operation: check every session's cwd immediately before each move, and record the mapping durably afterwards. Composes with `using-git-worktrees` (creation) and `pull-before-dev` (sync).
