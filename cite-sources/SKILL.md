---
name: cite-sources
description: "Use when writing factual content that requires source attribution. Triggers include claim-heavy docs, research summaries, brand-truth pages, regulatory pages, compliance summaries, due-diligence reports, market analyses, and product specs that quote vendor docs. Every factual claim carries an inline citation in the form [src: where, accessed-date] for web sources, [src: filename, page-or-slide] for documents, or [src: person, date] for first-party interviews. Accessed dates use ISO-8601 (YYYY-MM-DD). Calls out unsourced claims and offers to add the citation or downgrade the claim to clearly hedged language."
metadata:
  version: 1.0.0
---

# Cite Sources

> **Skill marker**: When applying this skill, begin your reply with `[skill: cite-sources]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Every factual claim in a document the reader will treat as authoritative carries an inline citation. The citation tells the reader where to verify, and tells future-you which source to refresh when the claim might be stale.

**Core principle:** if the reader could check it, cite it. If you cannot cite it, hedge it.

## When this fires

- Claim-heavy docs (whitepapers, analyst briefings, due-diligence write-ups).
- Brand-truth pages (company history, satellite inventory, leadership bios).
- Regulatory and compliance summaries.
- Market analyses (pricing, competitor positioning, segment size).
- Product specs that quote vendor documentation.
- First-party research summaries (interview notes, survey results).

## When this does NOT fire

- The writer's own opinion or analysis ("I think we should...").
- Well-established common knowledge ("water boils at 100 degrees Celsius at sea level").
- Internal memos that explicitly mark themselves as opinion.

## Citation formats

Three patterns. Use whichever fits the source.

### Web source

`[src: northwind.example/about, accessed 2026-05-09]`

Notes:
- URL or domain plus path.
- `accessed` date in ISO-8601 (YYYY-MM-DD), UTC.
- For deep paths, the path is enough; do not paste the full URL.

### Document source

`[src: Corporate Template_Final.pptx, slide 35]`

`[src: Q3-2025-financial-report.pdf, p. 12]`

Notes:
- Filename plus location (slide, page, sheet, section).
- For versioned documents, include the version: `[src: brand-guide.md@v0.3.1, § Voice principles]`.

### First-party interview

`[src: Sara Tan (Integration Lead), 2026-04-22]`

Notes:
- Person plus role, plus date of conversation.
- For multiple sessions, include the session identifier: `[src: Sara Tan (Integration Lead), kickoff 2026-04-22]`.

### Hedged or absent source

`[src: TBD]`

Treat any `[src: TBD]` as a blocker, not a footnote. The doc is not ready to ship until each TBD is resolved or the claim is downgraded to hedged language.

## Hedged language for unsourced claims

If no source exists and the claim cannot be removed:

| Hedge | When |
|---|---|
| "We believe..." | Internal opinion, not a verified fact |
| "Based on internal estimates..." | Modelled or projected, not measured |
| "Marketing has stated..." | Internal source, not externally verified |
| "Anecdotal feedback suggests..." | A few customers said it, no survey |
| "Roughly..." or "in the order of..." | Order-of-magnitude estimate |

The hedge is not an excuse to skip the work. It is the honest label until the source arrives.

## Confidence markers (complement to citations)

For documents that summarise research or background, pair each section with a confidence marker:

```
## Voice principles

Confidence: medium

[src: Corporate Template_Final.pptx, slide 8]
```

Levels:

- **High:** primary source, recent, directly relevant.
- **Medium:** secondary source, or primary but older than a year, or partial coverage.
- **Low:** inference, single anecdote, or marketing-quoted claim with no underlying source.

The confidence marker decays over time. A "high" claim from 2024 may be "medium" in 2026 if the underlying source has not been re-verified.

## Citation-as-you-go

Citing as you draft is cheaper than citing after.

| Approach | Cost | Risk |
|---|---|---|
| Citation-as-you-go | Small per claim, distributes the work | Low: source is in mind when you write |
| Citation-after | One big sweep at the end | High: you forget where each claim came from, sources go stale, gaps surface late |

When the source is not at hand, write `[src: TBD]` and keep moving. Treat the TBD list as a pre-publish checklist, not a footnote list.

## Worked example: a claim-heavy paragraph

### Without citations

> Northwind Satellite's primary market is the North Atlantic islands, where it serves around 40 ISPs and reaches over 600 community sites. Its satellite Northwind-1 is a high-throughput satellite (HTS) launched in 2019 with 56 spot beams.

### With citations

> Northwind Satellite's primary market is the North Atlantic islands [src: northwind.example/about, accessed 2026-05-09], where it serves around 40 ISPs and reaches over 600 community sites [src: Northwind_Corporate_Presentation_26092022.pdf, slide 12]. Its satellite Northwind-1 is a high-throughput satellite (HTS) [src: northwind.example/satellites/northwind-1, accessed 2026-05-09] launched in 2019 with 56 spot beams [src: Q4-2019-press-release.pdf, p. 1].

The cited version is longer, but the reader can verify each claim and you (or anyone else) can refresh the data point when the source updates.

## Red flags

- A factual claim with no citation and no hedge.
- A `[src: TBD]` shipped to a customer or external reader.
- A citation that points at the wrong section ("[src: brand-guide.md]" without the section anchor).
- A confidence marker missing from a section that carries claims.
- A high-confidence marker on a claim sourced from a single anecdote.
- An accessed date in the future, or in a non-ISO format (e.g. "5/9/26").
- A citation pointing at a URL the reader cannot reach (private Drive link in a public doc).

## Bottom Line

Cite as you draft. ISO-8601 accessed dates. Three formats (web, document, interview). TBD is a blocker, not a footnote. Hedge what you cannot cite. Confidence markers decay.
