---
name: author-skill
description: Use when the user wants to write a new self-authored skill from scratch, formalise a recurring instruction into a skill, or convert observed friction (the user repeating themselves across sessions) into a skill. Trigger phrases include "I want a skill for X", "let's turn this into a skill", "this should be a skill", "you keep forgetting Y", "make Z a skill". Scaffolds the interview for trigger surface, rules, examples, and red flags. Drafts the SKILL.md, iterates with the user, writes the file plus the .sources entry, and registers the new skill in the vault. Includes the Claude Search Optimisation discipline (description-must-not-summarise-workflow rule, keyword coverage, descriptive naming, token-efficiency targets), the anti-pattern catalogue (narrative-example, multi-language-dilution, code-in-flowcharts, generic-labels), the progressive-disclosure three-level loading model (metadata in context always, SKILL.md body on trigger, bundled resources as needed), and the bundled-resources structure (scripts / references / examples / assets per skill subdirectory). Folded selectively from obra/superpowers/skills/writing-skills and anthropics/claude-code/plugin-dev/skills/skill-development.
metadata:
  version: 1.3.0
---

# Author Skill

> **Skill marker**: When applying this skill, begin your reply with `[skill: author-skill]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Skills work because the `description:` field tells the agent when to load the body. A new skill needs a sharp trigger description, a tight set of rules, a few worked examples, and red flags. This skill is the structured interview that produces all four.

**Core principle:** the cost of a new skill is one short interview; the saving is "you do not need to repeat this guidance in every session".

## When this fires

- The user explicitly asks: "I want a skill for X", "let's turn this into a skill", "this should be a skill".
- The user has repeated the same guidance across multiple sessions and notices: "you keep forgetting Y, make it a skill".
- After a sub-agent or master observes a recurring pattern that would benefit from being formalised: surface "this looks like a skill candidate" via `AskUserQuestion`.

## When this does NOT fire

- Project-specific rules belong in the project's own `AGENTS.md` or `CLAUDE.md`, NOT a vault skill. The vault is for cross-project skills.
- One-off instructions for a single chunk belong in the conversation, not a skill.
- Always-on conventions that must fire every session belong in `~/.claude/CLAUDE.md`, not a skill (skills can miss; CLAUDE.md cannot).

## The interview

Walk the user through these in order. One question at a time via `AskUserQuestion` where there are choices; freeform conversation where there are not.

### 1. Trigger surface

The most important field. Wrong trigger means the skill never loads when needed, or loads when irrelevant.

- "What phrases or task shapes should make this skill load? Give 3-6 example trigger sentences."
- "Are there obvious near-misses I should explicitly EXCLUDE? (e.g. 'NOT for code', 'NOT for internal docs')"
- "Is this skill always-on (every session) or conditional (specific task shapes)?"
  - Always-on: belongs in CLAUDE.md, not a skill. Push back.
  - Conditional: continue.

Draft the description in this format:

> "Use when [task shapes / trigger phrases]. NOT for [exclusions]. Covers [the rules at a glance]."

Three to six lines. Concrete. Names the trigger phrases.

### 2. Rules

The body's prescriptive content.

- "What are the rules the skill enforces? List 3-10. Bullet form."
- "Which are non-negotiable (iron rules) and which are defaults that can be overridden?"
- "For each rule, what is the worked example?"

If the rules are very prose-heavy and not enumerable, the skill might be procedural (more "how to do X" than "always do Y"). Switch to the procedural pattern below.

### 3. Worked examples

At least one before-and-after for prescriptive skills, or one walked-through procedure for procedural skills.

- "Show me a real or realistic example of the wrong way and the right way (or just the right way)."
- "Is the example sanitisable, or do I need to redact?" (Some examples carry secrets, customer names, etc.)

### 4. Red flags

The "STOP, you are about to violate this" list.

- "What does a violation look like in the moment? Five to ten signals."

Examples (from existing skills): "hedge words like 'should' or 'probably'"; "an em dash anywhere in human-bound prose"; "a new endpoint with `allow.everyone`".

### 5. Bottom line

One paragraph that summarises the whole skill in language a tired reader can absorb. Often the same as the description, expanded.

## Match the form to the failure

Before picking a structure, classify the baseline failure you are correcting. The form that bulletproofs one failure type measurably backfires on another.

| The failure | Use this form | Not this |
|---|---|---|
| Knows the rule, skips it under pressure | Prohibition, plus a rationalisation table and red flags | Soft guidance ("prefer...", "consider...") |
| Complies, but the output has the wrong shape (bloated, buried verdict, restated spec) | A positive recipe or contract: what the output IS, its parts, in order | A prohibition list ("don't restate", "never narrate") |
| Omits a required element from something they already produce | A structural REQUIRED field or slot in the template they fill in | Prose reminders near the template |
| Behaviour should depend on a condition | A conditional keyed to an observable predicate ("if the brief exists, reference it") | An unconditional rule plus exemption clauses |

The counterintuitive row is the second. Under a competing incentive, agents negotiate with "don't X". In head-to-head wording tests the prohibition arm produced clearly more of the unwanted content than the recipe arm, and trended worse than even the no-guidance control. If the problem is shape, say what the right shape IS.

Two supporting rules:

- **No nuance clauses.** Appending a single nuance clause to a winning recipe degraded it from consistent to noisy. Resist the urge to qualify.
- **Exemption clauses do not scope.** "This limit doesn't apply to code blocks" still suppresses code blocks. Restructure so the rule cannot reach the exempt part, rather than carving out an exception.

## Structural patterns

Pick one based on the rule shape.

### Prescriptive (rules to enforce)

```
# <Title>

