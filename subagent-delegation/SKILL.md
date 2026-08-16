---
name: subagent-delegation
description: "Use when about to delegate non-trivial work to a sub-agent (Explore, general-purpose, or any specialist) OR write any hand-off that briefs another session/agent (spawn_task chip, throwaway-session prompt, TaskCreate brief, scheduled/cron agent, PR body handing off work). Covers Pattern A \"thin master, heavy sub-agents\": when to stay inline vs. delegate, the standing-instructions + memory precondition every hand-off brief must open with (the receiving session reads CLAUDE.md + global memory + project memory + repo AGENTS.md from disk for itself; the prose is never the control; multi-PAT keychain token / pull --ff-only / secrets hygiene are the canonical misses), the canonical-path-pinning preamble for every brief that does file I/O, the adjacent-pattern scan instruction for cross-cutting briefs, the master-side blast-radius grep before pushing a contract change, the AskUserQuestion gate when adjacent findings come back (bundle / follow-up PR / accept the gap), the AskUserQuestion gate for generalisable patterns (extract now / follow-up PR / defer with TODO / accept duplication), and the leaf rule (sub-agents do not spawn sub-sub-agents). Also covers the plan-execution loop for subagent-driven development (fresh subagent per task, two-stage review, implementer status model, model selection per task complexity, and the BOUNDED FIX LOOP: five rounds per task, resume the original implementer for rounds 1-3 then a fresh one a model tier up for 4-5, scoped re-review verdicting each finding ADDRESSED or NOT ADDRESSED, and the breaker that adjudicates open findings on the record at the cap instead of looping forever); folded from obra/superpowers/skills/subagent-driven-development. Fires on \"the review keeps finding things\", \"how many times do I re-dispatch\", \"this task is stuck in review\", \"fix loop\", \"re-review\", \"the implementer cannot fix it\", \"when do I stop retrying a subagent\". Parallel-Dispatch (independent problems) pattern for fanning out 2+ unrelated investigations or fixes concurrently; folded from obra/superpowers/skills/dispatching-parallel-agents. Parallel-Design Sub-Agents pattern (\"Design It Twice\") for exploring alternative interfaces. Specialist review dispatches catalogue (GHA security review with five-element finding contract; folded from getsentry/skills/gha-security-review)."
metadata:
  version: 1.6.0
---

# Sub-agent Delegation

> **Skill marker**: When applying this skill, begin your reply with `[skill: subagent-delegation]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

The default working pattern when a chunk is non-trivial: **thin master, heavy reads and writes via sub-agents**. Master keeps the plan, the decisions, and a thin index of state. Sub-agents do the bulk file I/O and return short summaries.

**Core principle:** master's context is the scarcest resource on the run. Spend it on decisions, not on file contents.

**The trap to avoid:** master "just peeking" at files between sub-agent calls. That is how context bloats. If you want to peek, instead enrich the next sub-agent's brief with the question and let it answer in its summary.

## When to Delegate

| Need | Sub-agent | What it returns |
|---|---|---|
| Heavy reads / surface mapping | `Explore` | Ranked file:line bullets, one short sentence each. No raw excerpts. |
| Writes (one slice per agent) | `general-purpose` | Diff size + test result + 120-word summary. Brief is self-contained: file paths, line numbers, acceptance criteria, verification commands. |
| Verification of an unknown failure | Its own sub-agent | Root-cause diagnosis, not a transcript. |

Master only loads a file when about to make a decision the sub-agent should not make alone (architectural choice, scope-shift, contract change). Even then, target sections via `Read` with `offset`/`limit`, never the whole file.

## When to Stay Inline (no sub-agent)

- Edits under ~3 lines with no surrounding research.
- Bookkeeping commits (status flips, archive appends, roadmap updates).
- Single Bash calls (commit, push, `gh pr view`).

## When to Escalate to "master peeks"

- A sub-agent returns "I had to make a judgement call between X and Y, picked X". Pull the relevant 20 lines yourself, decide, then re-spawn or proceed inline.
- A sub-agent's contract change touches the public surface (dropped a schema, renamed an export). Verify with a quick grep for orphan references before pushing.

## Sub-agents Are Leaves

Sub-agents CAN spawn sub-sub-agents (most agent types have the Agent tool). Do NOT let them.

Why: sub-sub output is invisible to master, parallelism dies, context still spends in the sub-agent's window. If a write-slice needs research, master either bundles the research into the original brief or runs an `Explore` turn first. Sub-agents only spawn sub-subs for genuinely independent fan-out (e.g. "for each of 5 files, return a 1-line summary").

## Canonical-path-pinning Preamble (verbatim template)

Sub-agents start with no memory of the conversation and may inherit a different `cwd` than expected. Particularly hazardous when the project uses git worktrees: the harness can default `cwd` to a stale `.claude/worktrees/<x>/` directory while the canonical repo lives at the parent path. The sub-agent then reports "the repo is at Day-0 scaffold" and refuses (rightly) to fabricate prerequisite work.

Always include this block at the top of every sub-agent brief that does file I/O:

```
## CRITICAL: read this first

