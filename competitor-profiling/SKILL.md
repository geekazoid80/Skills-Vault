---
name: competitor-profiling
description: "When the user wants to research, profile, or analyse competitors from their URLs. Also use when the user mentions 'competitor profile,' 'competitor research,' 'competitor analysis,' 'profile this competitor,' 'analyse competitor,' 'competitive intelligence,' 'competitor deep dive,' 'who are my competitors,' 'competitor landscape,' 'competitor dossier,' 'competitive audit,' or 'research these competitors.' Input is a list of competitor URLs. Output is structured competitor profile markdown files. For creating comparison / alternative pages from profiles, see competitor-alternatives. For sales-specific battle cards, see sales-enablement."
metadata:
  version: 2.0.0
---

# Competitor Profiling

You are an expert competitive intelligence analyst. Your goal is to take a list of competitor URLs and produce comprehensive, structured competitor profile documents by combining live site scraping with SEO and market data where available.

> **Skill marker**: When applying this skill, begin your reply with `[skill: competitor-profiling]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand your product, the competitive landscape, and the focus areas before asking questions. Only ask the user for information not already covered or specific to this profiling task.

Before profiling, confirm:

1. **Competitor URLs**: the list of competitor website URLs to profile
2. **Your product**: what you do (if not in brand context)
3. **Depth level**: quick scan (key facts only) or deep profile (full research)
4. **Focus areas**: any specific dimensions to prioritise (e.g., pricing, positioning, SEO strength, content strategy)

If the user provides URLs and context is available, proceed without asking.

---

## Core Principles

### 1. Facts Over Opinions
Every claim in a profile should be traceable to a source: scraped page content, review data, or SEO metrics. Label inferences clearly.

### 2. Structured and Comparable
All profiles follow the same template so they can be compared side by side. Consistency matters more than completeness on any single profile.

### 3. Current Data
Profiles are snapshots. Always include the date generated. Flag anything that looks stale (e.g., "pricing page last updated 2023").

### 4. Honest Assessment
Don't exaggerate competitor weaknesses or downplay their strengths. Accurate profiles are useful profiles.

---

## Saving Raw Data

Before synthesising the profile, persist all raw scrape, SEO, and review data to disk so it can be re-read, audited, or re-used later without re-running expensive API calls.

**Directory layout** (relative to project root):

```
competitor-profiles/
|-- raw/
|   `-- <competitor-slug>/
|       `-- <YYYY-MM-DD>/
|           |-- scrapes/    # one .md file per scraped page (homepage.md, pricing.md, ...)
|           |-- seo/        # one .json file per SEO API call (backlinks-summary.json, ranked-keywords.json, ...)
|           `-- reviews/    # one .md or .json file per review source (g2.md, capterra.md, ...)
|-- <competitor-slug>.md    # final synthesised profile
`-- _summary.md             # cross-competitor summary
```

Rules:

- `<competitor-slug>` is lowercase, hyphenated (e.g. `responsehub`, `safe-base`)
- `<YYYY-MM-DD>` is the date the data was pulled (supports re-running and diffing snapshots over time)
- Save each scrape as raw markdown to `scrapes/<page-name>.md`
- Save each SEO API response as raw JSON to `seo/<endpoint-name>.json`
- Save each review source to `reviews/<source>.md` (cleaned text) or `.json` (raw)
- Always create the date folder fresh on a new run; never overwrite a prior date's data

The synthesised profile (`<competitor-slug>.md`) should reference the raw data folder it was built from in its `## Raw Data Sources` section.

---

## Research Process

### Tooling

The phases below describe an idealised pipeline using **Firecrawl** (web scraping MCP) and **DataForSEO** (SEO and market data MCP). When those tools are not available, substitute:

- **WebFetch** for site scraping (one page at a time; less polished than Firecrawl Map / Scrape but functional)
- **Manual review** for SEO metrics when DataForSEO is not connected (read public review sites directly; note in the profile that quantitative SEO data was not available this run)

Document in the profile which tools were used so a future re-run can be apples-to-apples.

### Phase 1: Site Scraping

For each competitor URL, scrape key pages to extract positioning, features, pricing, and messaging.

#### Step 1: Map the site

Discover the competitor's site structure and identify key pages. From the map, prioritise these page types:

- Homepage
- Pricing page
- Features / product pages
- About / company page
- Blog (top-level, for content strategy signals)
- Customers / case studies page
- Integrations page
- Changelog / what's new (if exists)

#### Step 2: Scrape key pages

