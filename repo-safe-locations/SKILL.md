---
name: repo-safe-locations
description: "Use when choosing where on disk to put a git repo or programming project - cloning, `git init`, setting up a dev workspace - on any host that also runs a file sync (iCloud Desktop & Documents, NAS rsync, Syncthing, Dropbox, OneDrive). ALSO use when diagnosing a repo that reverts mid-session - working-tree files roll back to stale versions, `.git`/HEAD/branch refs shuffle, a `reset: moving to HEAD` you did not run, a worktree registry reverts, stale files reappear, ` 2.md` conflict copies show up, or CI `--frozen-lockfile` fails while local passes. Trigger phrases and symptoms - \"where should this repo live\", \"clone into\", \"git init here\", \"repo keeps reverting\", \"my edits vanished\", \"files rolled back\", \"iCloud\", \"NAS sync\", \"Syncthing\", \"two-way sync\". Iron rule - never place a live `.git` under a TWO-WAY file sync. Covers the preferred safe homes, the verify-before-drop checklist (enumerate every bidirectional sync), the backup model (GitHub is SoT for committed code, one-way Mac->NAS for uncommitted WIP), and the mid-session-revert recovery. NOT for a ref shuffle caused by a peer session sharing the `.git` (that is multi-agent-repo-coordination). Composes with multi-agent-repo-coordination and pull-before-dev."
metadata:
  version: 1.0.1
---

# Repo Safe Locations

> **Skill marker**: When applying this skill, begin your reply with `[skill: repo-safe-locations]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

File-level sync races git's own atomic ref updates. A repo whose `.git` lives under a **two-way** file sync (iCloud Desktop & Documents, a bidirectional NAS rsync, Syncthing, Dropbox, OneDrive) gets its working-tree files AND its refs reverted mid-session, silently and non-deterministically, because the sync copies an older cached copy back over live state. Edits that passed a test minutes ago vanish; a branch ref jumps back to `origin/main`; a relocated worktree registry rolls back.

**Iron rule:** never place a live `.git` under a two-way file sync. Genuine documents can sync both ways; live repos cannot. Choose the location up front, because moving a repo after the corruption starts is a cleanup, not a prevention.

## When this fires

- Choosing where to clone or `git init` a repo, or setting up a dev workspace, on a host that runs any file sync.
- Diagnosing a repo that reverts mid-session (see the symptom list in the description).

## When this does NOT fire

- A ref shuffle caused by a **peer session** that shares the same `.git` (a concurrent worktree or checkout): that is a coordination problem, use `multi-agent-repo-coordination`. This skill is about the FILE-SYNC cause, which reverts even with no peer present.
- Worktree creation mechanics: that is `using-git-worktrees`.

## Preferred safe homes

- `~/Documents/Programming` on this estate is **one-way NAS-backed** (Mac -> NAS backup only), so it is safe for live repos. This is the default home for work repos here.
- `~/dev` or `~/Developer` are **unsynced**; safe, with GitHub as the backup.
- Avoid `~/Documents` root, `~/Desktop`, and any tree under a two-way sync. On macOS, `~/Desktop` and `~/Documents` are the exact folders iCloud Desktop & Documents syncs, so a repo dropped there is under two-way sync by default.
- Avoid a small tmpfs for large clones (the NUC `/tmp` is ~293 MB; a large clone dies "No space left"); use a disk-backed, configurable work dir.

## Verify before you drop a repo (checklist)

Before cloning into a candidate location, confirm no two-way sync covers it. Do NOT stop at "is iCloud on?", enumerate EVERY bidirectional sync:

1. **iCloud Desktop & Documents:** `brctl status` shows sync activity; check whether `~/Documents` is a real directory or a CloudDocs firmlink (`ls -la ~ | grep Documents`, and `readlink`), which means iCloud owns it.
2. **A NAS / rsync launchd job:** `launchctl list | grep -i sync`, then READ the script it runs. Confirm it is one-way (Mac -> NAS backup) and that `.git` is not a synced path. A step that pulls NAS -> Mac additively (the two-way shape) copies the NAS's older `.git` back onto the Mac.
3. **Syncthing / Dropbox / OneDrive:** check each is not configured over the candidate tree.

If any two-way sync covers the location, pick a different home. If the sync can be made one-way or the tree excluded, do that first, then verify again.

## The backup model (so "no two-way sync" does not mean "no backup")

- **GitHub / origin is the source of truth for committed code.** Commit and push early; a pushed blob is immune to a local revert.
- **A one-way Mac -> NAS backup** captures the uncommitted and gitignored working state (WIP, local config) that GitHub does not hold. One-way only.
- **Never two-way** over a live `.git`. That is the whole rule; the backup goals are met without it.

## Diagnosing and recovering a mid-session revert

Symptoms: a subset of edited files roll back to pre-edit content while other edits from the same batch persist; `git reflog` shows an external `reset: moving to HEAD`; the `git worktree` registry reverts a relocated worktree; ` 2.md` conflict copies appear; CI fails `--frozen-lockfile` (a stale committed lockfile) while a local non-frozen install passes.

Recovery, until the clone itself is moved off the synced tree:

- **Treat origin as the only reliable source of truth.** After any anomaly, re-anchor with `git reset --hard <sha>` to a known-good commit and re-verify against origin with `git ls-remote` (never trust local `origin/<branch>` or `rev-parse HEAD` alone).
- **Verify the COMMITTED tree, not just the working tree**, before pushing: `git show <sha>:<path>`, and for a lockfile-bearing repo `<pkg-manager> install --frozen-lockfile`. A green local test does not prove the commit is good, because local tooling uses the working lockfile, not the frozen one.
- **Re-grep edited files right before commit;** re-apply and amend if they reverted.
- **Relocating a linked worktree out of the synced tree stabilises the working tree but is NOT sufficient:** branch refs and the worktree registry live in the COMMON `.git`, still under the sync, so ref-shuffles continue. The real fix is to move the WHOLE clone off the synced tree (`~/dev` / `~/Developer`).
- **For a SHARED checkout a peer session also uses, relocating is an operator coordination decision, not a unilateral move.** Surface it; do not silently relocate a shared repo.

Full incident evidence and the recovery walk-through live in the `feedback-icloud-worktree-revert` memory entry; this skill is the placement rule that prevents the incident.

## Red Flags

- About to clone or `git init` under `~/Documents` root, `~/Desktop`, or any two-way-synced tree.
- Assuming "iCloud is off" means no sync; a NAS rsync, Syncthing, Dropbox, or OneDrive can be the two-way culprit.
- Trusting a green local test as proof a commit is good when a file-sync revert may have staled the working tree or lockfile.
- Relocating only the linked worktree and expecting ref-shuffles to stop (the common `.git` is still synced).
- Silently moving a SHARED clone off the synced tree without surfacing it to the operator.
- Cloning a large repo onto a small tmpfs (`/tmp`) and hitting "No space left".

## Bottom Line

Never put a live `.git` under a two-way file sync. Prefer `~/Documents/Programming` (one-way NAS-backed) or `~/dev` / `~/Developer` (unsynced + GitHub). Before dropping a repo, enumerate every bidirectional sync over the location and confirm none covers it. Back up via GitHub (committed code) plus a one-way Mac -> NAS (uncommitted WIP), never two-way. If a repo is already reverting, treat origin as the only source of truth, commit and push early, re-anchor with `git reset --hard <sha>` + `ls-remote`, and move the whole clone off the synced tree (a shared clone only with operator sign-off). Composes with `multi-agent-repo-coordination` (the peer-session cause) and `pull-before-dev`.