The canonical repo is at `<absolute path>` (mind any spaces in the path).
The shell may default cwd to a stale worktree at `<worktree path>`;
that worktree is irrelevant. Ignore it.

For EVERY Bash call: prefix with `cd "<canonical path>" && ...`.
For EVERY Read/Write/Edit: use absolute paths starting with the
canonical path.

Confirm once before doing anything else:
    cd "<canonical path>" && pwd && git branch --show-current && git log --oneline -1

Expected output:
- pwd: <canonical path>
- branch: <expected branch>
- last commit: <expected SHA + subject>

If you don't see that exact state, STOP and report. Do not proceed.
```

This adds maybe 10 lines to the brief and saves an entire wasted sub-agent turn when the worktree hazard is live. If the project does not use worktrees, the block still helps any sub-agent that gets confused by `pwd` drift.

## Standing-instructions + Memory Precondition (verbatim template)

Every hand-off MUST open with a precondition that the receiving session **reads its standing instructions and memory FROM DISK, for itself, before acting**. This is not optional and not only for sub-agents: it applies to every hand-off vector - a sub-agent brief, a `spawn_task` chip, a throwaway-session prompt (cross-repo deviation rule), a `TaskCreate` brief a sub-agent will execute, a scheduled / cron cloud agent, and a PR body that hands follow-up work to a future session.

The brief's prose is NEVER the control. Cross-cutting rules (the multi-PAT keychain token, `pull --ff-only`, secrets hygiene) live in `CLAUDE.md` and memory, not in whatever the brief happened to restate. A receiving session that only reads the brief silently drops every rule the brief omitted.

Put this block at the very TOP of every hand-off brief, ABOVE the canonical-path-pinning preamble:

```
## Before you act: read your standing instructions + memory (from disk)

Read, for yourself, before doing anything else:
- ~/.claude/CLAUDE.md (always-on rules)
- ~/.claude/memory/MEMORY.md and its linked files
- the project memory index: ~/.claude/projects/<encoded-project-path>/memory/MEMORY.md
  and its linked files
- the repo's AGENTS.md / CLAUDE.md

Honour them even where this brief does NOT restate them. In particular:
- multi-PAT: use the correct per-org Keychain GH_TOKEN before ANY gh / HTTPS git push,
  e.g. GH_TOKEN="$(security find-generic-password -s gh_<org>_pat -w)".
