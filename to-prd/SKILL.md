---
name: to-prd
description: When the user wants to turn the current conversation context and codebase understanding into a PRD (product requirements document) and publish it to an issue tracker. Also use when the user mentions "write a PRD from this," "synthesise this into a PRD," "draft a PRD from what we've discussed," "create a spec from this thread," "publish this as a PRD," or "turn this into a product spec." Use this whenever someone wants the synthesis already in the conversation captured as a structured PRD without a fresh round of interviewing. For breaking a PRD into vertical-slice issues afterwards, see to-issues. For triaging issues that result, see triage.
metadata:
  version: 1.0.0
---

# To PRD

This skill takes the current conversation context and codebase understanding and produces a PRD. Do NOT interview the user; just synthesise what you already know.

> **Skill marker**: When applying this skill, begin your reply with `[skill: to-prd]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the project's issue tracker, PRD template conventions (if any), and triage label vocabulary before drafting. Only ask the user for information not already covered.

Tracker handling:
- If the project uses GitHub, publish via `gh issue create`.
- If the project uses Linear, Jira, or another tracker with an MCP / CLI integration, use that.
- If no tracker integration is configured, present the PRD content to the user for them to publish manually.

Apply the project's "ready-for-agent" label (or equivalent) so the PRD does not need additional triage. If no such label exists, leave it on the default queue.

---

## Process

### 1. Explore the repo to ground the PRD in reality

If you have not already explored the codebase, do so to understand the current state. Use the project's domain glossary vocabulary throughout the PRD, and respect any ADRs in the area you're touching.

### 2. Sketch the major modules

Sketch out the major modules you will need to build or modify to complete the implementation. Actively look for opportunities to extract deep modules that can be tested in isolation.

A deep module (as opposed to a shallow module) is one which encapsulates a lot of functionality in a simple, testable interface which rarely changes.

Check with the user that these modules match their expectations. Check with the user which modules they want tests written for.

### 3. Write the PRD and publish

Write the PRD using the template below, then publish it to the project issue tracker. Apply the `ready-for-agent` triage label (or equivalent) so it does not need additional triage.

---

## PRD template

```markdown
## Problem Statement

The problem that the user is facing, from the user's perspective.

## Solution

The solution to the problem, from the user's perspective.

## User Stories

A LONG, numbered list of user stories. Each user story should be in the format of:

1. As an <actor>, I want a <feature>, so that <benefit>

Example:

1. As a mobile bank customer, I want to see balance on my accounts, so that I can make better informed decisions about my spending.

This list of user stories should be extremely extensive and cover all aspects of the feature.

## Implementation Decisions

A list of implementation decisions that were made. This can include:

- The modules that will be built / modified
- The interfaces of those modules that will be modified
- Technical clarifications from the developer
- Architectural decisions
- Schema changes
- API contracts
- Specific interactions

Do NOT include specific file paths or code snippets; they may go stale very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts; not a working demo, just the important bits.

## Testing Decisions

A list of testing decisions that were made. Include:

- A description of what makes a good test (only test external behaviour, not implementation details)
- Which modules will be tested
- Prior art for the tests (i.e. similar types of tests in the codebase)

## Out of Scope

A description of the things that are out of scope for this PRD.

## Further Notes

Any further notes about the feature.
```

---

## Cross-references

- `to-issues`: the natural downstream; once the PRD is published, run to-issues to slice it into tracer-bullet work items.
- `triage`: handles state transitions for the PRD-as-issue and any issues to-issues spawns from it.
- `prototype`: if any implementation decision is genuinely uncertain ("does this state model feel right?"), build a prototype first and inline the validated snippet into the PRD's Implementation Decisions section.
- `improve-codebase-architecture`: if the Implementation Decisions reveal architectural friction, route that work through architecture first.
- `humanise-comms`: the PRD will be read by humans (maintainers, AFK agents); apply vault voice discipline to the prose sections.
