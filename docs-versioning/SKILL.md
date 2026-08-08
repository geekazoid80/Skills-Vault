---
name: docs-versioning
description: Use when editing a versioned documentation set or shared dependency repo, anything that downstream consumers pin to a tag (brand guides, design systems, API contracts, regulatory references, ML model cards, prompt libraries). Enforces VERSION bump plus CHANGELOG entry per change category (patch for clarifications, minor for additive changes, major for breaking renames or removals). Calls out missing VERSION bumps or CHANGELOG entries before the PR is opened. Suggests SemVer bump category based on the diff.
metadata:
  version: 1.0.0
---

# Docs Versioning

> **Skill marker**: When applying this skill, begin your reply with `[skill: docs-versioning]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

A documentation set is a contract when downstream consumers pin a tag of it. Editing that contract without a version bump silently changes what every pinned consumer is reading from.

**Core principle:** every edit to a pinned-doc surface lands in the same PR as a VERSION bump and a CHANGELOG entry. CI lints this; if the project has no lint, propose adding one.

## When this fires

- Brand guides and style references that downstream products pin to a tag.
- Design systems (token files, component specs).
- API contracts (OpenAPI, AsyncAPI, Protobuf, GraphQL SDL).
- Regulatory references (jurisdiction tables, retention rules).
- ML model cards and dataset cards.
- Prompt libraries shared across products.
- Any docs repo where another repo carries a `.<thing>-version` pin file.

## When this does NOT fire

- Internal-only docs nobody pins to.
- Working notes, drafts, scratch markdown.
- READMEs that are not the source of contractual truth.

## Bump categories (SemVer for docs)

| Category | When | Examples |
|---|---|---|
| **Patch** | Clarification, typo fix, link fix, source-citation refresh, formatting | "Reword sentence for clarity"; "Fix broken link to vendor doc"; "Refresh accessed date on a citation" |
| **Minor** | Additive content, new section, new asset, new product page, new optional field | "Add new sub-brand profile"; "Add new color token"; "Add an optional field to the API contract"; "New jurisdiction added" |
| **Major** | Rename of a stable identifier, removal of a section, change to a customer-facing claim, breaking contract change | "Rename a token (consumers must update)"; "Remove a deprecated logo variant"; "Change the satellite count claim"; "Remove a field from the API contract" |

When in doubt between minor and major, ask: "Will any pinned consumer break or render differently if they bump the pin without code changes?" If yes, major.

## The same-PR rule

The VERSION bump and the CHANGELOG entry MUST land in the same PR as the change. Not a follow-up. Not "I'll add it later".

Why: if the change ships without the bump, consumers cannot tell anything moved. If the bump ships without the change, the version number lies. The two are atomic.

## File conventions

### `VERSION` file

Single line, SemVer:

```
0.4.2
```

Pre-release identifiers (`0.4.2-rc.1`) for staging tags. Build metadata (`0.4.2+brand.update`) is allowed but rarely useful for docs.

### `CHANGELOG.md`

Keep-a-changelog style. One section per release, newest at the top:

```
# Changelog

## 0.4.2 - 2026-05-09

### Patch

- Fixed broken link in §Voice principles (#173)
- Refreshed accessed date on the satellite-count citation (#174)

## 0.4.1 - 2026-05-02

### Minor

- Added new color token: `--color-accent-pacific` (#170)

### Patch

- Reworded the brand-architecture summary for clarity (#171)
```

Notes:
- One sub-heading per category (Patch / Minor / Major).
- One bullet per change with the PR or issue number.
- ISO-8601 release date.
- Most recent release at the top.

## How to detect the right category from a diff

When reviewing a diff, walk through this sequence:

1. **Did anything get removed or renamed?** If yes, major.
2. **Did the diff change a customer-facing factual claim?** If yes, major (the pin gates downstream truth).
3. **Did the diff add new content (sections, tokens, assets, fields, sub-brands)?** If yes, minor.
4. **Otherwise (clarifications, formatting, citation refreshes, link fixes)?** Patch.

Worked examples:

| Diff | Category | Why |
|---|---|---|
| Fix typo "satellite" → "satellites" in §History | Patch | Clarification |
| Add a third logo variant under `assets/logos/horizontal-light.svg` | Minor | Additive |
| Rename token `--color-primary` to `--color-brand-primary` | Major | Breaking; consumers using the old name will not render |
| Update "operates 1 satellite" to "operates 2 satellites" | Major | Customer-facing factual change |
| Add new section "Sub-brand: PointCast" | Minor | Additive |
| Refresh the accessed date on three citations | Patch | Citation hygiene |
| Remove the deprecated logo variant `assets/logos/old-stack.png` | Major | Removal |

## CI lint

The project should have a CI step that fails when:

- The diff touches a pinned-doc path AND the `VERSION` file did not bump.
- The diff touches a pinned-doc path AND `CHANGELOG.md` did not gain an entry for the new version.
- The new version in `VERSION` does not appear at the top of `CHANGELOG.md`.
- The bump category in `CHANGELOG.md` does not match what the diff shape implies (best-effort heuristic; warns rather than blocks).

If the project does not yet have such a lint, propose adding one. A minimal version is a 30-line shell script in `scripts/lint-version-bump.sh`.

## Downstream-consumer effects

| Bump | Pin behaviour | Consumer action |
|---|---|---|
| Patch | Auto-pull is safe by SemVer contract | None |
| Minor | Auto-pull is safe by SemVer contract | None unless they want the new content |
| Major | Pin must be reviewed before bumping | Review every consumer before tagging the major release |

When you ship a major, list the affected consumers in the CHANGELOG entry so the rollout is visible:

```
## 1.0.0 - 2026-06-01

### Major

- Rename `--color-primary` to `--color-brand-primary` (#200)
  - Affected consumers: the marketing site, the docs site, the design-export pipeline
```

## Red flags

- A diff that touches a pinned-doc path without a VERSION bump.
- A VERSION bump without a CHANGELOG entry.
- A CHANGELOG entry without a release date or with a non-ISO date.
- A "minor" bump that actually renames a stable identifier.
- A "patch" bump that actually adds new content.
- "I'll add the changelog entry in a follow-up PR".
- A major release with no list of affected consumers.

## Bottom Line

Pinned docs are a contract. VERSION + CHANGELOG land in the same PR as the change. Major means renames, removals, or customer-facing factual changes. Minor means additive. Patch means clarifications. CI lints this; if it does not, propose the lint.
