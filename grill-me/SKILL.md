---
name: grill-me
description: "Use to interview the user via a relentless, one-question-at-a-time conversation that walks down every branch of the decision tree. Two interview shapes. (A) STRESS-TEST an existing plan or design (\"grill me\", \"stress-test this\", \"interview me on this design\", \"challenge this plan\", \"poke holes in this\", \"be critical\"). (B) CREATIVE IDEATION when starting from a fuzzy idea (\"let's brainstorm X\", \"help me think through Y\", \"I want to design Z but I'm not sure where to start\", \"explore this idea with me\"). Two firing modes. (1) ON-DEMAND: user uses one of the trigger phrases above. (2) HYBRID auto-propose: at plan-mode entry, the agent assesses whether the chunk is high-stakes (multi-module, contract change, security-sensitive, irreversible, large blast radius, new tech choice, or first-of-kind) and ASKS the user \"Want me to grill this plan before we ship it?\" with a one-sentence stakes summary; user says yes or no. Per-question, the agent provides its recommended answer alongside the question. If a question can be answered by exploring the codebase, the agent explores instead of asking. Localised hybrid of mattpocock/skills/productivity/grill-me (stress-test mode) and obra/superpowers/skills/brainstorming (creative-ideation mode); strips upstream brainstorming's hard gates and writing-plans dep."
metadata:
  version: 1.0.0
---

# Grill Me

Interview the user, one question at a time, until the decision tree is resolved. Two interview shapes (stress-test vs. creative ideation), two firing modes (on-demand vs. hybrid auto-propose). The interview discipline is the same across all four combinations.