## Overview
<2-4 sentences setting the scene + core principle>

## The Iron Rule (or core rule)
<the non-negotiable rule, possibly in a code block>

## <Section per rule, or per category of rule>
<rules with worked examples>

## Red Flags
<list>

## Bottom Line
<one paragraph>
```

Models: `verification-before-completion` (deleted, folded into `completion-gate`), `humanise-comms`, `utc-timestamps`, `secrets-hygiene`.

### Procedural (steps to follow)

```
# <Title>

## Overview
<2-4 sentences + core principle>

## When to Use This Skill
<list of trigger conditions>

## How to Apply
### Step 1: ...
### Step 2: ...
### Step 3: ...
<each step with worked detail>

## Tips for Effective Use
<list>

## When the Procedure Does Not Apply
<list>
```

Models: `find-skills`, `consumer-rollout`, `merged-skills-registry`.

## Drafting and iteration

After the interview:

1. Draft the SKILL.md inline (in the chat, not yet to file).
2. Show the description first; iterate until the user is happy with the trigger.
3. Show the body; iterate.
4. When the user says ship: `Write` the file to `<vault>/<skill-name>/SKILL.md`.
5. `Write` the `.sources/<skill-name>` pointer file. Format depends on origin:
   - **Self-authored skill:** single line `local CLAUDE.md`.
   - **Folded from one upstream:** single line with the full URL to the upstream skill directory, plus a parenthetical pointer to `merged-skills-registry` for fold notes and licence. Example: `https://github.com/<owner>/<repo>/tree/main/skills/<name> (see merged-skills-registry for fold notes and licence)`.
   - **Folded from multiple upstreams (consolidated fold):** one line per upstream, same URL-plus-parenthetical format. Each upstream gets its own line.
