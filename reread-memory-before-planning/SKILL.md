---
name: reread-memory-before-planning
description: "Use before drafting OR resuming ANY plan, before invoking AskUserQuestion to scope a chunk or sub-step, before writing or editing a plan file in `~/.claude/plans/`, at chunk-open, at PR-open within a chunk, and at every plan-mode entry (manual or harness-triggered). Triggers include \"let me plan\", \"draft a plan\", \"next chunk\", \"set up a plan\", \"PR-N plan\", \"open the next chunk\", \"I'll plan first\", \"planning the implementation\", \"exit plan mode\", \"enter plan mode\", \"ExitPlanMode\", \"EnterPlanMode\", \"approve the plan\", \"ready to plan\", \"scope the chunk\". NOT for inline replies, trivial actions (one-line fixes, doc typos, single-bash status checks), or continuation of an already-approved plan whose four-class re-read was already done in the current session. Iron rule: every plan I author is anchored in CURRENT global memory + CURRENT project memory + CURRENT project AGENTS.md + an explicit skills/MCPs enumeration, never in assumed-still-true context. Re-read all four classes first; plan second. Add a standing-reminder section to the plan file naming this rule."
---

# reread-memory-before-planning

> Skill marker: when this fires, emit `[skill: reread-memory-before-planning]` on its own line.

## Overview

I have a tendency to forget standing rules between sessions: UTC timestamps everywhere, per-deployment identity from vault never hardcoded, forward-compatible schemas, humanise-comms, consumer pointers when shipping services, ask-before-working-around-deps, token-expiry tracking, applicant-data completeness gate, bias-sensitive applicant fields, ID validation strategy, etc. Each of those lives in `~/.claude/projects/<encoded-project-path>/memory/`. Each was added because I previously got it wrong. Re-reading anchors the plan in current truth, not in faded session memory.

**Core principle:** the cost of re-reading memory is ~10 file reads in parallel; the cost of planning without re-reading is shipping a plan that violates a standing rule and burning a chunk to fix it. Always pay the cheaper cost.

## The iron rule

> Every plan I author re-reads memory first. Every plan file I write carries a standing-reminder section at the top so future-me (or a fresh session inheriting the plan) sees the expectation.

## The four-class procedure

When this skill fires, before any planning content goes into a plan file or an AskUserQuestion, re-read all four classes (in parallel where possible):

### Class 1. Global memory (cross-project rules)

Path: `~/.claude/memory/MEMORY.md` + every file it links to.

This is where cross-project `feedback_*.md` rules live (utc-timestamps, secrets-hygiene, multi-pat-direnv, worktree-workflow, plan-files-concise, verify-now-not-next-session, index-entries-audit-first, stacked-pr-delete-branch-trap, etc.). Always read the index first; then read every linked file in parallel. These rules apply regardless of project.

If `MEMORY.md` has changed since the last session (new entries, removed entries), the re-read picks up the delta naturally; do not skip on the assumption "I already know what's there."

### Class 2. Project memory (project-specific rules)

Path: `~/.claude/projects/<encoded-project-path>/memory/MEMORY.md` + every file it links to.

The encoded project path is the absolute project path with `/` replaced by `-` and leading `-` preserved. Example: project at `/Users/alice/code/foo-app` → memory dir at `~/.claude/projects/-Users-alice-code-foo-app/memory/`.

If the directory doesn't exist OR is empty (only `.` and `..`), this is a fresh project with no project-scoped overrides yet. Note that in the plan's Reminders block ("project memory: empty"); do NOT skip silently.

`MEMORY.md` files are indexes of point-in-time observations. Each link typically points at a `feedback_*.md` (cross-project behavioural rule) or `project_*.md` (project-specific design decision). Read MEMORY.md AND every linked file IN PARALLEL (one tool message, N Read calls); don't sequentially traverse, the latency adds up.

Each file carries a header: "This memory is N days old. Memories are point-in-time observations, not live state, claims about code behavior or file:line citations may be outdated. Verify against current code before asserting as fact."

