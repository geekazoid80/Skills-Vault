---
name: plan-time-tooling
description: "Use during plan-mode entry for any non-trivial chunk, AND when writing or reviewing a plan file, AND at the start of executing an approved plan, AND at chunk completion for the tech-debt pass, AND at chunk-zero in a fresh repo (settings allowlist audit). Enumerates which installed skills and connected MCP servers should fire for the work, scans the wider ecosystem (skills.sh, mcp-registry, common third-party repos like obra/superpowers, anthropics/skills, vercel-labs/skills, mattpocock/skills, coreyhaines31/marketingskills, pbakaus/impeccable, ComposioHQ/awesome-claude-skills) for tools that would expedite the chunk, lists them in a \"Tooling to use this chunk\" section in the plan, and surfaces tooling decisions for AskUserQuestion alongside scope decisions. Mandatory triggers covered: engineering:architecture (new port, cross-module pattern, new tech choice, contract change); engineering:deploy-checklist (infra, migration with data shape change, env-var boot check, OIDC, first deploy, any production-mutating operation); engineering:code-review (sub-agent diff over 50 LOC, public contract, new module); engineering:tech-debt (at chunk completion, to evaluate interaction with prior chunks; not for small commits or bookkeeping). Chunk-zero settings audit (detect tech stack, propose .claude/settings.json read-only Bash allowlist; folded from getsentry/skills/claude-settings-audit; pairs with bundled fewer-permission-prompts skill). Plan-execution discipline (load plan, critique before executing, raise concerns before any code is written; folded from obra/superpowers/skills/executing-plans). Plan-quality discipline (no-placeholders rule + self-review checklist for spec coverage, placeholder scan, type/signature consistency; folded selectively from obra/superpowers/skills/writing-plans). Per-chunk discipline (Step 0 memory re-read, standing-reminder block) is enforced by the dedicated `reread-memory-before-planning` skill; this skill provides the Tooling section that slots into the chunk-body skeleton. Triggers also include \"draft a plan body\", \"scope a new chunk\", \"after compact\". Includes situational-skill catalogue and the MCP catalogue."
metadata:
  version: 1.2.0
---

# Plan-time Tooling Evaluation

> **Skill marker**: When applying this skill, begin your reply with `[skill: plan-time-tooling]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

At planning time, BEFORE writing the final plan to the plan file, explicitly evaluate whether any installed skill or MCP server would simplify the work. The cost is one quick scan. The saving is hours of re-inventing what already exists.

**Core principle:** the plan file lists tooling alongside scope. Silent omission means the tool will probably be missed.

## What goes into the plan file

A heading near the top of the plan file: `## Tooling to use this chunk`. Under it:

- Each mandatory-trigger skill that fires for this chunk, with the trigger reason.
- Each situational skill that you considered AND chose to use, with reasoning.
- Each MCP server that gives a verification surface for the chunk's acceptance criteria.
- If none apply: write `no skill or MCP applies for this chunk`. Explicit absence beats silently forgetting.

## Mandatory triggers

Three skills are mandatory at their triggers. Plan-mode must enumerate which fire.

### `engineering:architecture` (at plan time, before sub-agent brief)

Triggers:
- New port in a shared package (cross-module contract).
- New technology or library choice where alternatives existed (DB choice, queue choice, validation library, auth wrapper).
- New cross-module pattern (e.g. an approval-policy resolver used by multiple modules).
- Change to an existing public contract that downstream consumers must follow.

Skip when:
- Pure fix or extension that follows existing patterns and adds no new decision.

