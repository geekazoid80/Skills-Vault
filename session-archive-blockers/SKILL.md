---
name: session-archive-blockers
description: "Use when a Claude Code session refuses to archive, hangs on archive, or the archive/close attempt errors out blaming a running agent, a running background agent, or a background task as the reason it cannot end. Also fires on: archive stuck, archive won't complete, can't archive this session, orphaned background task, zombie subagent, nested background process, a TaskOutput 'Running background agent' entry with no matching ListAgents row, or a subagent's own completion notification saying its background work is still running. Covers the ordered checklist of known blockers to rule out (own session parentSessionId/detached state, Remote Control attachment, ListAgents rows still running, orphaned nested background tasks spawned BY a subagent that outlive its completion notification) before ever concluding the session cannot self-archive and must be closed from the GUI, plus the mandatory rule that any newly discovered blocker gets appended to this same checklist before the session finishes. NOT for the park-versus-archive distinction itself (pre-park-externalisation), NOT for worktree recycling between chips (chip-worktree-hygiene)."
metadata:
  version: 1.0.0
---

# session-archive-blockers

> Skill marker: when this fires, emit `[skill: session-archive-blockers]` on its own line.

## Overview

An archive attempt that fails or hangs, citing "a running agent run" or "a background task", looks
opaque but is usually diagnosable from inside the session itself. This skill is a living, ordered
checklist of every known blocker. Walking it is cheap; declaring "cannot archive, please close it
from the GUI" without walking it first pushes avoidable manual work onto the user.

**Core principle:** the checklist below is not exhaustive and is not meant to be. Every session that
finds a genuinely new blocker adds it here before finishing, so the next session inherits a longer
list instead of re-discovering the same thing from scratch.

## The iron rule

> Before telling the user the session cannot archive itself and must be closed from the GUI, walk
> the full checklist below in order. Only fall back to a GUI-close ask once every angle has been
> checked (or ruled out) AND, if a new cause was found along the way, it has been appended to this
> checklist.

## The checklist, in order

### 1. Read the error text literally

The refusal's own wording is the strongest clue and is easy to skim past under archive-retry
pressure. Does it name a specific task id? Does it say "agent run" (points at a spawned agent) or
"background task" (points at the harness's task registry, which is broader than ListAgents)? Quote
it back before diagnosing further.

### 2. Check this session's own parent/detach state

Call the session-lookup tool on `'self'` and read `parentSessionId` and `detached`. A session with
`detached: false` and a `parentSessionId` set is a non-detached side session of a parent. This can
be the cause, but it is just as often a red herring: trace the parent (look it up by that id). If
the parent is itself already archived or not running, this angle is ruled out, not confirmed. Do not
stop here just because the field is populated.

### 3. Remote Control attachment

If Remote Control is enabled for this account, a remote client still attached to the session can
block archiving until it detaches. If Remote Control is not enabled at all for this session, rule
this out immediately rather than spending time on it.

### 4. ListAgents: visibly running rows

List spawned agents. Anything short of a terminal "completed" status on a row is a live blocker on
its face; wait on it or stop it before retrying archive.

### 5. Orphaned nested background tasks spawned BY a subagent (the sneaky one)

The tell: a subagent's own completion notification contains language like "this agent stopped with
background work of its own still running; it may resume on its own when that work completes or
reports; the result above may be interim." That sentence means the subagent, while doing its work,
itself kicked off a background process (for example a nested background tool call) that is still
live in the harness's task registry, separate from the subagent's own entry.

This nested process does **not** get its own row in the agent list: only the top-level subagent
shows there, and it shows as "completed" because the subagent itself finished. The nested process
only surfaces when something queries the harness's task/output registry directly (for example the
archive attempt's own error, or a task-output call), where it is listed as a running background
entry under its own, different, task id.

- **Diagnose:** query task output for the suspect id, or read the exact archive error text; it
  names the orphaned task id explicitly.
- **Fix:** stop that task id explicitly. Retry archive only after it is confirmed stopped.

### 6. (reserved for the next blocker found)

Nothing further confirmed as of this skill's creation. See "Keeping this list alive" below; the
next entry goes here, not in a separate note.

## Keeping this list alive (mandatory)

Whenever this checklist does not explain an archive failure, and the real cause is found some other
way, add a new numbered entry above (in the same session, before finishing) with: the diagnostic
signature (the exact error text or symptom that pointed at it) and the exact fix. Bump
`metadata.version` (patch) when adding an entry. Do not let the discovery live only in a plan file,
a memory note, or the chat transcript; those are exactly what this checklist exists to replace with
one durable, growing home.

## Worked example (generalised)

A session tried to archive itself and was refused, the error citing a running background task.
`get_session('self')` showed a `parentSessionId`; tracing it found the parent already archived and
not running, ruling out angle 2. Listing agents showed only "completed" rows, ruling out angle 4.
Re-reading a completion notification received roughly an hour earlier from a spawned subagent
showed it had explicitly warned that background work of its own was still running. Querying task
output against that subagent's id surfaced an explicit error naming a **different** task id as a
running background entry in the harness's registry, the subagent's own nested background process.
Stopping that id resolved it; the archive retry then succeeded immediately.

## Red flags

- Concluding "must be a GUI thing" without having quoted the exact error text.
- Checking the agent list once and stopping, when a subagent's own completion notification
  explicitly warned about background work still running.
- Treating a populated `parentSessionId` / `detached: false` as automatically the cause, without
  tracing whether the parent session is still alive.
- Retrying archive in a loop without changing anything between attempts.
- Giving up and telling the user to archive from the GUI without appending a newly found cause to
  this checklist first.

## Bottom line

An archive refusal blaming "a running agent" or "a background task" is diagnosable, not just
clickable-from-GUI. Read the error literally, check this session's own parent/detach state, check
Remote Control, check the agent list, and especially check for an orphaned nested background
process a subagent spawned and left running after its own completion notification. Only ask for a
manual GUI close once the checklist is exhausted, and grow the checklist every time a new blocker
turns up.