**Staleness handling.** If a memory file makes a code claim (filename, line number, function signature) that the plan depends on, verify it against the current codebase BEFORE the plan commits to that claim. Memory is the source of truth for INTENT and DECISIONS; current code is the source of truth for SHAPE and LOCATION.

### Class 3. Project conventions (project + module AGENTS files)

Re-read the project's root `AGENTS.md` / `CLAUDE.md` (hard rules, conventions, tooling quirks) AND every module-scoped `AGENTS.md` for surfaces this plan touches. If the plan edits `modules/foo/`, read `modules/foo/AGENTS.md`. If it edits `integrations/asana/`, read that. If it edits `apps/api/`, read that.

The module layer catches "this module forbids X" or "this module's public-API contract is Y" rules that the project root doesn't restate.

If neither file exists at the project root (some projects encode discipline elsewhere, process docs, per-skill `SKILL.md` headers, registry files), record that explicitly in the Reminders block and note where the conventions actually live, so future plans don't waste a read cycle looking for a file that isn't there.

### Class 4. Necessary skills + MCPs (tooling enumeration)

Invoke the `plan-time-tooling` skill at the same plan-mode entry. Its job is to enumerate:

- Which vault skills fire on this chunk's trigger surface (e.g. `secrets-hygiene` if the chunk touches credentials; `worktree-workflow` if the chunk creates a worktree; `humanise-comms` always-on for any human-bound text).
- Which MCP servers are needed beyond the default set (e.g. `asana` MCP if the chunk integrates with Asana; `box` MCP if Box; usually "none beyond default" for vault-edit chunks).

Record the enumerated skills + MCPs in the Reminders block alongside the memory entries. The point: a plan that doesn't enumerate its tooling shifts that work into execution where it disrupts flow.

This class exists BECAUSE memory-only re-reads have repeatedly omitted the tooling pass; the user surfaced this gap on 2026-05-24 and asked for it to be made explicit in the procedure.

## Scope (this rule is GLOBAL)

The rule lives in TWO source-of-truth files, both under `~/.claude/`:

- This file, `~/.claude/skills/reread-memory-before-planning/SKILL.md`
- The companion memory, `~/.claude/memory/feedback_reread_memory_before_plan.md`

Both are cross-project. The template carries verbatim into every plan in every project. Skills-Vault, other repos, and brand-new projects all use the same template. There is no project-specific variant; if a project needs to add a project-scoped wrinkle, it goes into the project's `AGENTS.md` / `CLAUDE.md` (Class 3) or into a project-memory file (Class 2), NOT into this template.

If the two source-of-truth files drift apart (one has the new four-class form, the other still has the old three-step form), the next plan will inherit whichever the skill loads from, usually the SKILL.md. Keep them byte-for-byte aligned on the template block.

## The plan-file standing-reminder template

Every plan file I write MUST carry this section AT THE TOP, before the existing `## Status` / `## Context` headers:

```markdown
> ## Standing reminder (cross-session, applies to every plan I author)
>
> **Project north star first.** Restate the project's north star in one line (from the repo `AGENTS.md`/`CLAUDE.md` § North star, mirrored in `~/.claude/projects/<encoded>/memory/project_north_star.md`) and judge every chunk in this plan against it: *how does this advance the north star?* If the project has none stated, surface that as a planning question before scoping.
>
> **Before drafting OR resuming a plan, re-read all four classes:**
>
> 1. **Global memory** at `~/.claude/memory/MEMORY.md` and every file it links to (cross-project rules: utc-timestamps, secrets-hygiene, multi-pat-direnv, worktree-workflow, plan-files-concise, etc.).
> 2. **Project memory** at `~/.claude/projects/<encoded-project-path>/memory/MEMORY.md` and every file it links to (project-specific rules; encoded path = absolute project path with `/` replaced by `-` and leading `-` preserved).
> 3. **Project conventions**, root `AGENTS.md` / `CLAUDE.md` plus module-scoped `AGENTS.md` for every surface the plan touches.
> 4. **Necessary skills + MCPs** for the chunk (invoke the `plan-time-tooling` skill; enumerate vault skills that fire on this chunk's trigger surface and MCP servers needed beyond the default set).
>
> **Why:** I have a tendency to forget standing rules between sessions. Re-reading anchors the plan in current truth, not assumed-still-true memory. The skills + MCPs step is part of the same discipline, a plan that doesn't enumerate its tooling shifts that work into execution where it disrupts flow.
>
> **Also:** every plan file I author MUST contain a section like this one at the top, so future-me (or a fresh session) inheriting the plan sees the expectation immediately.
>
> **Scope:** this reminder is GLOBAL, lives in `~/.claude/skills/reread-memory-before-planning/SKILL.md` + `~/.claude/memory/feedback_reread_memory_before_plan.md`, and applies to every plan in every project. Not project-specific.
>
> Carry this reminder forward to every plan in every session.
```

