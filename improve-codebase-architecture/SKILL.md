---
name: improve-codebase-architecture
description: Use when auditing an existing codebase for architectural friction and proposing deepening opportunities (refactors that turn shallow modules into deep ones). Triggers include "improve the architecture", "find refactoring opportunities", "what should we deepen", "this code feels coupled", "make this more testable", "review the architecture of X", "audit this module", "find shallow modules", "consolidate tightly-coupled modules", "make this more AI-navigable". Defers to greedy-with-constraints for the architectural vocabulary (module / interface / seam / adapter / depth / leverage / locality, plus the deletion test, plus dependency categories for deepening) and to subagent-delegation for the parallel-sub-agent design pattern when alternative interfaces need exploring. NOT for design-time greenfield work (use greedy-with-constraints directly). NOT for finding bugs (see engineering:debug). NOT for the writing-side TDD discipline (see tdd). Localised orchestrator that folds mattpocock/skills/engineering/improve-codebase-architecture's workflow; the supporting reference files (LANGUAGE, DEEPENING, INTERFACE-DESIGN) are folded into greedy-with-constraints and subagent-delegation as the canonical homes.
metadata:
  version: 1.1.0
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities**: refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability, with locality and leverage as the load-bearing properties.

This skill is the WORKFLOW. The vocabulary, dependency categories, and parallel-sub-agent design pattern live in their canonical homes; this skill orchestrates them.