> **Skill marker**: When applying this skill, begin your reply with `[skill: grill-me]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Interview shapes

### A. Stress-test (existing plan or design)

You have a plan or design and want it grilled before committing. The interview probes for unexamined assumptions, missing edge cases, scope drift, dependency risk, contract gaps. The agent recommends per question; you confirm or redirect.

Example trigger: "I'm planning to ship the new audit port; grill me before I commit."

### B. Creative ideation (fuzzy idea, no plan yet)

You have an idea and want to think through what it actually is, before anything is committed to writing. The interview probes for purpose, constraints, success criteria, then proposes 2-3 approaches with the agent's recommendation. Once the shape is clear, the interview ends with a short design summary; the next chunk's plan can then crystallise from that summary (no separate "writing-plans" handoff is needed; the user picks up planning per their normal cadence).

Example trigger: "I want to think through how we'd do the customer-facing status portal, but I haven't sketched anything yet."

The agent picks the shape from the trigger phrasing, defaulting to (A) when the user references an existing plan / design / chunk and (B) when the user signals a blank page. If unsure, ASK once.

## When this fires

### On-demand (you ask)

**Stress-test triggers:** "grill me", "stress-test this plan", "interview me on this design", "challenge this", "poke holes in this", "be critical".

**Creative-ideation triggers:** "let's brainstorm X", "help me think through Y", "I want to design Z", "explore this idea with me", "I'm starting from scratch on X".

You explicitly request it; the interview starts. The agent picks the shape from the trigger phrasing.

### Hybrid auto-propose (agent suggests)

At plan-mode entry, the agent scans the chunk for "high-stakes" signals. If any fire, the agent ASKS:

> "This chunk looks high-stakes (\<one-sentence stakes summary\>). Want me to grill this plan before we ship it? Yes / No / Partial (specific area only)."

You decide per chunk. The agent does not auto-grill without your yes.

#### High-stakes signals (any one is enough to propose)

- **Multi-module:** the change touches more than one `modules/`, `apps/`, `integrations/`, or `packages/` folder.
- **Contract change:** an exported port, schema, controller pattern, env-var, or decorator placement is added, renamed, removed, or has its semantics altered.
- **Security-sensitive:** the change touches authentication, authorisation, RBAC, audit, secrets, jurisdiction-specific compliance, PII handling, or cross-tenant boundaries.
- **Irreversible:** the change cannot be rolled back without data loss, manual cleanup, or downstream consumer pin updates (database migration with shape change, deletion of a field still readable by older releases, etc.).
- **Large blast radius:** the change is referenced by more than ~5 call sites or pinned downstream repos.
- **New tech choice:** the change picks a database, queue, validation library, auth wrapper, or any technology where alternatives exist.
- **First-of-kind:** the change establishes a pattern that future similar work will follow (e.g. the first use of a new lifecycle hook, the first integration of a new vendor).

#### Low-stakes signals (skip auto-propose)

- Single-file fix, single-line tweak, typo, doc clarification.
- Bookkeeping (status flips, archive appends, roadmap row updates).
- A change that strictly follows an existing pattern in the codebase with no contract drift.
- A confirmed straight-line continuation of the current chunk.

If neither side fires confidently, proceed without proposing. Do not over-fire.

#### How to phrase the proposal

Keep it short and stakes-focused. Examples:

> "This chunk introduces a new port in `packages/audit-port/` and three consumers will need to wire it. Want me to grill this plan before we ship it? Yes / No / Partial (interface design only)."

> "This chunk renames `userEmail` to `contactEmail` on `User`; it touches 7 modules and is irreversible without a follow-up release. Want grilling? Yes / No / Partial."

If the user says "Partial \<area\>", scope the interview to the area named.

## The interview

The interview discipline is the same across both shapes and both firing modes. What differs is the starting point: stress-test starts from an existing plan; creative ideation starts from a fuzzy idea.

Walk down each branch of the design tree. Resolve dependencies between decisions one at a time. For each question, provide your recommended answer alongside the question (so the user can confirm-or-redirect rather than answer cold).

**Ask one question at a time.** Do not bundle.

**If a question can be answered by exploring the codebase, explore instead.** Do not ask the user something the code already says.

**Order questions by dependency.** A question whose answer depends on an earlier decision waits for that earlier decision to land. The user gets a coherent walk, not a scattered survey.

**Surface the trade-off, then recommend.** Do not present alternatives without a recommendation; the user wants a strong read, not a menu.

### Creative ideation: what to probe

When the interview shape is creative ideation (no plan yet), the early questions cover purpose, constraints, success criteria. The agent does this work BEFORE proposing approaches; cold proposals waste the user's time.

Question categories, in dependency order:

1. **Purpose:** what is this trying to do for whom? What is the user moment that motivates it?
2. **Scope:** is this one chunk, or does it decompose into independent pieces? If multiple subsystems are implied, flag it and decompose before refining detail.
3. **Constraints:** what are the hard limits (time, cost, headcount, data, vendor, regulatory)? What patterns or ADRs from the project should this respect?
4. **Success criteria:** how will we know it works? What is the failure mode that matters most?
5. **Approaches:** propose 2-3 approaches with trade-offs and the agent's recommendation; let the user pick or hybridise.
6. **Shape:** with the approach picked, talk through the architecture / data flow / error handling / test strategy at the depth the choice demands.

The agent scales each section to its complexity. A small change can resolve in 3-4 questions; a substantial design can resolve in 15-20.

### Decomposition trigger

If the user's request describes multiple independent subsystems ("build a platform with chat, file storage, billing, analytics"), flag this immediately. Do NOT spend questions refining details of a project that needs decomposition first.

Help the user split into sub-projects: what are the independent pieces, how do they relate, what order should they land. Then run the interview on the first sub-project per the question categories above. Each sub-project gets its own interview cycle.

## When to stop

The interview ends when:

- Every branch of the decision tree has been resolved (yes / no / deferred-with-rationale).
- The user explicitly says "stop", "enough", "we're good".
- The agent has nothing new to ask (do not pad with questions for the sake of asking).

Output at the end: a short summary of the decisions reached, the deferrals (with the rationale for deferring), and any open questions that could not be resolved without more information.

For creative ideation, the summary is the seed of the next chunk's plan: purpose, chosen approach, key constraints, success criteria. The user picks up from there per the normal cadence (re-enter plan mode, write the plan file, run `plan-time-tooling`). The agent does NOT auto-write a spec file or hand off to a separate "writing-plans" skill; that workflow is too rigid for the vault's lighter cadence.

## Cross-references

- `plan-time-tooling`: the standard tooling-and-MCP plan-time evaluation. Grilling fires AFTER the tooling list and BEFORE the implementation sub-agent is briefed.
- `subagent-delegation`: when the grilling surfaces a need to spawn sub-agents (parallel design exploration, surface mapping, etc.), use that skill's discipline.
- `improve-codebase-architecture`: the architecture-audit workflow embeds its own grilling loop for the chosen deepening candidate. That grilling is scoped to the architectural decision; this skill grills the broader plan.
- `completion-gate`: the post-implementation verification gate. Grilling does not replace verification; it stress-tests intent before code is written.

## Bottom line

Two interview shapes (stress-test an existing plan, or creatively ideate from a fuzzy idea). Two firing modes (on-demand by trigger phrase, or hybrid auto-propose at plan-mode entry on high-stakes signals). One discipline: one question at a time, recommend per question, explore the codebase before asking, stop when the tree is resolved or the user calls it.