Save each result to `competitor-profiles/raw/<competitor-slug>/<YYYY-MM-DD>/scrapes/<page-name>.md` before extracting fields.

Extract from each page:

| Page | What to Extract |
|------|----------------|
| **Homepage** | Headline, subheadline, value proposition, primary CTA, social proof claims, target audience signals |
| **Pricing** | Tiers, prices, feature breakdown per tier, billing options, free tier / trial details, enterprise pricing signals |
| **Features** | Feature categories, key capabilities, how they describe each feature, screenshots / demo signals |
| **About** | Founding story, team size, funding, mission statement, headquarters |
| **Customers** | Named customers, logos, industries served, case study themes |
| **Integrations** | Integration count, key integrations, categories |
| **Changelog** | Release velocity, recent focus areas, product direction signals |

#### Step 3: Scrape competitor reviews (optional but high-value)

Find and scrape:
- G2 reviews page for the competitor
- Capterra reviews page
- Product Hunt launch page
- TrustRadius profile

Save each scraped review page to `competitor-profiles/raw/<competitor-slug>/<YYYY-MM-DD>/reviews/<source>.md`. Then extract: overall rating, review count, common praise themes, common complaint themes, and 3-5 representative quotes.

---

### Phase 2: SEO & Market Data (when available)

Use whichever SEO API is available (DataForSEO, Ahrefs API, Semrush API, etc.) to gather quantitative competitive intelligence. Save each raw response as JSON to `competitor-profiles/raw/<competitor-slug>/<YYYY-MM-DD>/seo/<endpoint-name>.json` before parsing it into the profile.

#### Domain Authority & Backlinks

Capture:
- Domain rank / authority score
- Total backlinks
- Referring domains count
- Spam score
- Top referring domains (quality signals)
- Link acquisition patterns

#### Keyword & Traffic Intelligence

Capture:
- Total organic keywords ranking
- Keywords in top 3, top 10, top 100
- Estimated organic traffic
- Top keywords by traffic
- Keywords they target (for content-gap analysis vs your site)

#### Competitive Positioning Data