> **Skill marker**: When applying this skill, begin your reply with `[skill: improve-codebase-architecture]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Vocabulary lives elsewhere

The architectural vocabulary used throughout this workflow (module / interface / implementation / depth / seam / adapter / leverage / locality, plus the deletion test, plus dependency categories for deepening) is the canonical content of `greedy-with-constraints`. Read that skill's "Architectural vocabulary" and "Dependency categories for deepening" sections before using this workflow; this skill assumes you have.

The parallel-sub-agent pattern for exploring alternative interfaces ("Design It Twice") lives in `subagent-delegation` § Parallel-Design Sub-Agents. Use it from step 3 below when the user wants to explore alternatives.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the codebase shape, domain vocabulary, ADRs already in place, and any in-flight refactor commitments before proposing changes. Only ask the user for information not already covered or specific to this exploration.

Before exploring, understand:

1. **Codebase scope**
   - Single service / module, multi-service repo, or cross-repo system?
   - Language(s) and major frameworks in play?
   - Existing test coverage and CI surface for the area in question?

2. **Refactor driver**
   - Performance, testability, deployment, on-boarding, or change-friction?
   - Concrete pain point with example(s) the user can cite?
   - Constraints from product / SLA on behaviour-preserving changes?

3. **Decision artefacts**
   - ADRs covering the affected area?
   - Recent design docs, RFCs, or PR-discussion threads?
   - Other agents / skills already touching this area?

---

## The Workflow

### 1. Explore

Read the project's domain glossary (e.g. `CONTEXT.md` or equivalent) and any `docs/adr/` entries in the area you are touching first. ADRs are decisions the workflow should not re-litigate.

**Scope before you scan.** Deepening a module only pays off by making *future* changes to it easier, so weight the scan toward code that actually keeps changing. Decide where to look before looking:

- If the user named a direction (a module, a subsystem, a pain point), take it and skip the inference.
- Otherwise walk back a good stretch of `git log --oneline` for hot spots: the files and areas that keep coming up. Let those paths pull attention first.
- If the changes are scattered with no clear hot spot, widen the net rather than forcing a hot spot that is not there.

Then use the Agent tool with `subagent_type=Explore` to walk the codebase. Do not follow rigid heuristics. Explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** (interface nearly as complex as the implementation)?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they are called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates (do NOT propose interfaces yet)

Present a numbered list of deepening opportunities. For each candidate:

- **Files:** which files / modules are involved.
- **Problem:** why the current architecture is causing friction.
- **Solution:** plain-English description of what would change.
- **Benefits:** explained in terms of **locality** and **leverage**, and in how tests would improve.
- **Recommendation strength:** exactly one of `Strong`, `Worth exploring`, `Speculative`.
- **Dependency category:** one of the four in `greedy-with-constraints` (`in-process`, `local-substitutable`, `ports & adapters`, `mock`).

Keep the benefits bullets inside the glossary. "Locality: bugs concentrate in one module" and "leverage: one interface, N call sites" earn their place; "easier to maintain" and "cleaner code" do not, because they are not terms in the vocabulary and they carry no information.

Close the list with a **Top recommendation**: which one you would tackle first, and why. An undifferentiated numbered list pushes the whole triage job onto the reader.

Use the project's domain vocabulary (CONTEXT.md if present) for the domain ("the Order intake module", not "the FooBarHandler"). Use `greedy-with-constraints` vocabulary for the architecture (module / interface / seam / etc.).

**ADR conflicts:** if a candidate contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting the ADR. Mark it clearly:

> "This candidate contradicts ADR-0007, but worth reopening because [load-bearing reason]."

Do not list every theoretical refactor an ADR forbids. Respect prior decisions until the cost of the friction outgrows them.

After the list, ASK the user via `AskUserQuestion`: "Which of these would you like to explore?" Do not pick one yourself.

### 3. Grilling loop on the chosen candidate

Once the user picks, drop into a grilling conversation (per the `grill-me` skill's interview model: one question at a time, recommend per question, walk down the dependency tree).

Walk the design tree:

- Constraints on the deepened module.
- Dependencies (classify per `greedy-with-constraints` § Dependency categories for deepening).
- The shape of the deepened module.
- What sits behind the seam vs. what is exposed at it.
- Which existing tests survive; which become waste once the deepened-interface tests exist.

#### Side effects happen inline as decisions crystallise

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Add the term to `CONTEXT.md` (or the project's domain-glossary file). Create the file lazily if it does not exist. Same discipline as the project's grill-with-docs equivalent.
- **Sharpening a fuzzy term during the conversation?** Update `CONTEXT.md` right there.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR, framed as: "Want me to record this as an ADR so future architecture reviews do not re-suggest it?" Only offer when the reason would actually be needed by a future explorer to avoid re-suggesting the same thing. Skip ephemeral reasons ("not worth it right now") and self-evident ones.
- **User wants to explore alternative interfaces for the deepened module?** Switch to the `subagent-delegation` § Parallel-Design Sub-Agents pattern (3+ sub-agents with differentiated constraints, then present, compare, recommend, ask). Return here with the chosen interface to continue the grilling.

### 4. Commit point

When the design tree is resolved (or the user calls it), output a short summary:

- Decisions reached.
- Deferrals (with the rationale for deferring).
- Open questions that could not be resolved without more information.
- The next concrete step (write a spec? open a tracking issue? brief an implementation sub-agent?).

Then ASK the user how to proceed, per the standard "do not default-then-act" rule.

## When this fires alongside other skills

- **`greedy-with-constraints`:** canonical home for the architectural vocabulary and dependency categories. Read first.
- **`subagent-delegation`:** the parallel-sub-agent design pattern for exploring alternative interfaces. Use from step 3 when the user wants alternatives.
- **`grill-me`:** the interview model used in step 3's grilling loop. The two skills' interview disciplines are aligned.
- **`tdd`:** the writing-side discipline that follows the workflow's commit point. Once the deepened module is designed, TDD it into existence.
- **`testing-anti-patterns`:** the test-review discipline. New tests at the deepened-module's interface should not violate the five iron laws.
- **`forward-compatible-schemas`:** if the deepening involves a schema change, the additive-only rule applies.

## Red Flags

- Workflow used for greenfield design (wrong skill; use `greedy-with-constraints` directly).
- Step 2 produces interface proposals; the user picks based on interfaces rather than on which problem to attack.
- Step 3 settled without classifying dependencies (per `greedy-with-constraints` § Dependency categories).
- ADR conflict surfaced as a footnote in the implementation rather than as a real "reopen the ADR" choice.
- Domain term invented during step 3 not added to CONTEXT.md.
- Parallel-design sub-agents skipped on a high-stakes interface; the master picked a single shape silently.

## Bottom Line

Find architectural friction; surface deepening candidates; grill the chosen one; design alternatives in parallel when alternatives exist; commit to a shape with the user's confirmation. Vocabulary and patterns live in their canonical homes; this skill orchestrates them.