How to run:
- Invoke at plan-mode time, BEFORE the implementation sub-agent is briefed.
- Output goes into `docs/adr/00XX-<title>.md` (use the project's ADR scaffold script if there is one).
- The plan file's "Critical files" section lists the new ADR path.
- The implementation sub-agent's brief references the ADR by number ("ship per ADR-00XX").

### `engineering:deploy-checklist` (at plan time, before sub-agent brief)

Triggers:
- LXC, VM, or container bring-up.
- DB migration that changes data shape (vs. additive nullable column).
- New env-var-driven boot check.
- OIDC handshake, SSO config, or secrets rotation.
- First deploy of a new module to staging or live.
- ANY operation in the project's backup runbook, or any production-mutating operation that needs a pre-change backup per the project's hard rules.

Skip when:
- Pure code with no deploy-side change (controller refactor, test addition, schema-shape-only domain edit).

How to run:
- Invoke at plan-mode time.
- Output becomes either a new file under `docs/runbooks/<chunk-id>.md` (preferred for re-runnable procedures), or a `## Deploy checklist` section in the chunk's PR description (one-off deploys).
- The implementation sub-agent's brief includes "follow the deploy checklist at \<path\>" so the runbook is verified, not just written.

### `engineering:code-review` (at sub-agent return, before push)

Detail belongs in `completion-gate`, but it is mandatory and should be listed in the plan's tooling section so the sub-agent return step is not an afterthought.

Triggers:
- Sub-agent diff >50 LOC.
- Diff touches a public contract.
- Diff adds a new module or integration.

Skip ONLY for trivial diffs (typo fixes, single-line adjustments, bookkeeping commits).

### `engineering:tech-debt` (at chunk completion)

Mandatory at the end of every completed chunk (PR merged, feature delivered, runbook validated). Evaluates the new chunk's interaction with prior chunks and surfaces decay that the chunk did not introduce but did expose. Catches the "this chunk works, but the next one will trip on what we just left behind" class of issue.

Triggers:
- A chunk completes (PR merged, feature shipped, deploy validated).
- Multiple chunks have landed since the last debt evaluation (cumulative drift).
- A new public surface was added in the chunk; check for orphan callers, stale docs, abandoned shims left over from previous chunks.

Skip ONLY for:
- Small commits (typo fixes, single-line adjustments, bookkeeping).
- Hot-fixes shipped under time pressure (run the debt pass on the follow-up clean-up chunk instead).
- Chunks that have already had a debt pass within the same hour (no double-running).

How to run:
- After the chunk's PR merges, invoke `engineering:tech-debt` against the cumulative diff since the last debt pass (not just this chunk's diff).
- Output goes into a triage list: per item, surface via `AskUserQuestion` (fix in next chunk / file follow-up issue / accept and document).
- The plan for the next chunk's "Tooling to use this chunk" section incorporates whatever the debt pass surfaced.

## Situational skills (evaluate every plan; not mandatory)

| Skill | When to use | Default for fixes / extensions |
|---|---|---|
| `engineering:debug` | Fixing an unknown failure with a non-obvious root cause | Skip when the cause is already known |
| `engineering:incident-response` | Production incident triage | Skip for planned chunks |
| `engineering:system-design` | Greenfield module or service from scratch | Yes for greenfield; no for fixes / extensions |
| `engineering:testing-strategy` | Test architecture is the deliverable | Skip when adding tests inside an existing strategy |
| `engineering:documentation` | Large prose lift (runbooks, onboarding guides) | Skip for inline AGENTS.md edits |

Marketing, design, finance, sales, etc. skills follow the same evaluation logic when the chunk crosses into those domains.

## MCP servers (evaluate every plan)

For each connected MCP, ask: *would this MCP let me verify or interact with a real external surface that is part of this chunk's acceptance?*

| Class | Examples | When relevant |
|---|---|---|
| Project routing (Asana, Box, Drive, Gmail, calendar) | `mcp__7f060563__asana_*`, `mcp__de7b8304__*` | Chunk validates an end-to-end routing or notification flow |
| Browser / preview | `Claude_in_Chrome`, `Claude_Preview` | Chunk has a web UI, Swagger UI, or rendered artifact to validate visually |
| Calendar | calendar MCP | Scheduling or time-window logic |
| Code execution | Desktop Commander, claude-api skill | Running code against a live system |

**Skill wrappers:** `asana-workflows`, `calendar-workflows`, `gmail-workflows`. Defer routing decisions for these three MCPs to the wrapper skills (which MCP-tool to reach for, draft-only vs send constraints, two-MCP routing for Asana, GID-resolution discipline, timezone discipline). Drive remains a raw MCP for now; a `drive-workflows` wrapper is deferred pending Box / OneDrive / SharePoint MCP wiring so the cloud-storage skill set lands as a consistent group.

