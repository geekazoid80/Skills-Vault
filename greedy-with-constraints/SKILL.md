---
name: greedy-with-constraints
description: "Use when designing or extending a code surface (validation rules, RBAC checks, typed errors, schema invariants, public API shapes, write surfaces). Default to the tightest reasonable surface in the engine; loosening later is a one-line tweak, tightening later requires a migration. Covers the process caveat: when scope, permissions, or write surfaces are AMBIGUOUS, ASK via AskUserQuestion rather than silently locking down or silently opening up. The heuristic is for code design, not licence to assume the worst about an unscoped write surface."
metadata:
  version: 1.0.0
---

# Greedy with Constraints, Not with Rights

> **Skill marker**: When applying this skill, begin your reply with `[skill: greedy-with-constraints]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Two halves, easy to confuse:

- **In CODE:** when in doubt, add MORE validation, narrower RBAC checks, more typed errors, more invariants. The engine's surface is cheap to loosen, expensive to tighten.
- **In PROCESS:** when scope, permissions, or write surfaces are AMBIGUOUS, ASK rather than silently locking down or silently opening up. Surface the trade-off, let the human choose.

**Core principle:** be greedy with constraints in the engine, not with rights to interpret ambiguity.

## Why the asymmetry

Tightening a constraint after it ships needs a migration: existing data must satisfy the new rule, existing callers must adapt. Loosening a constraint is a one-line removal; nothing on the floor breaks because everything in flight was already inside the tighter envelope.

Therefore: when in doubt about how strict to be, **err strict**. The cost of "too tight" is one PR. The cost of "too loose" is a migration plus a behaviour change for every consumer.

## In CODE: defaults

| Surface | Tighten by default | Worked example |
|---|---|---|
| Input validation | Reject anything not explicitly allowed | New string field: enforce length min and max, character class, format. Don't accept `string` and "we'll worry about it later". |
| RBAC | Default deny; opt-in by role | New endpoint: deny all roles, then add `requires(role.X)` for each role you actually want. Never `allow.everyone` "for now". |
| Typed errors | Distinct error type per failure mode | A `validate()` returns `ValidationError | NotFoundError | ConflictError`, not `Error`. Callers can branch; future code can add a fourth without renaming. |
| Schema invariants | NOT NULL, CHECK, UNIQUE wherever the model says they hold | `email` is unique and not null at the DB layer, not just at the application layer. The engine enforces what the design promises. |
| Public API surface | Smallest export set that meets the requirement | Don't re-export internal helpers "in case someone needs them". Add when a real consumer arrives. |
| Write endpoints | Allowed-list of fields the caller may set | A PATCH endpoint accepts an explicit set of fields, not "any subset of the model". |

The pattern: **default-deny, opt-in additions**. Documented decisions, narrow surfaces.

## In PROCESS: when to ASK instead of pick

The "be greedy with constraints" rule is for code design. It is NOT licence to lock down a write surface that has not been explicitly scoped, nor to open one up because "the user probably wants flexibility".

When the scope is ambiguous, the right move is to surface the ambiguity to the human via `AskUserQuestion`, present the trade-offs, and let them choose. Examples of process-side ambiguity:

- A new endpoint's RBAC list was not specified. Ask: "Roles that need access? Recommend default-deny plus opt-in per role."
- A new model field's validation envelope is unclear. Ask: "Length bounds, character class, format constraints? I'll default to strict if you don't have a target."
- A migration drops a column. Ask: "Is this column truly unused, or just unused in the current code? I can grep for stragglers in pinned downstream repos before pushing."
- A write surface for a multi-tenant feature was not scoped. Ask: "Cross-tenant write allowed? Recommend tenant-scoped with explicit cross-tenant override."

The pattern: when CODE is ambiguous, default tight. When PROCESS is ambiguous, ASK.

## Worked example: a new POST endpoint

Brief: "Add a POST /api/v1/sites endpoint for creating a customer site."

Wrong (greedy with rights):
- Accept any JSON body.
- Allow any authenticated caller.
- Return the created entity verbatim.
- "Add validation later when we know the shape."

Right (greedy with constraints + ask on ambiguity):
1. Define the input schema: required fields, types, length bounds. If unclear, **ask** for the field list and bounds.
2. RBAC: default deny. **Ask**: "Which roles can create a site? Recommend `site.admin` and `tenant.owner` for v1."
3. Validation rejects unknown fields (no silent passthrough).
4. Output schema explicit; do not return the raw entity.
5. Audit log every successful and rejected attempt.
6. Idempotency key in the request, idempotency table in the DB.

Each tightening above is a one-line loosening if it turns out to be wrong. Each loosening above (adding a new role, adding a new accepted field) is one line of code. Each tightening if started loose (rejecting fields callers were already sending, scoping back permissions callers were already using) is a migration plus a deprecation cycle.

## Worked example: ambiguous write surface

Brief: "Let admins update the customer's billing address."

Process-side ambiguity to flag before writing code:

- Which `admin` role? `tenant.admin`, `site.admin`, `support.admin`?
- "Update" the whole address object, or PATCH-style field-level?
- Audit-only, or notify the customer on change?
- Cross-tenant admins (rare in this app) allowed?

`AskUserQuestion` with these as options. Do not silently pick the most permissive ("any admin can replace the whole address"). Do not silently pick the most restrictive ("only tenant.admin, PATCH-only, customer-notified, no cross-tenant"). Make the user choose.

## Red Flags

- A new endpoint with RBAC `allow.everyone` "until we know the roles".
- A new schema with no CHECK constraints because "the application validates it".
- A `try { ... } catch (e) { ... }` that swallows distinct error types into a generic message.
- A migration that adds a NOT NULL column with no default and no backfill plan.
- A PATCH endpoint that accepts the whole model object.
- A "we'll narrow this later" comment with no follow-up issue.
- A silent pick between two reasonable interpretations of an ambiguous brief.

## Architectural vocabulary

Use these terms exactly. Consistent language is the point; do not substitute "component", "service", "API", or "boundary".

| Term | Meaning |
|---|---|
| **Module** | Anything with an interface and an implementation. Scale-agnostic: a function, class, package, or tier-spanning slice. Avoid "unit", "component", "service". |
| **Interface** | Everything a caller must know to use the module correctly: types, invariants, ordering constraints, error modes, required configuration, performance characteristics. NOT just the type signature. Avoid "API", "signature" (too narrow). |
| **Implementation** | What is inside the module. Distinct from **adapter**: a thing can be a small adapter with a large implementation (a Postgres repo) or a large adapter with a small implementation (an in-memory fake). Reach for "adapter" when the seam is the topic; "implementation" otherwise. |
| **Depth** | Leverage at the interface; the amount of behaviour a caller (or test) can exercise per unit of interface they have to learn. **Deep** means high leverage. **Shallow** means the interface is nearly as complex as the implementation. |
| **Seam** (from Michael Feathers) | A place where you can alter behaviour without editing in that place. The *location* at which a module's interface lives. Choosing where to put the seam is its own design decision, distinct from what goes behind it. Avoid "boundary" (overloaded with DDD's bounded context). |
| **Adapter** | A concrete thing that satisfies an interface at a seam. Describes role (what slot it fills), not substance (what is inside). |
| **Leverage** | What callers get from depth. More capability per unit of interface they have to learn. One implementation pays back across N call sites and M tests. |
| **Locality** | What maintainers get from depth. Change, bugs, knowledge, and verification concentrate at one place rather than spreading across callers. Fix once, fixed everywhere. |

### Principles

- **Depth is a property of the interface, not the implementation.** A deep module can be internally composed of small, mockable, swappable parts; they just are not part of the interface. A module can have **internal seams** (private to its implementation, used by its own tests) as well as the **external seam** at its interface.
- **The deletion test.** Imagine deleting the module. If complexity vanishes, it was a pass-through (delete it; callers can call the collaborator directly). If complexity reappears across N callers, the module was earning its keep (keep or deepen).
- **The interface is the test surface.** Callers and tests cross the same seam. If you want to test *past* the interface, the module is probably the wrong shape.
- **One adapter means a hypothetical seam. Two adapters means a real one.** Do not introduce a port or seam unless something actually varies across it (typically production plus test).

### Rejected framings

- **Depth as ratio of implementation-lines to interface-lines** (Ousterhout's original): rewards padding the implementation. Use depth-as-leverage instead.
- **"Interface" as the TypeScript `interface` keyword or a class's public methods**: too narrow; interface here includes every fact a caller must know.
- **"Boundary"**: overloaded with DDD's bounded context. Say **seam** or **interface**.

### Relationships

- A **Module** has exactly one **Interface** (the surface it presents to callers and tests).
- **Depth** is a property of a **Module**, measured against its **Interface**.
- A **Seam** is where a **Module**'s **Interface** lives.
- An **Adapter** sits at a **Seam** and satisfies the **Interface**.
- **Depth** produces **Leverage** for callers and **Locality** for maintainers.

## Design for testability

Good interfaces make TDD natural and enforce greedy constraints by limiting what callers can do.

**Accept dependencies; do not create them.** Pass collaborators in via parameters or constructor injection rather than instantiating them inside:

```typescript
// Testable; the caller controls the dependency
function processOrder(order, paymentGateway) { ... }