- pull-before-dev: git fetch && git pull --ff-only before the first edit.
- secrets hygiene: never read or echo a secret file (config.toml / config.ini / .env / config.py).
```

Why: a hand-off that omits this produces a session that misses whatever rule the prose did not restate. The recurring, concrete pain is the multi-PAT keychain rule - handed-off sessions ran bare `gh` and failed on the wrong account because the brief never told them to read memory. The receiving session's own fresh-disk read is the control. Full rule: `~/.claude/CLAUDE.md` "Every hand-off carries the read-memory + standing-instructions first precondition" + `~/.claude/memory/feedback_handoff_read_memory_precondition.md`.

## Adjacent-pattern Scan Instruction (cross-cutting briefs)

When the brief is fixing a cross-cutting pattern, an interface contract, or a behaviour that could plausibly exist in more than one place, end the brief with:

> After implementing, grep the codebase for the same pattern you just used. Report any divergent occurrences in your return summary, file:line plus a one-sentence note per occurrence. Do not fix them in this PR; just flag them.

The sub-agent's grep happens in its own context budget, not master's. Master gets back a thin list to act on.

## Blast-radius Grep on Contract Changes (master-side, before push)

When a sub-agent reports it changed a public surface, master runs a quick `grep -rn` for that surface across `apps/`, `modules/`, `integrations/`, `packages/`, and surfaces what would need to follow. Three lines of bash, master's own context, before any push.

Public-surface examples that trigger the grep:

- Engine method signature
- Port shape
- Exported schema
- Controller pattern
- Env-var name
- Decorator placement

## Adjacent Findings → AskUserQuestion BEFORE Pushing

Sub-agent flags an adjacent issue (its own scan, or surfaced by master's blast-radius grep). Master's options are:

1. **Bundle the fix into the current PR.** Scope creep, but keeps the narrative clean.
2. **Spawn a follow-up PR after this one merges.** Cleaner diffs, more PRs.
3. **Accept the gap.** Rare; usually only when the adjacent issue is genuinely out of scope.

This is a real choice. Do NOT default-and-act. Use AskUserQuestion to surface the three options. Do NOT bury it in a PR-body footnote like "this same bug exists in X, will be addressed as a follow-up". That is deferring instead of asking.

## Generalisable Code → AskUserQuestion BEFORE Pushing

When sub-agent output (or master's own observation while reviewing a diff) reveals a pattern that could become a shared library / helper / utility, **always surface it via AskUserQuestion before pushing the current PR**. Do not silently accept duplication; do not silently extract.

### Trigger conditions

- A sub-agent's brief had it copy-paste a helper from another module (e.g. `mapError` already exists in entity-group; ATS now needs the same).
- Master's blast-radius grep shows the same pattern in 3+ places with stable contract surface.
- A new module re-implements something that already lives in `packages/*` or `modules/*`.
- A test scaffold (e.g. ephemeral SQLite + registry-reset) gets duplicated at the file level.

### Options to surface (always 4, never 3 or 2)

| Option | When best | Trade-off |
|---|---|---|
| 1. Extract NOW into `packages/<lib>/` | Pattern's contract is stable AND ≥3 call sites exist | Adds scope to the current PR, but consumers all update together |
| 2. Spawn a follow-up "extract" PR after this one merges | Medium-stable patterns | Keeps current PR focused; extract becomes its own reviewable diff with all consumers updated |
| 3. Defer with an explicit TODO | Early-stage patterns where the right abstraction is not obvious yet | Code comment + roadmap row reference; revisit when stable |
| 4. Accept the duplication | 1-2 sites, small contract, project still in flux | Document the call so the next reviewer knows it was deliberate |

### Why this matters

Without the rule, every chunk silently leaves either (a) duplication that someone has to clean up later, or (b) premature abstraction that ossifies the wrong contract. Either is a debt class. Surfacing the choice means the abstraction lands when the user wants it, on the timeline they want.

## Plan-execution loop (subagent-driven implementation)

Folded from obra/superpowers/skills/subagent-driven-development. Use this pattern when an implementation plan with mostly-independent tasks is being executed in the current session, with the master coordinating fresh subagents per task. Distinct from the Pattern-A delegation above (which is the default working pattern for any non-trivial chunk); this section is the *workflow* when the chunk is structured as "execute the N tasks in this plan".

### When this fires

- A plan file or roadmap row with N discrete tasks has been approved.
- Tasks are mostly independent (touching disjoint files / modules).
- Execution stays in the current session (no parallel session handoff).

If tasks are tightly coupled, run them inline with the standard Pattern-A delegation, not the per-task loop below.

### Continuous execution

Do NOT pause to check in between tasks. Execute all tasks from the plan without stopping. The only reasons to stop are:

- A task returns BLOCKED status that master cannot resolve.
- Ambiguity that genuinely prevents progress.
- All tasks complete.

"Should I continue?" prompts and progress summaries between tasks waste time. The user briefed the plan; execute it. The cadence rule "default to plan mode between chunks" applies between *chunks*, not between *tasks within a chunk*.

### Per-task workflow

For each task in the plan, run this loop:

1. **Dispatch implementer subagent** with the task's full text and surrounding context. Brief includes the standing-instructions + memory precondition (per the section above), the canonical-path-pinning preamble, the file paths, the acceptance criteria, the verification commands, and the adjacent-pattern scan instruction if cross-cutting.
2. **Implementer asks clarifying questions?** Answer clearly, re-dispatch.
3. **Implementer implements, tests, self-reviews, commits.** Returns one of four statuses (see "Implementer status model" below).
4. **Spec-compliance review:** dispatch a spec reviewer subagent. Brief: "does the implementation match the task spec? Flag any over-build (extra features) or under-build (missing requirements)." If issues: enter the fix loop below.
5. **Code-quality review:** dispatch a quality reviewer subagent (or use `engineering:code-review` per `completion-gate` Layer 2). Brief: "find Critical, Important, Minor issues; ignore spec compliance (already covered)". If issues: enter the fix loop below.
6. **Mark task complete** in TodoWrite. Move to next task.

Never move to the next task while a review has open Critical or Important findings that are neither fixed nor parked with a written ruling at the cap.

After all tasks complete, dispatch one final code-review subagent across the full diff, then run the `completion-gate` Layer 3 iron law before claiming the plan is done.

### Implementer status model

Implementer subagents report one of four statuses. Master handles each appropriately:

| Status | Meaning | Master's action |
|---|---|---|
| **DONE** | Task complete and self-reviewed | Proceed to spec-compliance review |
| **DONE_WITH_CONCERNS** | Complete, but flagged doubts | Read concerns; if correctness or scope, address before review; if observations only, note and proceed |
| **NEEDS_CONTEXT** | Information was missing from brief | Provide missing context, re-dispatch |
| **BLOCKED** | Cannot complete the task | Diagnose: context problem (re-dispatch with more context), reasoning ceiling (re-dispatch with more capable model), too large (decompose), or plan wrong (escalate to user via AskUserQuestion) |

Never ignore a BLOCKED escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.

### Model selection per task

Use the least powerful model that can handle each task to conserve cost and increase speed. Signals:

| Task signal | Model class |
|---|---|
| Touches 1-2 files with a complete spec | Cheap / fast model (Haiku-tier) |
| Touches multiple files with integration concerns | Standard model (Sonnet-tier) |
| Requires design judgement or broad codebase understanding | Most capable model (Opus-tier) |
| Architecture, design, or review tasks | Most capable model |

Master coordinates the dispatch with appropriate `model:` parameter on the `Agent` tool call.

**Always name the model explicitly.** An omitted `model:` silently inherits the session's model, which is usually the most capable and most expensive one. One upstream run put all 26 of its reviewers on the top tier purely because the controller never named a model.

**Turn count beats token price.** The cheapest tier is not automatically cheapest overall: wall-clock and context cost scale with turns, and the cheapest models routinely take two to three times the turns on multi-step work. Use a mid-tier model as the floor for reviewers, and for implementers working from a prose description. Reserve the cheapest tier for implementers whose task text already contains the complete code to write (transcription plus testing) and for single-file mechanical fixes. Scale a review task's model to the diff's size, complexity, and risk.

### Two-stage review, in order

Spec-compliance review FIRST, then code-quality review. Order matters:

- Spec compliance gates against scope drift (over-build / under-build). A quality-clean diff that doesn't match the spec is wasted work.
- Code quality gates against semantic bugs, missing error paths, the things existing tests don't cover. Cleaning up code that is going to be ripped out for spec drift is also wasted work.

Both gates are required. Spec compliance does NOT replace code quality, and self-review does NOT replace either.

**This is a deliberate divergence from upstream, reaffirmed 2026-07-22.** obra/superpowers v6.0.0 (2026-06-16) replaced its two reviewer prompts with a single task reviewer returning both verdicts, on the grounds that two dispatches per task cost roughly double and were easy to game. The vault keeps the two-stage shape because the ordering guarantee is the point: scope drift gets caught before anyone spends effort on quality. Do not re-fold the single-reviewer model on a later audit pass without a fresh decision.

### The fix loop is bounded (five rounds, then adjudicate)

A review that returns findings starts a fix loop. **A loop with no cap is the failure mode**: without one, a task the implementer cannot see its way out of spins indefinitely, each round costing a dispatch and a re-review, and nothing in the process ever says stop.

One round is one fix dispatch plus one scoped re-review. **Five rounds maximum per task.**

Two routes leave before the loop starts:

- **Minor findings never enter the loop.** Record each in the ledger as you go (`Task <N>: minor (deferred): <one-liner>`) and point the final whole-branch review at that list so it can triage what must be fixed before merge. A roll-up nobody reads is a silent discard.
- **A finding that conflicts with what the plan requires is the user's decision**, like any plan contradiction. Present the finding and the plan text and ask which governs. Do not dismiss the finding because the plan mandated it, and do not dispatch a fix that contradicts the plan without asking.

**Rounds 1 to 3, resume the ORIGINAL implementer** with the open findings verbatim. Its context is intact: it knows the task, the code, and its own choices, so it does not pay to rebuild any of that. In this harness that is `SendMessage` to the agent id returned by the original `Agent` call, which means the resume half of this pattern is natively supported and needs no workaround. Record the agent id at dispatch time or you cannot resume it. If the id is gone, dispatch a fresh implementer carrying the brief path, the report-file path, and the findings; the report file is the persistent memory either way.

**Rounds 4 to 5, dispatch a FRESH implementer one model tier up** (per Model selection above), with the brief path, the report-file path, the open findings, and this framing: "a prior implementer attempted this task N times; you own it now, read the report file for what was tried." A loop that survives three resumes usually means the implementer cannot see its own problem, so this buys fresh eyes and a capability bump in one move.

**Every round, either way:** the implementer fixes, re-runs the tests covering the amended code, appends its fix report to the same report file, and returns the short contract. Confirm the fix report names the covering tests, the command run, and the output before re-dispatching the reviewer. Name the covering test files in the fix message; a one-line fix does not need the whole suite.

**The re-review is scoped, and that is what makes the loop terminate.** Give the re-reviewer the findings list, the brief, the report file, and the diff of the fix range only (base = the head the previous review saw). It verdicts each finding **ADDRESSED** or **NOT ADDRESSED** with `file:line`; "attempted" is not addressed. It flags new breakage **inside the fix diff only**. New Critical or Important breakage in that diff joins the open findings. Anything it notices outside the fix diff goes to the ledger as a deferred minor and never extends the loop. An unscoped re-review can wander into untouched code and manufacture a sixth round forever.

**Never fix findings yourself in the controller session.** Controller fixes pollute the context you need for coordination, and they skip review entirely.

**The breaker.** When round 5's re-review still leaves findings open, stop dispatching and adjudicate each one yourself, because you hold the plan and the cross-task context the reviewer lacks:

| Open finding at the cap | Ruling |
|---|---|
| Reviewer is wrong, or the point is contestable | Park it: `Task <N>: parked, <finding>, ruling: <why the code stands>`. The final review sees both sides. |
| Real, but nothing downstream builds on it | Park it the same way, with a ruling saying it is real and deferred. |
| Real and load-bearing (a later task builds on it, or it exposes a plan defect) | **STOP.** Append `Task <N>: BLOCKED, <reason>` and escalate via AskUserQuestion with the finding, the plan text it collides with, and the fix history. |

Parking a structural failure lets every dependent task build on it and hands the final review a problem it cannot fix either.

**Adjudicate only at the cap.** Adjudicating earlier to end a loop is pre-judging with a different name. Every adjudication is a ledger entry; a silent discard is forbidden.

### Hand artifacts over as files, never as pasted text

The single biggest avoidable cost in the loop. Everything pasted into a dispatch prompt, and everything a subagent prints back, stays resident in master's context for the rest of the session and is re-read on every later turn. A pasted diff parks itself permanently in the most expensive context you own.

- Write the task's requirements to a brief file and pass the **path**.
- Name the implementer's report file in the dispatch, and have the implementer return only status, commits, a one-line test summary, and concerns.
- Give the reviewer three paths (brief, report, diff package) rather than pasted text.

A dispatch prompt describes ONE task, not the session's history. One upstream session's dispatch reached 42k characters of which 99% was pasted prior-task summaries. A fresh subagent needs its task, the interfaces it touches, and the global constraints. Nothing else.

Related: if a final review returns findings, dispatch ONE fix subagent with the complete findings list, not one fixer per finding. Per-finding fixers each rebuild context and re-run the suite; one upstream session's final-review fix wave cost more than all of its tasks combined.

Then run **exactly one** scoped re-review over the fix range, and adjudicate any residual findings with the breaker rules from the fix-loop section: park with a written ruling, or stop on the load-bearing ones. **There is no second fix wave.** Residual load-bearing findings surface to the user when `completion-gate` Layer 4 presents the finish options. Point the final reviewer at the ledger's deferred-minor and parked lines so it can triage which of those must be fixed before merge.

### Keep a durable progress ledger

Conversation memory does not survive compaction. Controllers that lost their place have re-dispatched entire completed task sequences, which upstream names the most expensive failure it observed.

Track progress in something durable, not only in the in-session task list. In this vault that is the plan file or the harness `TaskList` (see `task-vs-plan-tracking`), not a scratch file.

- Check the ledger at loop start; resume at the first task not marked complete.
- Append one line per clean review, naming the commit range.
- **Append a line per fix round**, not just per task: `Task <N>: fix round <R>/5 (<X> addressed, <Y> open: <finding one-liners>; commits <a7>..<b7>)`. Without it, a resume after compaction cannot tell "task complete" from "task mid-loop at round 4", and the round counter that bounds the loop is exactly the state that does not survive the cut.
- Record every deferred minor, every parked ruling, and any BLOCKED adjudication as its own line. These are what the final review triages against.
- After a compaction, trust the ledger and `git log` over your own recollection. The commits exist in git even when your context no longer remembers creating them.

### The "cannot verify from the diff" verdict

Either reviewer, spec-compliance or code-quality, can report items it could not verify, because the requirement lives in code the diff does not touch, or spans several tasks. These do not block the rest of that stage's review, but master MUST resolve each one before marking the task complete, since master holds the plan and the cross-task context neither reviewer has. If master confirms the item is a real gap, treat it as a failed spec review: back to the implementer, then re-run the affected stage.

### Cross-references for the plan-execution loop

- `completion-gate` Layer 2 covers the BASE_SHA / HEAD_SHA dispatch pattern for the code-quality review subagent (folded from obra/superpowers/skills/requesting-code-review).
- `completion-gate` Layer 3 (the iron law) is the master-side verification before claiming the plan is complete.
- `tdd` is the discipline each implementer subagent uses inside its task (red-green-refactor with verification).
- `plan-time-tooling` is the upstream that decides which tools / MCPs / mandatory triggers fire for the plan being executed.

## Parallel-Dispatch (independent problems)

Folded from obra/superpowers/skills/dispatching-parallel-agents. Use this pattern when 2+ tasks are genuinely independent (no shared state, no sequential dependencies) and would benefit from concurrent investigation or execution.

Distinct from the two other parallel patterns in this skill:

- **Plan-execution loop** (above): N tasks from a plan, dispatched ONE-AT-A-TIME with two-stage review per task. Sequential by design.
- **Parallel-Dispatch** (this section): N independent problems, dispatched ALL-AT-ONCE for concurrent work. No shared state.
- **Parallel-Design Sub-Agents** (below): SAME problem, N differentiated constraints, dispatched ALL-AT-ONCE to compare alternatives. Same problem, different angles.

### When this fires

- 3+ test files failing with different root causes (each fix touches different code).
- Multiple subsystems broken independently (e.g. cron didn't fire AND vendor webhook is rejected AND nginx is logging 502s; three boundaries to investigate).
- Each problem can be understood without context from the others.
- No shared state between investigations (sub-agents won't edit the same files or contend for the same resources).

### When NOT to fire

- Failures look related (fixing one might fix the others). Investigate sequentially first; sometimes one root cause produces multiple symptoms.
- Need to understand full system state before splitting (exploratory phase).
- Sub-agents would interfere (editing the same files, contending for the same database, holding the same lock).
- One sub-agent's output is needed to brief the next (sequential dependency).

### Pattern

1. **Identify independent domains.** Group failures or tasks by what's broken, what file they touch, what subsystem they belong to. If two domains overlap, merge them into one larger sub-agent task; do not split.
2. **Create focused agent briefs.** Each gets: specific scope (one test file, one subsystem, one investigation), clear goal (make these tests pass; diagnose this 502; fix this race), constraints (don't change other code, don't refactor, don't widen scope), and expected output (a 120-word return summary plus diff).
3. **Dispatch concurrently.** Send all `Agent` tool calls in a single message so they run in parallel. Master collects all summaries when they return.
4. **Review and integrate.** For each return: read the summary, verify changes, check for cross-conflicts (did two agents touch the same file unexpectedly?). Then run the full test suite or the equivalent verification across all affected components. The integration step catches the "agents made systematic errors" class of bug.

### Brief template additions for parallel dispatch

In addition to the standing-instructions + memory precondition and the canonical-path-pinning preamble (both per their sections above), include in each parallel brief:

- **Scope statement:** "Your scope is X only. Do NOT touch Y or Z (other agents are handling those)."
- **Constraint statement:** "Do NOT change production code outside X" or "Fix tests only" or whatever the boundary is.
- **Return contract:** specific list of what the summary should contain (root cause identified, files changed, tests passing, any side findings flagged).

Without these, agents widen their scope and start stepping on each other.

### Common mistakes

- **Too broad:** "Fix all the tests" sends one agent in N parallel copies; they all overlap. Specific scope per agent.
- **No constraints:** agent decides to refactor a shared module while another agent is editing it. Constrain explicitly.
- **No integration step:** all agents return clean summaries, but the merged result has 3 silent conflicts. Run the full verification after collecting all returns.
- **Splitting related failures:** a deploy breaks 6 tests. They look independent but are caused by one config change. Investigate together first; only split if root causes are confirmed disjoint.

## Parallel-Design Sub-Agents (Design It Twice)

Adapted from John Ousterhout's "Design It Twice" principle. Use this pattern when the user wants to explore alternative interfaces for a chosen problem (typically a deepening candidate from `improve-codebase-architecture`). Your first interface idea is unlikely to be the best.

### When this fires

- After a deepening candidate has been chosen (per `improve-codebase-architecture`'s grilling loop) and the user wants to explore interface options.
- When a new port or shared service is being designed and the user wants alternatives surfaced before committing.
- When a tech-pick has multiple plausible interface shapes (DB access, message-passing, validation library).

### Process

#### 1. Frame the problem space (master, before spawning)

Write a user-facing explanation of the problem space. This goes to the user, not to the sub-agents.

- The constraints any new interface would need to satisfy.
- The dependencies it would rely on, and which category they fall into (`greedy-with-constraints` § Dependency categories for deepening).
- A rough illustrative code sketch to ground the constraints. Not a proposal; just a way to make the constraints concrete.

Show this to the user, then immediately proceed to step 2. The user reads and thinks while the sub-agents work in parallel.

#### 2. Spawn 3+ sub-agents in parallel

Each must produce a **radically different** interface for the deepened module. Use the Agent tool with `subagent_type=general-purpose` (or `Plan` for design-only output). Send all spawns in a single tool-block so they run concurrently.

Prompt each sub-agent with a separate technical brief:

- The canonical-path-pinning preamble (per the section above).
- File paths, coupling details, dependency category, what sits behind the seam.
- A different design constraint per agent. Suggested constraints (rotate as needed):

| Agent | Constraint |
|---|---|
| 1 | "Minimise the interface; aim for 1-3 entry points max. Maximise leverage per entry point." |
| 2 | "Maximise flexibility; support many use cases and extension." |
| 3 | "Optimise for the most common caller; make the default case trivial." |
| 4 (if applicable) | "Design around ports and adapters for cross-seam dependencies." |

Include both `greedy-with-constraints` vocabulary (module / interface / seam / adapter / depth / leverage / locality) and the project's domain vocabulary (CONTEXT.md if present) in each brief, so the proposals all use consistent language.

Each sub-agent's return contract:

1. The proposed interface (types, methods, parameters, plus invariants, ordering, error modes).
2. A usage example showing how callers use it.
3. What the implementation hides behind the seam.
4. Dependency strategy and adapters (per dependency category).
5. Trade-offs: where leverage is high, where it is thin.

Sub-agents are leaves. They do NOT spawn sub-sub-agents.

#### 3. Present and compare (master)

Present designs sequentially so the user can absorb each one, then compare them in prose. Contrast by:

- **Depth** (leverage at the interface).
- **Locality** (where change concentrates).
- **Seam placement** (where the boundary lives).
- **Cost of being wrong** (which design is hardest to migrate away from later).

After comparing, give your own recommendation: which design you think is strongest and why. Be opinionated; the user wants a strong read, not a menu.

If elements from different designs would combine well, propose a hybrid. Name what comes from where.

#### 4. AskUserQuestion to commit

Surface the recommendation plus alternatives via `AskUserQuestion` (per the standard "do not default-then-act" rule). Options: each candidate by name, or "hybrid: \<sketch\>", or "go back; the brief was wrong". Do not silently pick.

### When NOT to use this pattern

- The interface choice is obvious (one design dominates on all axes).
- The interface is not a new design but a refinement of an existing one.
- The chunk is a fix or bug-only change with no design surface.
- The user has already committed to an interface shape (do not litigate).

## Specialist review dispatches

Some review passes are deep enough to warrant their own sub-agent dispatch with a focused brief, separate from the general-purpose code-review covered by `completion-gate` Layer 2. Catalogue:

### GHA security review

Folded from getsentry/skills/gha-security-review. Use when reviewing a change to `.github/workflows/*` in a repo that any external attacker could open a PR against (effectively all public repos and many private ones with fork-PR support enabled).

Threat model: external attacker WITHOUT write access to the repo. Can open PRs from forks, create issues, post comments. Cannot push to branches, trigger `workflow_dispatch`, or run manual workflows.

Dispatch a `general-purpose` sub-agent with this brief shape:

- **Scope:** review all `.github/workflows/*.yml` plus any `action.yml` / `.github/actions/*/action.yml` in the diff. Trace into config files loaded by workflows (`CLAUDE.md`, `AGENTS.md`, `Makefile`, shell scripts under `.github/`).
- **Threat model:** external-attacker-without-write-access ONLY. Do NOT flag findings that require `workflow_dispatch` access or push to protected branches, nor `workflow_call` input injection where every caller is internal, nor secrets used in `workflow_dispatch`-only or `schedule`-only workflows. Those four exclusions are what keep the reviewer's false-positive rate down.
- **Confidence threshold:** report only HIGH and MEDIUM findings. LOW / theoretical issues are dropped.
- **Vulnerability classes to check** (load only the references that match the triggers found):
  - Pwn-request (`pull_request_target` + checkout of fork code).
  - Expression injection (`${{ <attacker-controlled> }}` inside `run:` blocks).
  - Comment-triggered commands without `author_association` check.
  - Credential escalation (PATs, deploy keys accessible to untrusted code).
  - Config-file poisoning (workflow loads PR-supplied `Makefile`, shell scripts, or other build inputs that get EXECUTED).
  - AI prompt injection via CI (workflow loads PR-supplied `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, or similar agent-instruction files AS INPUT to an LLM running inside CI; attacker hijacks the agent's behaviour rather than running shell commands).
  - Supply chain (third-party actions pinned to mutable tags instead of full SHA).
  - Permissions and secrets (over-privileged `GITHUB_TOKEN`, secrets exposed to fork PRs).
  - Self-hosted runner / cache / artifact misuse.