Copy this block verbatim into every new plan file. Don't paraphrase: the template carries forward intact to future sessions where I might not have this skill loaded.

## The project MEMORY.md standing-header template

Every project memory index at `~/.claude/projects/<encoded-project-path>/memory/MEMORY.md` MUST open with a standing-header line that points the next session to global memory first. Sibling discipline to the plan-file standing-reminder template above, both ensure cross-session durability of the four-class re-read, one inbound (plan-mode entry) and one outbound (project-memory consumption).

```markdown
# Project memory index, <Project Name>

> **ALWAYS check `~/.claude/memory/MEMORY.md` (global memory) FIRST** before reading or extending this file. Universal rules (<list the categories relevant to this project: secrets, timestamps, multi-PAT direnv, comms style, schema compatibility, token expiry, per-deployment identity, long-running cadence, etc.>) live there. This file holds ONLY rules specific to this project.

- [Project north star or first project-specific rule](...)
- ...
```

**Why:**

- Single source of truth (Class 1 global rules belong in global memory; project memory should never duplicate them).
- Discoverability (a new session opening a project's `MEMORY.md` immediately sees the breadcrumb to global memory, so the four-class re-read works correctly even when the session jumps straight to project memory).
- Anti-duplication (without the header, a project memory entry that re-codifies a universal rule looks authoritative; the header makes clear that universal rules live elsewhere and this file is project-specific only).

**When to apply:**

- **Creating a new project memory directory:** the very FIRST line of the new `MEMORY.md` is the project-name header; the second line is the standing-header blockquote. No exceptions.
- **Auditing an existing project's `MEMORY.md`:** check the top of the file. If the standing-header blockquote is absent (or paraphrased), add it. The blockquote text is intentionally specific so memory searches can find it via the literal string "ALWAYS check `~/.claude/memory/MEMORY.md`".
- **Quick audit script** to find project MEMORY.md files lacking the header:
  ```bash
  for f in ~/.claude/projects/*/memory/MEMORY.md; do
    if ! head -3 "$f" 2>/dev/null | grep -q "ALWAYS check"; then
      echo "MISSING: $f"
    fi
  done
  ```

**What the header replaces:** any project-memory entry that says "applies to every project" or "universal across every project", promote those to global memory (per the 2026-05-24 universal-tagged-memory promotion sweep), then leave only the standing header pointing to where the universal rule now lives.

**Scope.** This rule is GLOBAL, lives in this skill's SKILL.md AND in the companion memory pointer at `~/.claude/memory/MEMORY.md` (see the "Project MEMORY.md standing header" index entry). Applies to every project in every session.

## Skip carve-out (when this skill does NOT need to re-read)

The re-read is mandatory at FRESH planning. It does NOT need to fire again for:

- A continuation of an already-approved plan whose memory-reread already happened in the current session.
- Trivial actions that don't constitute planning: one-line fixes, doc typos, single-bash status checks, "merge the PR", "delete that file", "rename this variable".
- Pure information-retrieval ("what does X do?", "where is Y?") that doesn't produce a plan.

When in doubt, re-read. The cost is small and the failure mode (planning on stale assumptions) is the entire reason this rule exists.

## Worked example

User says: "let's open the next chunk." I'm about to enter plan mode for a chunk I haven't planned yet.

WRONG, go straight to `AskUserQuestion` to scope:
```
AskUserQuestion({
  question: "Which chunk should we open next?",
  options: [...]
})
```

This skips all four classes. I might forget that the project has a "per-deployment identity from vault" rule and propose a chunk plan that hardcodes a token, requiring re-work; OR I might forget that `secrets-hygiene` should fire on the chunk and end up writing a credential prompt that violates the "Probing the credential store" pattern.

ALSO WRONG, re-read project memory only, skip global + skills/MCPs:
```
Read(~/.claude/projects/<encoded>/memory/MEMORY.md)
Read(<project>/AGENTS.md)
# Then straight to AskUserQuestion ...
```

This is the gap that the 2026-05-24 user-caught error was symptomatic of. It feels rigorous because SOME memory was read, but it misses the cross-project layer where most of the load-bearing rules actually live, and it skips the tooling enumeration entirely.

RIGHT, re-read all four classes in parallel, invoke `plan-time-tooling`, THEN scope:
```
# Class 1: global memory in parallel
Read(~/.claude/memory/MEMORY.md)
Read(~/.claude/memory/feedback_secrets_hygiene.md)
Read(~/.claude/memory/feedback_multi_pat_direnv.md)
Read(~/.claude/memory/worktree-workflow.md)
... (every file MEMORY.md links to)

# Class 2: project memory in parallel (skip-if-empty)
Read(~/.claude/projects/<encoded>/memory/MEMORY.md)
Read(~/.claude/projects/<encoded>/memory/feedback_utc_timestamps.md)
... (every file project MEMORY.md links to)

# Class 3: project + module AGENTS / CLAUDE
Read(<project>/AGENTS.md)            # may not exist; that's fine, note it
Read(<project>/modules/foo/AGENTS.md) # only if plan touches modules/foo/

# Class 4: tooling enumeration
Skill(plan-time-tooling)   # surfaces firing skills + needed MCPs

# Then surface scope (with all four classes informing the options)
AskUserQuestion({
  question: "Which chunk should we open next?",
  options: [...]
})

# When the user picks and approves, the plan file gets the
# standing-reminder block at the top AND a Reminders section
# below it that lists what was actually re-read in each class.
```

## Red flags

- About to call `AskUserQuestion` to scope a chunk WITHOUT having re-read all four classes in this session.
- About to write a plan whose Reminders block lists only project memory and skips global memory / project conventions / skills + MCPs (the 2026-05-24 gap; the four-class re-read MUST be explicit in the Reminders section, not implicit "I read some stuff").
- About to call `Write` on a `~/.claude/plans/*.md` file WITHOUT the standing-reminder block at the top.
- About to call `ExitPlanMode` for a plan file that lacks either the standing-reminder block OR a Reminders section that enumerates all four classes.
- Drafting plan content based on "I remember the project rule is X" without verifying memory says so today.
- Memory file claims a code shape (filename, line number, signature) the plan depends on; planning without verifying it's still true.
- A fresh session inherits a plan file that has no standing-reminder block → the skill's enforcement broke at the previous plan-author point; reflag and add it.
- Plan-mode entry that does NOT invoke `plan-time-tooling` (Class 4), the tooling enumeration must be part of the plan, not deferred to execution.
- The two source-of-truth files (`SKILL.md` here + `feedback_reread_memory_before_plan.md`) have drifted out of sync on the template block, re-align before the next plan.
- A project's `MEMORY.md` lacks the standing-header line at the top (or has prose that doesn't match the template), add or re-align before the next plan that touches that project.
- Creating a new project memory directory without the standing-header, the very first `MEMORY.md` line is the project-name header; the second is the standing-header blockquote. Both before any rule entries.

## Bottom line

Re-read memory before drafting any plan; add the standing-reminder block to every plan file. Cost is small (one parallel read batch); failure mode of skipping it is shipping a plan that violates a standing rule. Always pay the cheaper cost.