6. If the skill folds in any third-party content, add a row to `merged-skills-registry` describing the fold, the licence, and any voice / cross-reference customisation applied.
7. **Verify before declaring done.** Four checks; all four must pass:
   - `<vault>/<skill-name>/SKILL.md` exists with frontmatter, skill marker, body.
   - **The frontmatter PARSES as YAML, not just "has the right fields".** Run `python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]).read().split("---",2)[1])' <vault>/<skill-name>/SKILL.md` (exit 0 = pass). An unquoted `description:` that contains a `: ` (colon then space) or an embedded `"` silently aborts the loader with `mapping values are not allowed here`, while a dash byte-scan and a "four fields present" eyeball both pass, so this is the check that actually catches it. On failure, re-emit the line as a double-quoted scalar (the house convention): `description: "` + value with every `\` and `"` escaped + `"`. This matters most for subagent-drafted skills, whose self-report ("four fields, parses") is not reliable.
   - `<vault>/.sources/<skill-name>` exists with the correct origin line(s).
   - For folds: a row exists in `merged-skills-registry/SKILL.md`. For self-authored: no registry row needed.

   Skip any of these and a future audit pass (per the Chunk 6 B-0 reconciliation pattern) has to clean it up retroactively across dozens of skills. The write is cheap at fold time and expensive at reconciliation time; always pay at fold time.

## Naming conventions

- Lowercase, hyphen-separated. (`utc-timestamps`, not `UTC_Timestamps` or `utcTimestamps`.)
- Verb-or-noun phrase, not a sentence. (`humanise-comms`, not `write-like-a-human`.)
- Avoid the word "skill" in the name (`find-skills` is an exception because it finds OTHER skills).
- Six to twenty characters typically. Longer if needed.

## House style (every new skill)

- British / Pacific English. No US spellings.
- No em dashes. Use commas, semicolons, parentheses, full stops.
- YAML frontmatter: `name:` and `description:`, plus the vault's `metadata.version` block (semver, per `docs-versioning`). Nothing else.
- Markdown body with `#` for the title, `##` for sections.
- Tables and bullet lists where they help. No corporate padding.
- 50-250 lines for most skills (some carry-the-vocabulary skills like `greedy-with-constraints` and `subagent-delegation` exceed this; that is by intent).
- By word count, the equivalent target is 1,500 to 2,000 words for the body, under 3,000 in most cases, and 5,000 as a hard ceiling. Reference files carry no such limit and routinely run 2,000 to 5,000+ words each.

When the body pushes past those numbers, the fix is to move a long section into `references/` rather than to trim the rules. A skill of 1,800 words plus `patterns.md` (2,500) and `advanced.md` (3,700) reads far better than a single 8,000-word file, because only the first is paid for on every trigger.

## Progressive disclosure (Claude Code skills load in three levels)

Folded selectively from anthropics/claude-code/plugin-dev/skill-development. Skills use a three-level loading system the harness manages automatically:

1. **Metadata (name + description):** always in context for every loaded skill (~100 words per skill). This is what Claude reads to decide whether to load the body.
2. **SKILL.md body:** loaded when the skill triggers (1,500 to 2,000 words ideal, under 3,000 preferred, 5,000 hard maximum; aim much lower for frequently-loaded skills per the token-efficiency rule above).
3. **Bundled resources (scripts, references, assets):** loaded as needed, not eagerly. Scripts can be EXECUTED without ever entering the context window.

Design skills to push detail down the levels:

- Always-needed rule: in the body.
- Sometimes-needed reference (large API docs, schema definitions, long worked examples): in `references/<name>.md`, with the body pointing at it (and grep search patterns if the file is over 10k words).
- Pure tooling that runs and returns a result: in `scripts/<name>.sh` or `scripts/<name>.py`, never read into context.

## Bundled resources structure

When a skill ships more than just SKILL.md, the bundled-resources convention is:

```
skill-name/
├── SKILL.md            # Required; the trigger surface and the rules
├── scripts/            # Executable code the SKILL runs (Python, Bash, Node)
│   └── <name>.{sh,py,js}
├── references/         # Documentation loaded as needed (not eagerly)
│   └── <topic>.md
├── examples/           # Complete, runnable samples the USER copies and adapts
│   └── <name>.{sh,json,md}
└── assets/             # Files used IN the output (templates, icons, fonts)
    └── <name>.{png,pptx,html}
```

When to use each:

