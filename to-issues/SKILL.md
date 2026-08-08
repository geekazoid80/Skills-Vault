---
name: to-issues
description: When the user wants to break a plan, spec, or PRD into independently-implementable issues on a project issue tracker using vertical slices (tracer bullets). Also use when the user mentions "convert this plan into issues," "break this down into tickets," "draft vertical slices," "tracer bullet issues," "create implementation tickets," "split into AFK / HITL work items," "publish these slices to GitHub / Linear / Jira," or "make issues from this spec." Use this whenever someone wants to turn a written plan into a queue of independently-grabbable work items. For drafting the PRD that becomes the source for slicing, see to-prd. For triaging issues once they exist on the tracker, see triage.
metadata:
  version: 1.0.0
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

> **Skill marker**: When applying this skill, begin your reply with `[skill: to-issues]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the project's issue tracker, label vocabulary, and any conventions for AFK / HITL work before drafting slices. Only ask the user for information not already covered.

Tracker handling:
- If the project uses GitHub, the agent should use `gh issue create` (per repo / org).
- If the project uses Linear, Jira, or another tracker with an MCP / CLI integration, use that.
- If no tracker integration is configured, present the slice list to the user for them to publish manually.

If the project has a `triage` skill or label vocabulary configured (e.g. `ready-for-agent`, `needs-info`), apply the same vocabulary; otherwise default to whatever the tracker's conventions are.

---

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes an issue reference (issue number, URL, or path) as an argument, fetch it from the issue tracker and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be HITL (human-in-the-loop) or AFK (away-from-keyboard). HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

#### Vertical slice rules

- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests).
- A completed slice is demoable or verifiable on its own.
- Prefer many thin slices over few thick ones.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right (too coarse, too fine)?
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Publish the issues to the issue tracker

For each approved slice, publish a new issue to the issue tracker. Use the issue body template below. These issues are considered ready for AFK agents, so publish them with the project's "ready-for-agent" triage label (or equivalent) unless instructed otherwise.

Publish issues in dependency order (blockers first) so you can reference real issue identifiers in the "Blocked by" field.

#### Issue body template

```markdown
## Parent

A reference to the parent issue on the issue tracker (if the source was an existing issue, otherwise omit this section).

## What to build

A concise description of this vertical slice. Describe the end-to-end behaviour, not layer-by-layer implementation.

Avoid specific file paths or code snippets; they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts; not a working demo, just the important bits.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- A reference to the blocking ticket (if any)

Or "None, can start immediately" if no blockers.
```

Do NOT close or modify any parent issue.

---

## Cross-references

- `to-prd`: drafts the PRD that to-issues then slices into work items; the natural upstream of this skill.
- `triage`: once issues are published, triage handles state transitions (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix).
- `systematic-debugging`: if a slice is a bug fix, run the diagnosis loop first to know the correct seam for the regression test.
- `improve-codebase-architecture`: if vertical slicing keeps revealing tangled coupling, the codebase architecture may need work before further slicing pays off.
- `subagent-delegation`: AFK slices that are large enough are good candidates for delegation; HITL slices stay in the main conversation.