// Hard to test; the dependency is hidden inside
function processOrder(order) {
  const gateway = new StripeGateway();
  ...
}
```

**Return results; do not produce side effects (where you can).** A function that computes is easier to reason about and test than a function that mutates and computes.

**Small surface area.** Fewer methods means fewer tests. Fewer parameters means simpler test setup.

## Dependency categories for deepening

When deepening a cluster of shallow modules, classify the dependencies. The category determines how the deepened module is tested across its seam.

| Category | What | Test strategy | Recommendation shape |
|---|---|---|---|
| **In-process** | Pure computation, in-memory state, no I/O | Always deepenable; test through the new interface directly. No adapter needed. | "Merge the modules; test the new interface directly." |
| **Local-substitutable** | Dependencies with local test stand-ins (PGLite for Postgres, in-memory FS) | Deepenable if the stand-in exists. Tests use the stand-in in the test suite. Seam is internal; no port at the external interface. | "Use the local substitute in tests; keep the seam internal." |
| **Remote but owned** (Ports & Adapters) | Your own services across a network boundary (microservices, internal APIs) | Define a port at the seam. Deep module owns the logic; transport is injected as an adapter. Tests use an in-memory adapter. Production uses HTTP/gRPC/queue. | "Define a port at the seam; implement an HTTP adapter for production and an in-memory adapter for testing, so the logic sits in one deep module even though it is deployed across a network." |
| **True external** (mock) | Third-party services (Stripe, Twilio) you do not control | Deepened module takes the external dependency as an injected port. Tests provide a mock adapter. | "Inject the third-party port; mock at the seam in tests." |

### Seam discipline

- **Internal seams vs external seams.** A deep module can have internal seams (private to its implementation, used by its own tests) as well as the external seam at its interface. Do not expose internal seams through the interface just because tests use them.
- **Replace, do not layer (testing strategy).** Old unit tests on shallow modules become waste once tests at the deepened module's interface exist; delete them. Write new tests at the deepened module's interface. Tests assert on observable outcomes through the interface, not internal state. Tests should survive internal refactors; they describe behaviour, not implementation.

For the workflow that finds deepening opportunities and grills design candidates, see `improve-codebase-architecture`. For the writing-side discipline that goes with these design choices, see `tdd`. For the parallel-sub-agent pattern that explores alternative interfaces, see `subagent-delegation`.

## Bottom Line

Code surfaces start tight, loosen on real demand. Modules deepen, not widen. The vocabulary above is the canonical home for architectural terms across the vault; do not substitute. Ambiguous scopes get an `AskUserQuestion`, not a silent pick. The heuristic protects against the asymmetric cost of getting strictness wrong; it does not authorise locking down what the user did not ask to lock down.