- **`scripts/`:** code that the same skill rewrites repeatedly OR needs deterministic execution. Example: a script that rotates a PDF, validates a hooks.json schema, or sets up a baseline test environment. The skill executes these; they never need to enter context.
- **`references/`:** documentation Claude should consult while working but does NOT need eagerly. Example: a database schema reference, a long API spec, a brand guide that the brand-voice skill defers to. Keeps SKILL.md lean. If the reference is over 10k words, include grep patterns in SKILL.md so Claude can navigate it.
- **`examples/`:** complete, runnable samples a reader copies and adapts. Example: three working hook scripts, a filled-in config file, a template. The distinction from `scripts/` is who runs it: the skill runs a script, whereas an example is a starting point handed to the user.
- **`assets/`:** files used IN the output Claude produces. Example: a slide template, a brand logo, a boilerplate React project, a font file. NOT loaded into context; copied or referenced by output.

Three usual shapes: **Minimal** (`SKILL.md` alone), **Standard** (`SKILL.md` + `references/` + `examples/`), **Complete** (adds `scripts/`). Most vault skills are Minimal, and that is the right default.

Information should live in EITHER SKILL.md OR a references file, not both. Duplication rots quickly.

For non-Claude-Code skills (vault skills not bundled into a plugin), the same structure works: drop `references/`, `scripts/`, `examples/` and `assets/` next to `SKILL.md` in the skill's directory.

## Description discipline (Claude Search Optimisation)

Folded selectively from obra/superpowers/skills/writing-skills. The `description:` field is the trigger surface; Claude reads it to decide whether to load the skill. Three rules govern good descriptions:

### Rule 1: Description = WHEN to use, NOT WHAT the skill does

The most important rule. Do NOT summarise the skill's process or workflow in the description. Triggering conditions only.

**Why:** when a description summarises a workflow, Claude often follows the description instead of reading the full body. A description that says "code review between tasks" causes Claude to do ONE review even though the body's flowchart shows TWO. A description that says "use TDD; write test first, watch it fail, write minimal code, refactor" causes Claude to skip the body's red-green-refactor verification rules entirely. The body becomes documentation Claude shortcuts past.

```yaml
# Bad: summarises workflow; Claude may follow this instead of reading the skill
description: Use when executing plans; dispatches subagent per task with code review between tasks

# Bad: too much process detail
description: Use for TDD; write test first, watch it fail, write minimal code, refactor

# Good: just triggering conditions, no workflow summary
description: Use when executing implementation plans with independent tasks in the current session

# Good: triggering conditions and trigger phrases
description: Use when implementing any feature or bugfix, before writing implementation code
```

### Rule 2: Keyword coverage

The description should carry the words a tired reader would search for when the skill applies. Cover:

- **Error messages** the skill resolves: "Hook timed out", "ENOTEMPTY", "race condition".
- **Symptoms** that signal the skill fits: "flaky", "hanging", "zombie", "pollution".
- **Synonyms** for the same idea: "timeout / hang / freeze", "cleanup / teardown / afterEach".
- **Tools, commands, library names, file types** that are part of the trigger surface.

Symptoms beat language-specific wording. "Race condition" beats "setTimeout"; "flaky" beats "test passes inconsistently". Keep technology-agnostic unless the skill IS technology-specific.

### Rule 3: Token efficiency for the description body

Skills that load every session (always-on, frequently-loaded) cost tokens in EVERY conversation. Target word counts:

- Always-on or getting-started skills: under 150 words in the description body.
- Frequently-loaded skills: under 200 words.
- Other skills: under 500 words.

Move heavy reference to separate files. Cross-reference instead of repeating. Compress examples ruthlessly (one excellent example beats five mediocre ones).

## Anti-patterns (avoid in every new skill)

Folded from obra/superpowers/skills/writing-skills. These are skill failures; if you catch yourself writing one, rewrite.