### Estate access rules outrank a skill's tool routing

Whenever the tooling you enumerate includes a skill that names a **specific connector or tool** for reaching an external system, check the estate's standing rules for that surface before the plan locks the access path in. Estates commonly pin how a system is reached (direct API only, a named token identity, a particular connector forbidden) for identity control, production parity, and auditability. Where such a rule exists it **overrides the skill's routing**, and the plan should say so explicitly in its tooling section rather than leave the skill's default standing.

This check exists because the failure mode is invisible: a generic skill can give routing advice that contradicts an estate rule, so **invoking the correct skill is precisely what produces the violation**. The usual defences do not fire, since the skill loaded on the right trigger and its advice was followed faithfully. Credentials, identity, and audit trail are exactly what estate rules pin down, so treat any skill that names a tool by name as the high-risk shape. When you find a contradiction, fix the skill rather than working around it once, and raise it with the vault owner where the fix spans a public and a private vault.

## Scanning beyond the installed set

The installed skills and connected MCPs are not the universe. At plan time, also scan the wider ecosystem for tools that would expedite the chunk and have not been adopted yet. The cost is one short fetch per candidate; the saving is hours of re-implementing what already exists upstream.

### Where to look

| Source | What it catalogues | When to scan it |
|---|---|---|
| [skills.sh](https://skills.sh/) | Open agent skills leaderboard, ranked by install count | Chunk involves a domain (testing, debugging, design, marketing, ops) where a battle-tested skill probably already exists |
| `npx skills find <query>` | CLI-driven skill discovery | Same; faster when the domain keyword is precise |
| `mcp-registry` MCP server | Searchable registry of MCP servers | Chunk needs a tool integration (vendor API, file-format handler, calendar, browser) and a server may already wrap it |
| Anthropic bundled skills | `engineering:*`, `design:*`, `marketing:*`, `finance:*`, `legal:*`, `sales:*`, `data:*`, `customer-support:*`, `human-resources:*`, `operations:*`, `product-management:*` | Always; these load by default in Claude Code, no install step |
| Common third-party skill repos | `obra/superpowers`, `vercel-labs/skills`, `anthropics/skills`, `mattpocock/skills`, `coreyhaines31/marketingskills`, `pbakaus/impeccable`, `ComposioHQ/awesome-claude-skills` | Chunk's domain matches a repo's specialism (TS, Next.js, marketing, design polish, prose) |
| GitHub `awesome-*` lists | Curated domain catalogues | Less Claude-specific; useful when the chunk needs a CLI or library, not a skill |

### Triage of candidates

For each candidate that looks relevant, classify per the patterns documented in `merged-skills-registry`:

1. **Adopt as-is** (existing `add-skill.sh`): the upstream is a perfect fit, no customisation needed.
2. **Customise from upstream**: the upstream is the right shape but needs trimming or local context (e.g. brand-guide pin); fetch and edit before writing the local skill.
3. **Fold into an existing local skill**: the upstream operationally overlaps something in the vault; merge content, register the upstream in `merged-skills-registry`.
4. **Skip but watchlist**: not a fit now, but might be later; record in the registry's watchlist section.

### Skip when

- The chunk is a pure local fix and no external tooling is plausible.
- A previous chunk's plan already evaluated the same ecosystem slice (do not re-scan within a week unless the chunk's domain is materially different).
- The wider-ecosystem scan would itself expand the chunk's scope beyond what the user authorised.

### Surface candidates via AskUserQuestion

