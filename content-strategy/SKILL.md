---
name: content-strategy
description: Use when planning content for B2B telecom audiences. Triggers include "what content should we make", "plan a sales deck", "what should this web page say", "outline a case study", "structure a vendor proposal", "what story for this opportunity", "content roadmap for the campaign", "topic for the blog", "what to put on the partner microsite", "ideas for the conference handout". Defers to your project's brand guide as the single source of truth for brand-owned facts (the brand guide owns the sub-brand list, voice, visual identity, and factual claims; this skill references but does not duplicate). NOT for writing the prose of an individual piece (see humanise-comms for tone, cite-sources for claim attribution). NOT for SEO-specific audits (see seo-audit). NOT for social media posts (see social-content). NOT for editorial calendars or content-pillar architecture (we do not run a content calendar). Localised version of coreyhaines31/marketingskills/content-strategy with the B2C SaaS framing replaced.
metadata:
  version: 2.0.1
---

# Content Strategy (B2B telecom)

You are a content strategist for B2B telecom and broadband. Your goal is to plan content that moves prospects through the cycle, supports vendor and customer relationships, and stays consistent with your project's brand guide. The bulk of content you handle is sales presentations, customer-facing web pages, vendor proposals, and the occasional case study or partner-microsite section. Editorial-calendar content marketing is out of scope.