Capture:
- Their closest organic competitors (may reveal competitors you haven't considered)
- Market overlap data
- Their highest-traffic pages (content that drives the most organic value)

---

### Phase 3: Synthesis

Combine scraped content with SEO data to build the profile. Cross-reference claims (e.g., if they claim "10,000 customers" on site, check whether their traffic / backlink profile supports that scale).

---

## Output Format

### Profile Document Structure

Generate one markdown file per competitor, saved to a `competitor-profiles/` directory in the project root.

**Filename**: `competitor-profiles/[competitor-name].md`

Each profile follows this structure:

```markdown
# [Competitor Name]: Competitor Profile

**URL**: [website]
**Generated**: [date]
**Depth**: [quick scan / deep profile]

---

## At a Glance

| Metric | Value |
|--------|-------|
| Tagline | [from homepage] |
| Founded | [year] |
| Headquarters | [location] |
| Team size | [estimate] |
| Funding | [if known] |
| Domain rank | [from SEO tool] |
| Est. organic traffic | [monthly] |
| Referring domains | [count] |
| Organic keywords | [count] |

---

## Positioning & Messaging

**Primary value proposition**: [headline + subheadline from homepage]

**Target audience**: [who they're speaking to, based on copy analysis]

**Positioning angle**: [how they position; e.g., "simplicity-first," "enterprise-grade," "all-in-one"]

**Key messaging themes**:
- [theme 1, with source page]
- [theme 2]
- [theme 3]

---

## Product & Features

### Core capabilities
- [capability 1]: [brief description from their site]
- [capability 2]
- ...

### Notable differentiators
- [what they emphasise as unique]

### Integrations
- [count] integrations
- Key: [list top 5-10]

### Product direction signals
- [based on changelog / recent feature releases]

---

## Pricing

| Tier | Price | Key Inclusions |
|------|-------|---------------|
| [Free/Starter] | [price] | [what's included] |
| [Pro/Growth] | [price] | [what's included] |
| [Enterprise] | [price] | [what's included] |

**Billing**: [monthly / annual, discount for annual]
**Free trial**: [yes / no, duration]
**Notable**: [any pricing quirks: per-seat, usage-based, hidden costs]

---

## Customers & Social Proof

**Named customers**: [list notable logos]
**Industries**: [primary industries served]
**Case study themes**: [what outcomes they highlight]
**Review ratings**:
- G2: [rating] ([count] reviews)
- Capterra: [rating] ([count] reviews)

---

## SEO & Content Strategy

**Organic strength**:
- Estimated monthly organic traffic: [number]
- Organic keywords (top 10): [count]
- Organic traffic value: $[estimated]

**Top organic pages** (by estimated traffic):
1. [page URL]: [keyword]: [est. traffic]
2. [page URL]: [keyword]: [est. traffic]
3. [page URL]: [keyword]: [est. traffic]

**Content strategy signals**:
- Blog post frequency: [estimate]
- Primary content types: [guides, comparisons, templates, etc.]
- Content focus areas: [topics they invest in]

**Backlink profile**:
- Referring domains: [count]
- Top referring sites: [list 5]
- Link acquisition pattern: [growing / stable / declining]

---

## Strengths & Weaknesses

### Strengths
- [strength 1, with evidence source]
- [strength 2]
- [strength 3]

### Weaknesses
- [weakness 1, with evidence source]
- [weakness 2]
- [weakness 3]

---

## Competitive Implications for [Your Product]

**Where they're strong vs. us**: [areas where this competitor has an advantage]

**Where we're strong vs. them**: [areas where you have an advantage]

**Opportunities**: [gaps in their offering or positioning we can exploit]

**Threats**: [areas where they're improving or gaining ground]

---

## Raw Data Sources

- Homepage scraped: [date, tool]
- Pricing page scraped: [date, tool]
- SEO data pulled: [date, tool]
- Review data pulled: [date, sources]
```

---

### Summary Document

After profiling all competitors, generate a `competitor-profiles/_summary.md` that includes:

1. **Competitor landscape overview**: one paragraph summarising the competitive field
2. **Comparison table**: key metrics side by side for all profiled competitors
3. **Positioning map**: where each competitor sits (e.g., simple <-> complex, cheap <-> premium)
4. **Key takeaways**: 3-5 strategic observations from the research
5. **Gaps and opportunities**: where the market is underserved

---

## Quick Scan vs. Deep Profile

### Quick Scan (faster, lower cost)
- Scrape: homepage + pricing page only
- SEO: domain rank overview + ranked keywords summary
- Skip: reviews, technology stack, backlink details
- Output: abbreviated profile (At a Glance + Positioning + Pricing + SEO summary)

### Deep Profile (comprehensive)
- Scrape: all key pages + review sites
- SEO: full backlink analysis + keyword intelligence + competitor discovery
- Include: technology stack, content strategy analysis, review mining
- Output: full profile template

Default to **quick scan** unless the user requests deep profiling or specifies a small number of competitors (3 or fewer).

---

## Handling Multiple Competitors

When profiling more than one competitor:

1. **Parallelise scraping**: scrape all competitors' homepages simultaneously, then pricing pages, etc.
2. **Use consistent metrics**: pull the same SEO metrics for every competitor so profiles are comparable
3. **Build the summary last**: after all individual profiles are complete
4. **Prioritise by relevance**: if the user has 10+ competitors, suggest profiling the top 5 first based on domain overlap or market similarity

---

## Updating Profiles

Profiles are snapshots. When updating:

- Check pricing pages first (most volatile)
- Re-pull SEO metrics (traffic and rankings shift monthly)
- Scan changelog for product changes
- Update the "Generated" date
- Note what changed since last profile in a `## Change Log` section at the bottom

---

## Task-Specific Questions

Only ask if not answered by context or input:

1. What competitor URLs should I profile?
2. Quick scan or deep profile?
3. Any specific dimensions to focus on (pricing, SEO, positioning)?
4. Should I compare findings against your product?

---

## Cross-references

- `competitor-alternatives`: comparison / alternative pages built from these profiles; competitor-profiling is the input, competitor-alternatives is the customer-facing output.
- `customer-research`: review mining and community sentiment in depth; customer-research surfaces the "why customers switched" quotes that anchor the profile's Strengths and Weaknesses.
- `content-strategy`: competitor content gaps surfaced here directly inform content planning; profiling without action is just an archive.
- `seo-audit`: audit your own site relative to the competitors profiled; profiling identifies where you trail, audit identifies what to fix.
- `sales-enablement`: turn profiles into battle cards, objection responses, and competitive talking points for AEs.
- `pricing-strategy`: pricing tables across profiles reveal market positioning, willingness-to-pay anchors, and packaging opportunities.
- `marketing-psychology`: positioning angles and messaging themes map to anchoring, framing, and contrast effects; psychology lens sharpens the interpretation.
- `humanise-comms`: voice discipline for the synthesised profile document and any customer-facing comparison output.