- **Trigger-to-reference loading map** (load the matching reference file only when the trigger / pattern is present in the workflow; avoids bloating the sub-agent's context with references it does not need):

  | Trigger / pattern in the workflow | Reference to load |
  |---|---|
  | `pull_request_target` trigger | `references/pwn-request.md` |
  | `issue_comment` with command parsing | `references/comment-triggered-commands.md` |
  | `${{ }}` interpolation inside `run:` blocks | `references/expression-injection.md` |
  | PAT / deploy key / elevated-scope credential reachable from PR code | `references/credential-escalation.md` |
  | Checkout of PR code AND load of an agent-instruction config file (`CLAUDE.md` / `AGENTS.md` / `.cursorrules`) | `references/ai-prompt-injection-via-ci.md` |
  | Third-party action invocation (especially unpinned to full SHA) | `references/supply-chain.md` |
  | `permissions:` block or `secrets.*` usage in the workflow | `references/permissions-and-secrets.md` |
  | Self-hosted runners; cache or artifact upload / download | `references/runner-infrastructure.md` |
  | Any confirmed finding (for attacker-pattern context) | `references/real-world-attacks.md` |

  References live under `getsentry/skills/gha-security-review/references/` upstream; the sub-agent should fetch them if the upstream plugin is not installed locally.
- **Five-element finding contract** (every HIGH finding requires all five; if you can't construct all five, downgrade to MEDIUM "needs verification" or drop):
  1. Entry point (how does the attacker get in: fork PR, issue comment, branch name).
  2. Payload (what does the attacker send: actual code / YAML / input).
  3. Execution mechanism (how does the payload run: expression expansion, checkout + script).
  4. Impact (what does the attacker gain: token theft, code execution, repo write access).
  5. PoC sketch (concrete steps an attacker would follow).
- **Safe patterns table** (do NOT flag): `pull_request_target` WITHOUT fork checkout, numeric IDs, `${{ secrets.* }}`, `${{ }}` in `if:` / `with:` / job-level `env:`, full-SHA pinning, first-party `actions/*` and `github/*` on a version tag, `pull_request` trigger.
- **Privilege gate** (the secret-exfiltration and privilege-escalation finding classes do not apply): a job with no `secrets` in scope, a read-only `GITHUB_TOKEN` (`permissions: contents: read` or narrower), and no fork checkout has nothing to leak or escalate. Do not raise those finding classes against it; an unpinned third-party action there is a hygiene note, not a HIGH finding.
- **Validation step** before reporting any finding: read the actual workflow YAML, trace the trigger, confirm the expression / checkout, confirm attacker control, check existing mitigations.
- **No-finding case:** if no checks produced a finding, report zero findings. Do NOT invent issues.

Cross-reference: `secrets-hygiene` § GitHub Actions secrets discipline carries the defensive patterns this review surfaces violations of. Land them together when adopting the recommendations.

## Red Flags

- Master reading a whole file mid-chunk "just to check".
- Any hand-off brief (sub-agent, spawn_task chip, throwaway-session prompt, TaskCreate, scheduled/cron agent, PR body handing off work) WITHOUT the standing-instructions + memory precondition at the top. The recurring miss: handed-off work that ran bare `gh` and failed the multi-PAT keychain rule because the brief never told the new session to read memory.
- Sub-agent brief without the canonical-path block on a worktree-flavoured repo.
- Cross-cutting fix briefed without the adjacent-pattern scan instruction.
- Public-surface change pushed without the master-side blast-radius grep.
- Adjacent finding tucked into a PR-body footnote instead of an AskUserQuestion.
- Generalisable pattern silently extracted (or silently duplicated) without the four-option AskUserQuestion.
- Sub-agent spawning a sub-sub-agent for non-fan-out work.
- Parallel-design sub-agents producing interfaces that converge (the constraints were not differentiated enough; rebrief with sharper constraints).
- Master picking a parallel-design winner without surfacing the choice via AskUserQuestion.
- Plan-execution loop pausing between tasks to ask "should I continue?" (the user briefed the plan; execute it).
- Plan-execution loop skipping spec-compliance review (jumping straight to code-quality review or skipping review entirely).
- Plan-execution loop running spec-compliance review AFTER code-quality review (wrong order; spec drift makes quality cleanup wasted work).
- Implementer subagent reporting BLOCKED and master re-dispatching the same model with the same brief (something needs to change; either context, model class, or the task itself).
- All implementer subagents dispatched with the most capable model regardless of task complexity (cost / speed waste; use the least powerful model that handles the task).
- Parallel-Dispatch fired on related failures (one root cause producing multiple symptoms; sub-agents will all "fix" the symptom and miss the cause).
- Parallel-Dispatch brief without scope and constraint statements (sub-agents widen scope and step on each other).
- Parallel-Dispatch with no integration step (all returns look clean individually; merged result has silent conflicts).
- GHA security review reporting LOW / theoretical findings (only HIGH and MEDIUM go to master; LOW is noise).
- GHA security review HIGH finding without all five elements (entry point, payload, execution mechanism, impact, PoC sketch); should have been downgraded to MEDIUM or dropped.
- GHA security review brief widening scope to write-access threats (`workflow_dispatch` input injection on protected branches); those are out of the threat model.

Fix-loop rationalisations, each of which ends the loop early or lets it run forever:

| Excuse | Reality |
|---|---|
| "One more round will converge" | Past the cap, rounds do not converge; the failure is structural. Adjudicate and route. |
| "The re-reviewer will just find something new anyway" | A scoped re-review verifies fixes and cannot wander. New findings on untouched code go to the ledger, not the loop. |
| "This finding is obviously wrong, I'll drop it" | You adjudicate only at the cap, and every ruling is a ledger entry. Silent discards are forbidden. |
| "The fix was small, skip the re-review" | Unreviewed fixes are how regressions land. Every round ends with a scoped re-review. |
| "I'll just fix it myself, dispatching is overhead" | Controller fixes pollute the coordination context and skip review. Resume the implementer. |
| "Ledger bookkeeping is overhead" | The ledger is what survives compaction. Controllers without one have re-dispatched entire completed task sequences. |
| "Close enough on spec compliance" | A reviewer finding spec gaps means not done. Fix, or hit the cap and adjudicate. Those are the only two exits. |

## Bottom Line

Master holds the plan. Sub-agents do the I/O. Every contract change gets a blast-radius grep before push. Every adjacent finding and every generalisable pattern gets an AskUserQuestion before push. For new interface design, spawn 3+ parallel sub-agents with differentiated constraints; present, compare, recommend, ask. No silent decisions, no silent peeks.

Every fix loop is bounded: five rounds, then you adjudicate on the record. A loop with no cap and a re-review with no scope are the two ways a task runs forever.