- **Narrative example.** "In session 2025-10-03, we found that the empty `projectDir` caused..." Bad because it is too specific and not reusable. The skill is a reference, not a war story; turn the lesson into a generalised rule.
- **Multi-language dilution.** Showing `example-js.js`, `example-py.py`, `example-go.go`. Bad because each example becomes mediocre and the maintenance burden multiplies. One excellent example beats N mediocre ones; the reader can port.
- **Code in flowcharts.** `step1 [label="import fs"]; step2 [label="read file"];`. Bad because the reader can't copy-paste and the diagram is harder to read than a numbered list. Flowcharts are for non-obvious decision points; code goes in markdown blocks.
- **Generic labels.** `helper1`, `step3`, `pattern4`, `option2`. Bad because labels carry no semantic meaning. Use names that describe what the thing IS or DOES (`extract-token`, `verify-baseline`, `parallel-dispatch`).

## Worked example: turning friction into a skill

Imagine the user has said three times in three sessions: "remember to put the customer's contract number at the top of every email to vendors".

Author-skill flow:

1. Trigger surface interview: "When does this fire?" → "Every email to a vendor". Trigger phrases: "draft an email to <vendor>", "reply to <vendor>", "write to <vendor>". Exclusions: not for internal mail.
2. Rules: "Top of every vendor email carries `Ref: KAC-<contract-number>` so the vendor can route it; if the contract number is unknown, ASK before sending; confidential vendor mails get the contract number AND a confidentiality footer per template X."
3. Examples: a real (sanitised) before-and-after.
4. Red flags: "About to send a vendor email with no Ref line; contract number invented (must come from project config); confidential content without the footer."
5. Bottom line: "Vendor emails open with `Ref: KAC-<n>`. Ask if you do not know the number. Never invent."

Draft the description: "Use when drafting or replying to a vendor email. NOT for internal mail. Covers the `Ref: KAC-<contract-number>` opening line, the ask-when-unknown rule, and the confidential-mail footer per template X."

Write to `<vault>/vendor-email-ref/SKILL.md` plus `.sources/vendor-email-ref` = `local CLAUDE.md`.

## Red flags

- Description that says "this skill helps with X" without naming the trigger phrases.
- Description that summarises the workflow ("dispatches subagent per task with code review between tasks"); shortens Claude's behaviour from the body's full discipline to whatever the description says.
- Description longer than ~6 lines (probably trying to fit two skills into one).
- Body with no worked example.
- Body with no red flags section.
- Skill written from a single recent annoyance (the friction may not be recurring; one-off should not become a skill).
- Skill that overlaps an existing local skill without merging or registering the overlap.
- Always-on or frequently-loaded skill with a description body over 200 words (token cost adds up across every session).
- Generic labels in the body (`helper1`, `step3`, `pattern4`); labels should carry semantic meaning.
- A prohibition list used against a shape problem ("don't restate the spec", "never narrate"). Prohibitions work on rule-skipping, not on output shape; write the recipe instead.
- An exemption clause carving a case out of a rule ("this does not apply to code blocks"). It will not scope; restructure so the rule cannot reach the exempt part.
- Code embedded inside a flowchart (the reader can't copy-paste; use markdown code blocks).
- Multi-language examples (one excellent example in the most natural language beats N mediocre ones).
- Skill ships without a `.sources/<name>` pointer file. Always needed: `local CLAUDE.md` for self-authored skills, upstream URL(s) for folds. Missing pointers are the gap that the Chunk 6 B-0 reconciliation pass had to retroactively close for 34 skills; do not let the gap reopen.
- Folded skill ships with the `.sources/` pointer but no `merged-skills-registry` row (or vice versa). Both must land together in the same PR as the fold; partial fold bookkeeping rots quickly and breaks the audit cadence.

## Bottom Line

Interview for trigger, rules, examples, red flags. Draft inline, iterate, then write. House style is non-negotiable. Every new skill gets a `.sources/<name>` pointer file at fold time: `local CLAUDE.md` if self-authored, upstream URL(s) if folded. Folded upstreams also get a `merged-skills-registry` row. SKILL.md + pointer + (for folds) registry row all land in the same PR; verify all three before declaring done.
