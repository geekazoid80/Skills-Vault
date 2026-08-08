---
name: prototype
description: When the user wants to build a throwaway prototype to flesh out a design before committing to it. Also use when the user mentions "prototype this," "let me play with it," "sanity-check this data model / state machine," "try a few designs," "mock this up," "explore design options," "throwaway code for X," "spike on Y," or "build something disposable to test the idea." Use this whenever someone wants to answer a design question by building something disposable rather than reasoning on paper. For diagnosing a bug with a deterministic loop, see systematic-debugging. For converting validated prototype findings into work items, see to-issues.
metadata:
  version: 1.0.0
---

# Prototype

A prototype is **throwaway code that answers a question**. The question decides the shape.

> **Skill marker**: When applying this skill, begin your reply with `[skill: prototype]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the project's task runner, framework conventions, and any existing prototype patterns before deciding where to put throwaway code. Only ask the user for information not already covered.

---

## Pick a branch

Identify which question is being answered, from the user's prompt, the surrounding code, or by asking if the user is around:

- **"Does this logic / state model feel right?"** Build a tiny interactive terminal app that pushes the state machine through cases that are hard to reason about on paper. (Logic branch; see below.)
- **"What should this look like?"** Generate several radically different visual variations on a single surface, switchable between via a project-appropriate variant toggle (URL parameter, env var, CLI flag, route segment, or framework-idiomatic mechanism; pick whatever the project's existing routing / config convention supports). (UI branch; see below.)

The two branches produce very different artifacts; getting this wrong wastes the whole prototype. If the question is genuinely ambiguous and the user isn't reachable, default to whichever branch better matches the surrounding code (a backend module to logic; a page or component to UI) and state the assumption at the top of the prototype.

---

## Rules that apply to both branches

1. **Throwaway from day one, and clearly marked as such.** Locate the prototype code close to where it will actually be used (next to the module or page it's prototyping for) so context is obvious; name it so a casual reader can see it's a prototype, not production. For throwaway UI variants, obey whatever routing / config convention the project already uses; don't invent a new top-level structure.
2. **One command to run.** Whatever the project's existing task runner supports (`pnpm <name>`, `python <path>`, `bun <path>`, `cargo run --example <name>`, `make prototype`, etc.). The user must be able to start it without thinking.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is *checking*, not something it should depend on. If the question explicitly involves a database, hit a scratch DB or a local file with a clear "PROTOTYPE, wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond what makes the prototype *runnable*, no abstractions. The point is to learn something fast and then delete it.
5. **Surface the state.** After every action (logic branch) or on every variant switch (UI branch), print or render the full relevant state so the user can see what changed.
6. **Delete or absorb when done.** When the prototype has answered its question, either delete it or fold the validated decision into the real code; don't leave it rotting in the repo.

---

## Logic branch

For "does this state model / data model / business-logic flow feel right?" questions, build a tiny interactive terminal app (or test-runner harness) that:

- Initialises the state machine or data model in memory with sensible starting state.
- Exposes commands or actions that drive the machine through transitions.
- Prints the full state after each action so the user can spot wrong-shaped transitions.
- Hits the hard-to-reason-about cases (concurrent transitions, race conditions, edge-case inputs, recovery from errors) explicitly, ideally with one action per case.

A terminal REPL works well; so does a single-file script with a sequence of hard-coded actions. Pick whatever the user can run + read + tweak fastest.

---

## UI branch

For "what should this look like?" questions, generate several *radically different* visual approaches on a single surface, switchable between via the project's idiomatic mechanism:

- Each variant should be a distinct design direction, not a small tweak. If variant B is "the same as A but blue", the prototype has failed.
- Keep variants self-contained; a global change should not affect them all.
- The switch mechanism should be obvious to the user (a floating bar, a query parameter they can change in the URL, a CLI flag, a route segment). Match the project's conventions.
- Render full representative state in each variant (real-ish data, not Lorem Ipsum) so the user can judge how the design behaves under realistic load.

Three to five radically different variants is a useful range. Fewer and the design space isn't explored; more and the user can't compare.

---

## When done

The *answer* is the only thing worth keeping from a prototype. Capture it somewhere durable (commit message, ADR, issue, or a `NOTES.md` next to the prototype) along with the question it was answering. If the user is around, that capture is a quick conversation; if not, leave the placeholder so they (or you, on the next pass) can fill in the verdict before deleting the prototype.

If the validated decision is precise enough to encode (a state machine, a reducer, a schema, a type shape), inline that snippet in the capture; downstream skills (`to-prd`, `to-issues`) can lift the snippet into the PRD's Implementation Decisions or the slice body's "What to build" section.

---

## Cross-references

- `systematic-debugging`: a prototype harness can be the Phase 1 fast deterministic pass/fail signal; useful when the loop needs to be built before there's any real test seam.
- `improve-codebase-architecture`: prototypes answer design questions *before* architectural commitment; if the prototype reveals that the codebase has no good place for the validated decision, route the next step through architecture.
- `to-prd`: validated prototype findings (especially state machines, reducers, schemas) belong in the PRD's Implementation Decisions section.
- `to-issues`: if the prototype validates a design that needs implementation across multiple layers, to-issues slices the work into tracer-bullet issues.
- `greedy-with-constraints`: prototype scope should be the smallest thing that answers the question; resist the temptation to grow the prototype into a production-shaped surface.
- `tdd`: prototypes skip tests by design; if the validated decision graduates into production code, tdd handles the transition.
