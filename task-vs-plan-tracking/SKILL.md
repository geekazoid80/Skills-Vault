---
name: task-vs-plan-tracking
description: Use when the in-flight queue in a plan file would cross 4 items, when the harness emits the "task tools haven't been used recently" reminder while a chunk has 4+ pending items, or when the user says "too many tasks", "switch to TaskCreate", "plan file is getting long", "should this be tasks", "track these as tasks", "the plan is getting unwieldy", "use the task tool", "I can't read this plan anymore". Routes the queue to harness TaskCreate / TaskList / TaskUpdate and trims the plan file to background + carry-forward principles + a one-line pointer to the task list. Also covers the reverse direction (collapsing a TaskList back into plan-file prose when in-flight items drain to ≤3 AND the chunk has more than one logical session ahead of it). Counts only pending + in_progress items; completed and deleted tasks don't count toward the threshold. Aligns with the always-on rule in ~/.claude/CLAUDE.md "Switch from plan.md prose to TaskCreate at four in-flight items"; this skill is the safety net for moments when only the trigger phrase fires (no plan-mode entry).
metadata:
  version: 1.0.0
---

# Task vs Plan Tracking

> **Skill marker**: When applying this skill, begin your reply with `[skill: task-vs-plan-tracking]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Two persistence surfaces compete for the same role of "what's in flight for this chunk":

1. **Plan file** (`~/.claude/plans/<slug>.md`), prose, user-readable, persists across sessions, surfaces background and carry-forward principles alongside the current chunk.
2. **Harness task list** (`TaskCreate` / `TaskList` / `TaskUpdate`), structured, machine-tracked, surfaces status (`pending` / `in_progress` / `completed`) with a built-in reminder hook when tasks go stale.

Each has a sweet spot. Under 4 items, plan-file prose reads fine. At 4+ items, the plan file becomes a scroll and the user has to read the whole list to see what is actually pending; the harness task list is purpose-built for this.

**Core principle:** small queues belong in plan-file prose; queues larger than 3 belong in harness tasks. The plan file always carries background + principles; what changes at the threshold is where the *queue itself* lives.

## The threshold

```
≤ 3 in-flight items   → plan-file prose (current-chunk section)
≥ 4 in-flight items   → harness TaskCreate; plan file holds only a one-line pointer
```

**"In-flight"** means anything currently `pending` or `in_progress` that the user is waiting on the assistant to resolve. Completed items don't count (plan files shouldn't carry done history per `feedback_plan_files_concise.md` anyway).

The trigger fires the moment the queue **would** cross the threshold, not retroactively at chunk-close. If about to write the 4th bullet in a plan file's current-chunk section, call `TaskCreate` instead.

## When the threshold fires, what to do

1. **Create the harness tasks.** One `TaskCreate` call per item. Each carries `subject` (imperative title) and `description` (what needs doing). Keep titles short; the description carries the detail.
2. **Trim the plan file.** Replace the existing task bullets with:
   ```
   Tasks tracked via harness: see TaskList. Plan file holds background + carry-forward principles only.
   ```
3. **Keep background + principles.** The chunk's background section, carry-forward principles, and verification approach stay in the plan file. Those are prose, not tasks.
4. **Update status discipline.** `TaskUpdate` to `in_progress` the moment work on a task starts; `completed` immediately on finish. No batching at chunk-end.
5. **Clean up at chunk-close.** Delete any `completed` tasks the harness still carries for that chunk (`TaskUpdate` status to `deleted`) so the next chunk's `TaskList` view is clean.

## When the threshold doesn't apply

- **Intra-turn fan-out.** Multi-step actions resolved inside the current assistant turn (lint sweep across 8 files, rename-and-update-imports, batch grep) don't need `TaskCreate` at any count. The threshold counts cross-turn in-flight items, not intra-turn steps.
- **Sub-agent batches.** Delegating 5 file analyses to Explore in parallel is tracked by the sub-agent return summaries, not as harness tasks. Add a harness task only when a sub-agent's output gates the next user-visible step.
- **One-shot operations.** A single discrete action (run the deploy, file the PR, post the comment) is the assistant's current turn; no task needed.

## The reverse direction (TaskList → plan file)

If a `TaskList` drains back to ≤3 in-flight items AND the chunk has more than one logical session ahead of it, it is fine to fold the remainder back into the plan file's current-chunk section.

Don't churn between the two for short-lived flux. Only collapse when the queue is stable at ≤3 across at least one session boundary. The cost of switching surfaces is real (re-writing bullets, re-establishing context); avoid doing it twice for the same chunk.

## Why this exists

Three concrete problems with letting a plan file's queue grow past 3:

1. **Scroll burden.** The user opens the plan file to see what's happening right now. At 4-5 bullets it's already too much to scan; at 8-10 it's hostile.
2. **No staleness signal.** The harness emits a system reminder ("the task tools haven't been used recently") when tasks idle. Plan-file bullets get no such poke; they silently rot.
3. **Lost state transitions.** `TaskUpdate` records a discrete `in_progress` → `completed` transition the user can audit. Plan-file bullets are checkbox-edited inline and history is lost when the section is rewritten.

Three concrete problems with using harness tasks at low count:

1. **Boilerplate cost.** Three TaskCreate calls for three items has worse signal-to-noise than three bullets in a plan section.
2. **No background context.** The harness tracks task items, not the chunk's background or carry-forward principles. The plan file is still needed; using harness tasks at low count just adds a second surface for no gain.
3. **User-visible churn.** Switching surfaces costs attention. At low count the saving doesn't justify the churn.

## Integration with related skills and rules

- **`plan-time-tooling`** owns the plan file's "Tooling to use this chunk" section. The Tooling section is prose and stays in the plan file regardless of where the task queue lives.
- **`reread-memory-before-planning`** owns the standing-reminder block at the top of every plan file. That block stays in the plan file regardless.
- **`feedback_plan_files_concise.md`** (global memory) says the plan file carries only doing + todo. This skill refines: at >3 items, the "todo" moves to harness tasks; the plan file then carries only background + principles + pointer.
- **CLAUDE.md "Switch from plan.md prose to TaskCreate at four in-flight items"** is the always-on safety net. This skill is the keyword-triggered version that catches sessions where the always-on rule was not internalised.

## Red flags

- Writing the 4th bullet in a plan-file current-chunk section, STOP, call `TaskCreate` instead.
- Plan file's current-chunk section is over 30 lines of bullets, overdue migration to harness tasks.
- Harness `TaskList` has 1-2 items and you find yourself opening the plan file to read background, fine, that's expected; the plan file owns background.
- Both surfaces carrying overlapping todos, single-source violation; pick one and clear the other in the same turn.
- "I'll TaskCreate this when the count hits 4", no; the trigger is the **would-cross** moment, not after-the-fact.
