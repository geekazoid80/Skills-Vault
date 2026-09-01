---
name: pre-park-externalisation
description: "Use BEFORE any session park, restart, quit-and-reopen, sleep, or compact-then-quit moment. Triggers include \"park\", \"park this\", \"let's park\", \"park and restart\", \"save state\", \"I'll come back to this\", \"let me restart\", \"quit Claude Code\", \"kill this session\", \"stand down\", \"park for a restart\". Iron rule: ephemeral state (TaskList, background subprocess IDs, current cwd assumptions, in-memory caches, in-flight AskUserQuestion answers already received, pending decisions) does NOT survive a process boundary. Flush every category to the plan file BEFORE confirming the park. Then, if this session owns a worktree, remove it as the LAST tool call of the session, because nothing else does (ending a session does not remove a worktree and neither does archiving one) and because removing the tree you are standing in strands whatever the close still owed; only your own, never a peer's, and never with --force. Sibling discipline to the pre-compact externalisation pass; both run at process-boundary moments."
---

# pre-park-externalisation

> Skill marker: when this fires, emit `[skill: pre-park-externalisation]` on its own line.

## Overview

Every session has TWO process boundaries that lose ephemeral state: compact (chunk-level, handled by the pre-compact externalisation pass) and park / restart / quit (session-level, ALL ephemeral state lost). This skill enforces the park-level discipline: flush before parking.

**Core principle:** the plan file (`~/.claude/plans/*.md`) is the canonical resume artefact across a process boundary. Every category of ephemeral state that the next session will need to resume cleanly flows there.

## The iron rule

> Before any park, restart, quit, or process-boundary moment, externalise EVERY ephemeral piece of state the next session will need to resume. The cost of flushing is one plan-file section; the cost of skipping is re-derivation, mis-resumption, and lost context.

## What to flush, where to flush

