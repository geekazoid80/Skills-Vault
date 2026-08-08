---
name: consumer-rollout
description: Use when introducing a new shared service, engine, port, library, or cross-cutting capability that has consumers in the same monorepo or in pinned downstream repos. Drops a "Required hooks" or "Integration checklist" section into every consumer's AGENTS.md / CLAUDE.md / equivalent so future scoping picks up the new dependency. Lists each consumer to update; flags consumers where the hook is non-obvious; surfaces follow-up work for consumers that need code changes (not just doc pointers).
metadata:
  version: 1.0.0
---

# Consumer Rollout

> **Skill marker**: When applying this skill, begin your reply with `[skill: consumer-rollout]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

When a new shared capability lands (an enforcement layer, an engine, a port, a library, a cross-cutting middleware), the new thing is only half the work. The other half is making sure every consumer knows it exists and how to wire it up. Without that, the next person scoping a feature in a consumer module will not know about the new dependency, and will silently bypass it.

**Core principle:** the rollout is not done when the engine ships. It is done when every consumer's AGENTS.md or equivalent points at the new dependency.

## When this fires

- A new enforcement layer that consumers must invoke.
- A new engine that consumers feed input to.
- A new port in a shared package (e.g. `packages/ports/`).
- A new lint rule that consumers must satisfy.
- A new env-var-driven config that consumers must set at boot.
- A new authentication wrapper or session-refresh middleware.
- A new audit hook every domain operation must emit through.
- A new shared validation library, error-taxonomy, or telemetry surface.

## When this does NOT fire

- Pure refactor of an existing shared capability (signature stays the same).
- Internal change to a single module (no consumers).
- A change to a one-off utility used in exactly one place.

## The rule

For every consumer of the new capability:

1. Find the consumer's `AGENTS.md` (or `CLAUDE.md`, `MAINTAINERS.md`, `README.md`, whichever the project uses).
2. Add or update a `## Required hooks` section (or a section with whatever name the project uses).
3. Document: what the new dependency is, why it exists, how to wire it up, what verification confirms it is wired.

The new shared capability's own README also gets a one-liner pointing back at the consumer list.

## Required hooks section template

```markdown
## Required hooks

- **<capability-name>** (lives in `<path-to-shared-package>`)
  - **What:** <one sentence describing what the capability enforces / provides>
  - **Why:** <one sentence describing why every consumer must wire it>
  - **How to wire:** <2-4 lines: import path, factory call, or constructor injection>
  - **Verification:** <command or test that confirms the wiring is live>
  - **ADR:** <link to the ADR that introduced the capability>
```

## How to apply

1. **Enumerate consumers.** Grep the monorepo for the obvious patterns: imports of the old equivalent (if there was one), invocations of the surface this replaces, modules in the same domain. For pinned downstream repos, check the `.<thing>-version` pins to find which projects consume your repo.

2. **For each consumer, add or update the Required hooks section.** Use the template. Be specific: the import path, the constructor parameter, the verification command. Do not write "see ADR-00XX for details" as a substitute for the wiring instruction; the AGENTS.md should be readable without leaving the file.

3. **Flag consumers where the hook is non-obvious.** Examples:
   - The consumer must implement a callback signature.
   - The consumer must register at boot, not lazily.
   - The consumer must call the capability before another middleware (ordering matters).
   - The consumer's test scaffold must be updated to inject a stub.

4. **For consumers that need code changes (not just doc pointers), file follow-up tasks.** A doc pointer alone is not enough when the consumer's existing code is incompatible. The follow-up should land before the capability is enforced (lint or runtime check that fails when the wiring is missing).

5. **Add the consumer index to the new capability's README.** A short bulleted list:
   ```
   ## Consumers

   - `modules/ats/`: wired in v0.4.2 (#180)
   - `modules/entity-group/`: wired in v0.4.2 (#181)
   - `modules/orchestration/`: pending (#182)
   ```

## Worked example: a new audit-logging port

Imagine you are introducing `packages/ports/audit-port` with a new `AuditLogger` interface. Three consumers: `modules/ats/`, `modules/entity-group/`, `modules/orchestration/`.

### Consumer 1: `modules/ats/AGENTS.md`

```markdown
## Required hooks

- **AuditLogger** (lives in `packages/ports/audit-port`)
  - **What:** every state transition on a Requisition or Application must emit an audit event
  - **Why:** SOX-equivalent audit chain; CI lints for missing emits per ADR-0050
  - **How to wire:** inject in the controller via `@Inject('AuditLogger')`; emit via `audit.emit({ kind: 'requisition.transition', ... })`
  - **Verification:** `pnpm test --filter ats audit` covers the standard transitions
  - **ADR:** `docs/adr/0050-audit-port.md`
```

### Consumer 2: `modules/entity-group/AGENTS.md`

```markdown
## Required hooks

- **AuditLogger** (lives in `packages/ports/audit-port`)
  - **What:** every Case open / close / state change must emit an audit event
  - **Why:** as above
  - **How to wire:** inject via `@Inject('AuditLogger')`; emit via `audit.emit({ kind: 'case.transition', ... })`
  - **Verification:** `pnpm test --filter entity-group audit`
  - **ADR:** `docs/adr/0050-audit-port.md`
```

### Consumer 3: `modules/orchestration/AGENTS.md`

```markdown
## Required hooks

- **AuditLogger** (lives in `packages/ports/audit-port`)
  - **What:** every workflow start / complete / fail must emit an audit event
  - **Why:** as above
  - **How to wire:** workflows resolve `AuditLogger` from the runtime context; emit via the `ctx.audit.emit` shorthand
  - **Note:** ordering matters; emit MUST be the last step in the workflow before commit, otherwise the chain misses the failure case
  - **Verification:** `pnpm test --filter orchestration audit-chain`
  - **ADR:** `docs/adr/0050-audit-port.md`
```

The orchestration consumer's hook is non-obvious (ordering matters); the rollout call captured that explicitly so the next scoper sees it.

## When this fires alongside other skills

- After `engineering:architecture` produces the ADR for the new capability.
- Before the implementation sub-agent is briefed (the brief lists the consumer-rollout work as part of the chunk).
- Alongside `plan-time-tooling`, which makes sure both `engineering:architecture` and `engineering:deploy-checklist` fire if applicable.
- The `subagent-delegation` skill's adjacent-pattern scan is the right tool to find consumers you might have missed.

## Red flags

- A new shared capability shipped without a Required hooks section in any consumer.
- A Required hooks section that says "see ADR-00XX" with no wiring detail.
- A non-obvious wiring detail (ordering, callback signature, boot-time vs lazy) not flagged.
- A consumer that needs code changes, not just doc pointers, with no follow-up task filed.
- The new capability's README has no Consumers list.

## Bottom Line

Engine plus pointer per consumer plus follow-up tasks for code changes plus consumers list in the engine's README. The rollout ends when every consumer can be scoped without re-discovering the dependency.