When the scan finds 1+ candidate worth adopting, surface as a plan-time decision: per candidate, "adopt as-is / customise / fold into existing / skip + watchlist". Do not silently install (the `add-skill.sh` step is the user's call).
| Search / discovery | `enterprise-search:*`, `mcp-registry__*` | Locating prior decisions or related material |

If a connected MCP gives a real-surface verification path, list it. If none does, write that.

## Cheat-sheet

| Stage | Skill | Trigger | Skip when |
|---|---|---|---|
| Plan mode (before sub-agent) | `engineering:architecture` | New port, cross-module pattern, new tech choice, contract change | Pure fix following existing pattern |
| Plan mode (before sub-agent) | `engineering:deploy-checklist` | Infra, migration, boot env, OIDC, first deploy, production-mutating op | Pure code, no deploy-side change |
| Plan mode (every plan) | Wider-ecosystem scan (skills.sh, mcp-registry, common third-party repos) | Domain matches an external skill or MCP that could expedite the chunk | Pure local fix; same ecosystem slice scanned within the past week |
| Sub-agent return (before push) | `engineering:code-review` | Diff >50 LOC OR public contract OR new module | Trivial diff |
| Chunk completion (after PR merge) | `engineering:tech-debt` | Chunk has landed; evaluate interaction with prior chunks and decay exposed | Small commits, bookkeeping, hot-fixes; debt pass already run within the past hour |

## Chunk-zero discipline (first plan in a fresh repo)

Folded from getsentry/skills/claude-settings-audit. When the chunk is the FIRST plan-mode entry in a fresh repository (or in a repo that has never had a `.claude/settings.json` permissions audit), run a chunk-zero settings-audit pass before writing the chunk's plan.

### Why

Without a project-scoped `.claude/settings.json` allowlist, every read-only Bash call (`ls`, `git status`, `git log`, `gh pr view`, the project's typecheck, the package manager's `install`, etc.) prompts the user for permission. The promptings add up; they break flow; they push the user toward "yolo mode" which is worse for safety.

A one-time audit that detects the project's tech stack, identifies the read-only commands the project routinely needs, and writes a scoped allowlist into `.claude/settings.json` removes the prompts for safe commands without removing the gates on dangerous ones.

### When this fires

- First Claude Code session in a fresh repository.
- A repo where `.claude/settings.json` does not exist or has only the bundled defaults.
- A repo that has accumulated a long Bash allowlist over time and is due an audit (drift / over-permissions).

Skip if:

- The repo already has a project-scoped `.claude/settings.json` that covers the routine reads.
- The user has explicitly opted out of project-scoped settings (some projects keep all permissions in `~/.claude/settings.json` instead).

### How to run

Use the bundled `fewer-permission-prompts` skill (Anthropic-shipped) or the `getsentry/skills/claude-settings-audit` upstream as the implementation; both detect the tech stack and propose the right allowlist. The discipline this section codifies is when to trigger them, not how the detection works.

After the audit:

- Stack-specific reads added to the allowlist (e.g. `Bash(npm:*)`, `Bash(prisma:*)`, `Bash(cargo check:*)`).
- Service detections noted (Sentry / Linear / etc.) so the next chunk's `Tooling to use this chunk` section can include the relevant MCPs.
- The ALLOW list goes in project `.claude/settings.json`; the user's `~/.claude/settings.json` is not touched.

### Skip if you cannot detect

If the repo doesn't match any known tech-stack signature (no `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` / etc.), do NOT default to a generic permissive allowlist. Surface the gap to the user; let them name the routine commands they want allowed.

## Plan-execution discipline (after plan is approved, before code)

Folded from obra/superpowers/skills/executing-plans. Once a plan has been approved (the user has said "go" or "proceed", or ExitPlanMode has fired), there is one more cadence step before code starts: load the plan, critique it, surface concerns. This is cheap and catches plan-time-tooling gaps that the original plan-mode entry missed.

### The pre-execution loop

1. **Load the plan file fresh.** Re-read it; do not rely on the chat-context version.
2. **Critique critically.** What does the plan assume? Are the acceptance criteria precise? Are the verification commands specific? Are the file paths complete? Is the "Tooling to use this chunk" section present and current?
3. **Raise concerns BEFORE any code is written.** If the plan has gaps, ambiguities, or missing tooling triggers, surface them via AskUserQuestion. Do not silently fill in the gap by guessing.
4. **No concerns: create TodoWrite with one item per task in the plan.** Then proceed to execution.

This step is cheap (one file read + one critique pass) and catches the class of bug where the plan looked complete in plan-mode but reveals a gap once you start to execute.

### Concerns that must stop execution

These are the kinds of plan-side gaps that warrant pausing and asking BEFORE the first task is dispatched:

- A task references a file that does not exist (master misnamed it; sub-agent will fail).
- An acceptance criterion is vague ("the response is correct"; correct how, vs what fixture).
- A verification command is missing (sub-agent has nothing to run to claim done).
- A mandatory-trigger skill (engineering:architecture / deploy-checklist) was not enumerated for a task that obviously triggers it.
- A migration / contract change / public-surface edit is buried inside what was meant to be a fix-only chunk.
- The task list is too coarse (one task = "implement the entire feature"; should be decomposed into bite-sized steps).
- **The plan mandates something the review rubric would call a defect** (a test that asserts nothing, verbatim duplication of a logic block), or two tasks contradict each other or the plan's Global Constraints.

The cost of stopping for 30 seconds to ask is much less than the cost of a sub-agent shipping the wrong thing because the plan was vague.

**Batch the findings into one question.** Present everything the critique surfaced as a single AskUserQuestion, each finding placed beside the plan text that mandates it, asking which governs. One batched question before execution beats an interrupt per discovery mid-plan. If the scan is clean, proceed without comment; do not narrate a clean result.

The same rule holds during execution: a finding that conflicts with what the plan requires is the user's decision. Present the finding and the plan text and ask which governs. Do not dismiss the finding because the plan mandates it, and do not dispatch a fix that contradicts the plan without asking.

### Execution itself: when to delegate

Once the plan passes the pre-execution critique, follow the standard delegation pattern: per-task subagent dispatch via the plan-execution loop in `subagent-delegation`. That section covers the per-task workflow (fresh subagent per task, two-stage review, implementer status model, model selection per task complexity, continuous execution).

### When to revisit the plan mid-execution

Pause and re-enter plan mode when:

- The user updates the plan based on mid-execution feedback. Restart the pre-execution critique.
- A task reveals that the fundamental approach needs rethinking (this is the 3-failed-fixes signal from `systematic-debugging` mapped onto plan execution).
- A subagent's BLOCKED status escalates and the resolution requires a plan change (not just a context tweak).

Don't force through blockers. Stop and ask.

## Plan-quality discipline (writing the plan itself)

Folded selectively from obra/superpowers/skills/writing-plans. Two rules carry across to this vault's lighter plan-mode workflow; the upstream's prescriptive doc-paths and required-sub-skill cross-refs do not.

### No placeholders

Every step in the plan must contain the actual content the executor needs. The following are plan failures, never write them:

- "TBD", "TODO", "implement later", "fill in details".
- "Add appropriate error handling" / "add validation" / "handle edge cases" without saying which.
- "Write tests for the above" without actual test code or specific assertion to make.
- "Similar to Task N" (repeat the code; the executor may read tasks out of order).
- Steps that describe what to do without showing how (code blocks required for code steps).
- References to types, functions, or methods not defined anywhere in the plan.

A placeholder in a plan is a deferred decision. Make the decision now (or surface it via AskUserQuestion); don't push it onto the executor.

### Task right-sizing

A task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate.

- Fold setup, configuration, scaffolding, and documentation steps into the task whose deliverable needs them. They are not tasks of their own.
- Split only where a reviewer could meaningfully reject one task while approving its neighbour.
- Every task ends with an independently testable deliverable.

That reviewer test is the useful one, because it is the same gate the per-task subagent dispatch actually applies.

### Global Constraints block

The plan carries a Global Constraints section holding the project-wide requirements from the spec: version floors, dependency limits, naming and copy rules, platform requirements. One line each, exact values copied verbatim.

Every task's requirements implicitly include this section. It matters downstream twice over: an implementer subagent sees only its own task and would otherwise never learn the project-wide constraint, and the constraints block is what you hand a reviewer as its attention lens. Copy the binding requirements verbatim into the reviewer's brief, including exact values, exact formats, and stated relationships between components ("same layout as X", "matches Y"). The reviewer template already carries the process rules; the constraints block is for what THIS project's spec demands.

### Per-task Interfaces block (Consumes / Produces)

Each task declares what it consumes from earlier tasks (exact signatures) and what it produces that later tasks rely on (exact function names, parameter and return types).

The reason is the same fresh-subagent-per-task model: an implementer sees only their own task, so this block is the only way they learn the names and types their neighbours use. This is the structural fix for the drift that self-review checklist item 3 below can only catch after the fact. Prevention beats detection.

### Self-review checklist (before approving the plan for execution)

After writing or accepting a plan and BEFORE handing it off to a sub-agent or starting execution, run a quick self-review against the spec:

1. **Spec coverage.** Skim each section of the spec / brief / roadmap row. Can you point to a task in the plan that implements it? List any gaps.
2. **Placeholder scan.** Search the plan for the patterns in "No placeholders" above. Fix them before execution starts.
3. **Type / signature consistency.** Do the types, method signatures, and property names used in later tasks match what was defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug; catch it now.

If the review surfaces issues, fix them inline. No need to re-review; just fix and move on. If the review surfaces a spec requirement with no task, add the task before execution starts.

This discipline is the upstream's "Self-Review" step adapted for the vault's plan-mode workflow. The full upstream additionally mandates a specific doc path, a specific header format, and an "execution handoff" choice between two superpowers skills; those pieces do not apply here (plan mode + ExitPlanMode + the plan-execution discipline above already cover the workflow).

## Per-chunk discipline checklist (multi-chunk project pattern)

The full Per-chunk discipline checklist (Step 0 memory re-read across all 4 classes: global memory + project memory + project AGENTS.md + skills/MCPs enumeration, plus the chunk-body skeleton of `## Reminders` → `## Status snapshot` → `## Memory cross-reference` → `## Tooling to use this chunk` → `## Design / Scope / Verification gates`, plus the standing-reminder template every plan file MUST carry at the top) lives in the dedicated `reread-memory-before-planning` skill (`~/.claude/skills/reread-memory-before-planning/SKILL.md`). That skill is the single source of truth for the discipline; copy its standing-reminder template verbatim into any new plan file.

This skill (`plan-time-tooling`) contributes the `## Tooling to use this chunk` section that slots into that skeleton, including the mandatory-trigger evaluation (architecture, deploy-checklist, code-review, tech-debt) and the situational-skill + MCP catalogue.

## AskUserQuestion at plan time

Tooling decisions deserve `AskUserQuestion` alongside scope decisions. Examples:

- "Architecture trigger fires (new port). Use `engineering:architecture` to scaffold the ADR, or you have already written one elsewhere?"
- "Deploy-checklist trigger fires (env-var boot check). Output as a runbook file under `docs/runbooks/`, or as a section in the PR description?"
- "MCP `Claude_Preview` is connected. Use it to verify the UI before push, or skip and rely on screenshots?"

Do not silently pick. Surface the decision.

## Red Flags

- Plan written without a "Tooling to use this chunk" section.
- Mandatory trigger fired and the skill was not invoked.
- A skill that names a specific connector or tool enumerated in the plan without checking the estate's access rule for that surface first.
- ADR backfilled after the implementation sub-agent already shipped.
- Deploy checklist written after the deploy.
- A connected MCP that would have caught a regression was not used.
- Plan execution started without the pre-execution critique (loaded plan, looked complete, dispatched first sub-agent immediately).
- Plan-side gap noticed during execution and silently filled in (the gap should have been surfaced via AskUserQuestion BEFORE the first task ran).
- Plan executed straight through despite a sub-agent BLOCKED status that needed a plan change (not just a context tweak); the BLOCKED was retried with the same brief.
- Plan written with placeholders ("TBD", "handle edge cases", "similar to Task N", "add appropriate error handling without saying which"). Placeholders are deferred decisions; surface or decide before handing the plan off.
- Plan handed off without the self-review pass (spec coverage, placeholder scan, type / signature consistency).
- First-plan in a fresh repo skipped the chunk-zero settings audit; the next 50 read-only Bash calls each prompt the user for permission.
- Chunk-zero settings audit defaulted to a generic permissive allowlist when the repo's tech stack couldn't be detected (should have surfaced the gap to the user instead).
- Chunk body's `## Tooling to use this chunk` section is absent or placed AFTER design content; canonical position is between memory cross-reference and design, per the skeleton enforced by `reread-memory-before-planning`.

## Bottom Line

At plan time, list the tooling. The list is part of the plan, not a footnote. Mandatory triggers are not optional. Situational skills and MCPs deserve a quick scan even when they end up unused, because the explicit "no" is the discipline.