| State category | Where in-session | Where to flush |
|---|---|---|
| Harness TaskList state (id + status + description) | Session-only; lost on restart | Plan file "Task snapshot at park" section. Group completed at the top (compact summary), in_progress + pending in detail with full descriptions. |
| Background subprocess IDs (`run_in_background` Bash tasks) | Session-only; killed on restart | Plan file "In-flight subprocesses" sub-section. ID, command, output-file path, last-known status, exact re-poll / re-run command for resume. |
| Resolved AskUserQuestion answers received this session | In-context only | Plan file "Decisions locked" section. Each Q + answer, so resume doesn't re-ask. |
| In-progress uncommitted edits | Filesystem (survives) but uncommitted | Plan file "Uncommitted work" note. Branch, file list, what was being changed, intended next action. Optional `git stash` with descriptive message. |
| External-CI state (PR runs the harness can't track) | GitHub-side (survives) but no completion notification | Plan file: branch + commit + check name + last-known status + exact `gh run list` command to re-poll on resume. |
| Current cwd assumption | Session-only | Plan file: use ABSOLUTE paths in any "next step" instruction; never rely on cwd surviving. |
| TCC / OS permission state | OS-level; may or may not survive | Plan file SESSION RESTART PICKUP: step that VERIFIES required permissions before resuming (`Read <path>` as test; on EPERM, surface to user). |
| Insights / lessons noticed mid-session that lack a durable artefact | In-context only | Per `reread-memory-before-planning` + `author-skill` + the north-star "codify at the point of pain" discipline: write to a global memory file, vault skill, or CLAUDE.md rule. The pre-park moment is the LAST chance. |

## The SESSION RESTART PICKUP skeleton (verbatim, top of plan file)

Every plan file at park-time MUST carry this section at the TOP, above the standing-reminder block:

```markdown
## SESSION RESTART PICKUP (read FIRST after restart)

**Step 0 (read FIRST, before anything else)**: re-read the project north star at `~/.claude/projects/<encoded-project-path>/memory/project_north_star.md` (if present), the orientation marker for the current project's end-state.

**Step 1 (verify permissions)**: confirm `~/Documents/` access restored (or whatever permission was blocked at park-time). Test with a Read on a known file. If EPERM, surface to user before continuing.

**Step 2 (re-poll in-flight external work)**: re-check status of any background CI / subprocess listed in the "In-flight subprocesses" section below. Use the exact re-poll command recorded there.

**Step 3 (re-create task list)**: TaskCreate the in_progress + pending entries from the "Task snapshot at park" section below (in id order). Completed tasks are git-log history; don't re-track.

**Step 4 (resume execution)**: per the current chunk's scope as recorded in the plan file. The decisions in the "Decisions locked" section are already-answered; do not re-ask.
```

## How to apply

1. **The moment the user says "park" / "restart" / "stand down" / "save state"**, OR you proactively recognise an imminent park (compact + quit, sleep, low context):
2. **Pause** any in-flight action; do NOT confirm park yet.
3. **Scan** every ephemeral state category in the table above. Note what's loaded that wouldn't survive a restart.
4. **Flush** each category to the chosen durable surface (plan file primarily; memory file / CLAUDE.md / vault skill for cross-session learnings).
5. **Write the SESSION RESTART PICKUP section** at the top of the plan file with the resume order (verify-permissions → re-poll-CI → re-create-tasks → resume-execution).
6. **Brief the user** with what was flushed, what was deferred, what the next session will see.
7. **If this session owns a worktree, remove it now, and make it the LAST tool call.** Nothing else will:
   ending a session does not remove a worktree, archiving one does not either, and a native exit helper
   only handles worktrees it created in the current session. Push first, pin any commit that exists only
   locally to a permanent ref (`git -C <canonical> update-ref refs/archive/<date>/<name> <sha>`), then
   `git -C <canonical> worktree remove .claude/worktrees/<name>` **without `--force`**, run from the
   canonical clone. Only your own, never a peer's. `using-git-worktrees` carries the full rule.
8. **THEN** confirm safe to park, in text, written from memory without reaching for another tool.

**Why step 7 sits after the brief rather than beside the flush.** The removal destroys the working directory
this session is standing in, so anything still owed afterwards is stranded mid-turn: the plan-file write, the
commit, the tracker update, the stamp. Every one of those has to be finished while the worktree still
exists. That is also why the confirmation in step 8 is the one part written from memory, and why a session
that finds itself needing "just one more command" after step 7 has ordered its close wrongly rather than
found an exception.

**The worktree is the one category here that is NOT flushed somewhere else.** Everything above moves state
INTO the plan file so it survives the boundary; this removes a thing that would otherwise survive it and
should not. It sits in this skill because it belongs to the park sequence and its correctness is entirely a
question of ORDER, which is what this skill owns.

## Worked example (a real park session)

**Wrong:** "Safe to quit. The plan file is the canonical resume artefact."
(But TaskList state isn't in the plan file. Next session has zero idea what tasks were in-flight. Background CI poll isn't recorded, next session doesn't know it was running.)

**Right:** Dump the 33-task TaskList as a "Task snapshot at park" section in the plan file with id + status + full description (in_progress + pending in detail; completed compactly summarised). Note the in-flight CI poll: branch `t-020/internal-alert-pipeline`, commit `cb48c0c`, exact `gh run list --branch ... --commit cb48c0c --json status,conclusion,name` to re-run on resume. Note the TCC block at park-time and the verify-on-resume step. Note the resolved AskUserQuestion answers (D + A + C parallel-work, MEM-PROMO-01 separate chunk, etc.) so resume doesn't re-ask. Update SESSION RESTART PICKUP with the resume order. THEN say "safe to quit."

## Skip carve-out (when this skill does NOT need to fire)

The pre-park pass is mandatory at FRESH parks. It does NOT need to fire again when:

- The user says "continue" / "go" / "resume", those are post-park / post-compact resume signals, not park signals.
- The session has no ephemeral state worth flushing (no in-flight tasks, no background subprocesses, no unresolved decisions, no uncommitted edits). Rare but possible.
- The user explicitly says "park without saving state" or equivalent (override).

When in doubt, flush. The cost is small and the failure mode (next session loses state) is exactly what this rule prevents.

## Red flags

- About to confirm a park / restart / quit without having flushed TaskList state to the plan file.
- About to confirm a park without recording an in-flight CI poll or background subprocess (next session won't know it was running).
- A pre-park summary that says "the plan file has it" without having ACTUALLY added the Task snapshot + In-flight subprocesses + Decisions locked sections.
- A SESSION RESTART PICKUP that doesn't enumerate verify-permissions / re-poll-CI / re-create-tasks in explicit order.
- A resolved user decision (from a recently-answered AskUserQuestion) that exists only in conversational context, not in the plan file.
- About to "save state" by writing prose ("we discussed X, Y, Z") instead of structured sections the next session can act on mechanically.
- Recognised mid-session that a lesson lacks a durable artefact, then parked WITHOUT first codifying (per the north-star "codify at the point of pain" discipline).
- Parking out of a worktree this session created and leaving it on disk, on the assumption that ending or archiving the session disposes of it. Neither does.
- Removing the worktree anywhere other than as the LAST tool call, which strands whatever the close still owed.
- Reaching for `worktree remove --force` to get past a dirty-guard refusal at park time, rather than reading what it named.
- Removing a worktree this session did not create, or widening the park into a sweep of other sessions' leftovers.

## Cross-references

- `park_and_standdown_discipline.md` (`~/.claude/memory/`), companion memory carrying this rule for the Class 1 re-read. (It previously named `feedback_pre_park_externalisation.md`, which was absorbed into that file and no longer exists; verified absent on disk rather than inferred.)
- `using-git-worktrees`, which owns worktree disposal, why nothing else does it, and the preserve-before-removing steps. This skill only fixes where the removal sits in the park order.
- `reread-memory-before-planning`, sibling discipline at plan-mode entry; both maintain durability across process boundaries.
- `feedback_plan_files_concise`, plan file shape; the pre-park dump is allowed to grow the plan file but goes in its OWN clearly-labelled section (not interleaved with in-flight chunk content), and is the FIRST thing trimmed on next-session resume after tasks are re-created.
- `task-vs-plan-tracking`, covers the opposite direction (plan → tasks at 4+ in-flight items). At park time, the discipline reverses: task → plan regardless of count, for the duration of the park.
- `~/.claude/CLAUDE.md § Pre-park externalisation pass`, always-on safety net for moments when this skill does not load.
- `~/.claude/CLAUDE.md § Pre-compact externalisation pass`, sibling rule for the OTHER process boundary (chunk-level compact vs session-level park).

## Bottom line

Every park moment is a process boundary that loses all ephemeral state. Flush before parking. The plan file is the canonical resume artefact; TaskList, subprocess IDs, resolved decisions, TCC status, and re-creation order all go there. The cost is one plan-file section; the cost of skipping is re-derivation.