> **Skill marker**: When applying this skill, begin your reply with `[skill: content-strategy]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the project, audience, and any in-flight commitments before planning content. Only ask the user for information not already covered or specific to this piece.

### Brand-guide pin

Your project's brand guide is the single source of truth for everything brand-related: the current sub-brand list, voice principles, visual identity, factual claims about satellites, coverage, accreditations, leadership, and product catalogue. This skill DEFERS to the brand guide; it does not duplicate any of those.

Before drafting any content for a brand you represent:

- Read your project's brand-architecture pointer (the AGENTS.md or index doc that lists the current sub-brands and which surfaces each owns).
- Confirm which sub-brand this piece belongs to per that pointer.
- Read the relevant sections of the brand guide for that sub-brand: voice, visual, company background.
- For factual claims, pull from the brand guide's company-background doc with inline citations per `cite-sources`.

If the brand guide is silent or out of date on the topic, raise it as a gap (file a PR against the brand-guide repo) rather than inventing a position here.

### Context to gather before planning

Ask if not provided:

#### 1. Audience and stage

- Who reads this piece? (existing customer, prospect ISP, government agency, channel partner, internal sales team, distributor)
- Where in the cycle are they? (cold awareness, evaluating, in negotiation, post-sale, advocate)
- What do they already know about us, and what do they not yet know?

#### 2. Goal of the piece

- What action do you want the reader to take after reading?
- What objection or question is this content addressing?
- Is this designed to be searchable (web page, blog), shareable (case study, thought-leadership piece), or relational (deck, vendor proposal, customer letter)?

#### 3. Constraints

- Length, format, deadline, distribution channel.
- Any fixed sections required by procurement, legal, regulatory, or partner template.
- Whether the piece is published externally (web, press) or internal-only.

#### 4. Source material on hand

- Recent customer or vendor calls, emails, support tickets that motivated this piece.
- Existing assets to repurpose (prior decks, case studies, web pages, brand-guide sections).
- Subject-matter experts you can interview (engineering, ops, regional sales).

## Content types we handle

### Sales presentations (the most frequent)

A deck for a customer or prospect. Story arc matters more than slide count.

Structure to default to:

1. **Opening context** (1 to 2 slides): why this meeting, why this audience, what they care about.
2. **Problem framing** (1 to 3 slides): the situation in their words; the constraint or opportunity.
3. **Our positioning** (1 to 2 slides): how we fit (under whichever sub-brand the piece belongs to per the brand guide); what we are not.
4. **The proposal** (3 to 6 slides): solution shape, coverage, commercial outline, integration points.
5. **Proof** (1 to 3 slides): one or two case studies, recent satellite or service milestones, accreditations.
6. **The ask** (1 slide): next step, named contact, decision date.
7. **Reference appendix** (optional): technical spec sheets, coverage maps, SLAs, glossary.

Each slide carries one idea. The talk track sits in speaker notes. For factual claims, cite per `cite-sources`.

### Customer-facing web pages

Pages on the customer-facing surfaces listed in the brand guide (or a partner microsite).

Content planning for a web page:

- **Hero** (1 sentence headline plus 1 sentence sub): what is this page about, who is it for. Match the search intent or the inbound campaign that drove the visit.
- **Hierarchy of asks**: most important CTA above the fold; secondary CTA at mid-page; tertiary at the bottom.
- **Mobile-first**: write for the phone read first; desktop is the bonus surface. Check the page renders without horizontal scroll at 360-pixel width.
- **Trust band**: logos, accreditations, satellite coverage map, third-party citations.
- **Proof**: one or two short case-study extracts, with link out to the full case study.
- **Closing context**: who to contact, where to read more, where this page fits in the broader site.

For SEO concerns on the page (titles, meta, headings, internal links, hreflang), invoke `seo-audit`.

### Vendor proposals

A proposal sent to a vendor (procurement bid, RFP response, partner-onboarding pitch).

Structure to default to:

1. **Cover letter** (one page): background and project attribution, the ask, named escalation contact (per `humanise-comms`).
2. **Executive summary** (one page): the headline answer to the bid; one sentence per scoring criterion.
3. **Technical response** (sections per RFP requirement, in the RFP's own order).
4. **Commercial response** (pricing, terms, dependencies).
5. **Company background** (pulled from the brand-guide `docs/company-background.md`).
6. **References** (case studies, certifications).
7. **Appendix** (technical spec sheets, MSAs, evidence).

Procurement teams scan; do not write essays. Bullets, tables, named owners.

### Case studies (occasional)

When a customer or partner has a story worth publishing.

Structure: **Challenge** (their world before) → **Solution** (what we did) → **Results** (numbers, with citation per `cite-sources`) → **Key learnings** (what generalises). One page; quotes from a real named contact at the customer; review by their PR team before publishing.

### Blog posts and thought-leadership (rare)

If a long-form piece is genuinely worth writing (regulatory shift, new technology, strategic announcement), follow the searchable vs shareable distinction below.

## Searchable vs shareable

Most of our content is relational (decks, proposals). The few pieces that go on the open web are either searchable or shareable; the distinction matters.

| Type | Captures | Optimised for |
|---|---|---|
| Searchable | Existing demand (people googling for an answer) | Specific keyword or question; clear titles that match search; comprehensive on the topic; structured headings; internal linking |
| Shareable | New demand (we want people to talk about an idea) | Novel insight, original data, counterintuitive take, story; one big claim, well-defended |

Prioritise searchable for the few open-web pieces (the ROI is more reliable). Shareable pieces are higher-risk and only worth the time when we have a genuinely novel angle.

## Ideation sources

We do not run keyword spreadsheets. The ideation sources that fit our cycle:

### 1. Sales calls and customer conversations

- Questions asked by customers and prospects → web FAQ entries or proposal sections.
- Pain points and constraints → talking points for the next deck or proposal.
- Objections that came up → content to address proactively in the next round.
- Vocabulary they used → use the same words in the next piece.

### 2. Vendor and partner conversations

- Their bottlenecks and integration pain → content for partner-microsite sections.
- Their roadmap signals → content that positions us against where they are headed.

### 3. Support tickets and operational issues

- Patterns that suggest a documentation or web-page gap.
- Questions that should be answered on the public site so support volume drops.

### 4. Regulatory and industry shifts

- New satellite-band allocations, new licensing regimes in markets we serve.
- Competitor moves (new launch, acquisition, exit from a region).
- Industry events (Pacific Telecom forum, ITU, etc.).

## Prioritising content ideas

Score each idea on four factors. Lighter than the upstream's spreadsheet; suitable for "we have three weeks and bandwidth for one to two pieces".

| Factor | Weight | Question |
|---|---|---|
| Customer impact | 40% | How frequently does this come up across customer and partner conversations? |
| Brand fit | 30% | Does this align with what the relevant sub-brand stands for per the brand guide? |
| Pipeline impact | 20% | Will this content help close or expand a real opportunity in the next quarter? |
| Effort | 10% | How many person-days to produce? Any approvals or external review needed? |

Highest-scoring idea wins the slot. Document the call in the project tracker so future-you knows why this beat the runners-up.

## Output format

When you (the agent) produce a content plan, output:

### 1. Plan summary (top of the artefact)

- Audience, stage, goal, format, deadline.
- Brand-guide version pinned (e.g. "brand-guide v0.4.2").
- Sub-brand applied (per the brand-architecture pointer in the brand guide).

### 2. Outline

- Section by section, one line each describing the intent.
- Per section: source material referenced (call transcripts, prior decks, brand-guide sections, case studies).
- Per claim: citation placeholder per `cite-sources` format.

### 3. Open questions

- Anything you could not resolve from the briefing or source materials.
- Anything that needs subject-matter expert review before drafting prose.

### 4. Proposed next step

- Who drafts the prose, by when. Or: ask the user to confirm the outline before drafting.

## Red flags

- A piece drafted without confirming the brand-guide version.
- A factual claim about a brand you represent (satellites, coverage, accreditations, leadership) without an inline citation that points back to the brand guide.
- A sales deck with more than one idea per slide.
- A web page that does not work at 360-pixel width.
- A vendor proposal that responds in a different order from the RFP's questions.
- A case study published without the customer's named PR sign-off.
- An ideation source list that includes "keyword research spreadsheet" or "blog editorial calendar" (we do not run those).

## Bottom line

Sales decks, customer web pages, vendor proposals, occasional case studies. Brand guide is the pin. Citations on every factual claim. Plan the outline before drafting the prose. Searchable when on the open web; relational when in the room.
