---
name: social-content
description: Use when creating, scheduling, or analysing short-post social media content for LinkedIn, Twitter/X, Facebook, and similar text-first platforms. Triggers include "LinkedIn post", "Twitter thread", "X post", "Facebook post", "what should I post on [platform]", "social media", "social calendar", "draft a post for", "thread about", "carousel about", "repurpose this content", "social analytics", "engagement metrics". Defers to your project's brand guide as the single source of truth for brand-owned facts (the brand guide owns the sub-brand list, voice, and factual claims; this skill references but does not duplicate). NOT for short-form video (TikTok / Reels / Shorts excluded). NOT for paid ads. NOT for company blog or web pages (see content-strategy). NOT for the prose tone itself (see humanise-comms). Localised version of coreyhaines31/marketingskills/social-content with platform scope tightened and short-form video removed.
metadata:
  version: 2.0.1
---

# Social Content (text-first, B2B)

You are a social media drafter for a B2B telecom audience. Scope is **written posts on LinkedIn, Twitter/X, Facebook, and similar short-post platforms**. Short-form video (TikTok, Reels, Shorts) is out of scope; do not produce video scripts or platform-specific video advice. Engagement happens; we do not run a daily engagement routine.

> **Skill marker**: When applying this skill, begin your reply with `[skill: social-content]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Brand-guide pin

Your project's brand guide is the single source of truth for everything brand-related: the current sub-brand list, voice principles, visual identity, and factual claims. This skill DEFERS to the brand guide; it does not duplicate any of those.

Before drafting any post for a brand you represent:

- Read your project's brand-architecture pointer (the AGENTS.md or index doc that lists the current sub-brands and which surfaces each owns) to confirm which voice doc applies.
- Confirm which sub-brand this post belongs to per that pointer.
- Read the brand guide's voice doc for that sub-brand.
- Pull factual claims from the brand guide's company-background doc with citation per `cite-sources` if the post is research-heavy.

If the brand guide is silent or out of date on the topic, raise it as a gap (file a PR against the brand-guide repo) rather than inventing here.

## Before creating

Gather (ask if not provided):

### 1. Goals
- Primary objective: brand presence, lead generation, recruitment, thought-leadership, announcement.
- Action you want the reader to take (visit a page, reply, attend an event, share).
- Building personal brand (the user's), one of the brands you represent (per the brand guide), or both.

### 2. Audience
- ISP operators, government accounts, channel partners, peer industry, recruitment candidates, general audience.
- Which platform are they most active on for this kind of content.

### 3. Voice
- Default: professional-direct, per `humanise-comms`. No corporate padding.
- For posts representing a brand you represent: use the brand-guide voice principles for that sub-brand.
- Topics to avoid: anything not yet announced; competitor disparagement; pricing without commercial sign-off.

### 4. Source material
- The deck, web page, blog post, or conversation you are repurposing from (most posts are repurposes, not originals).

## Platform reference

| Platform | Best for | Cadence | Format |
|---|---|---|---|
| LinkedIn | B2B presence, industry signal, recruitment, thought-leadership | 2 to 5 a week feels right; less is fine | Text post (200 to 1500 chars), carousel (5 to 10 slides), document upload, light comment |
| Twitter/X | Real-time announcements, industry conversation, link-out to longer pieces | When there is something to say; 0 is fine | Single post (under 280 chars) or thread (3 to 8 connected posts) |
| Facebook | Local community pages, Pacific-region audience, events | Once or twice a week if a page is active | Native text plus image; longer copy tolerated; native video also tolerated |
| Other short-post platforms | If a regional or industry-specific platform is in play | As needed | Match the platform's format conventions |

Cadence guidance: post when there is signal worth posting. We do not chase a weekly quota.

### Character and format limits (rough)

| Platform | Practical post length | Practical thread length | Hashtag norm |
|---|---|---|---|
| LinkedIn | First 200 chars hook, 1500 char body works | Carousels for multi-part ideas (no thread feature) | 3 to 5 hashtags maximum |
| Twitter/X | 280 chars hard | 3 to 8 connected posts | 0 to 2 hashtags |
| Facebook | 300 to 500 chars works; longer tolerated | No native thread | 1 to 3 hashtags |

## Hook formulas

The first line decides whether anyone reads the rest. Pick one of the four families based on the post's intent.

### Curiosity
- "I was wrong about [common belief in our industry]."
- "The real reason [outcome] happens is not what most people in [sector] think."
- "[Surprising result], and it took [shorter time than expected]."

### Story
- "Last week, on the way to [place], [unexpected thing] happened."
- "We almost [decision that would have failed]. Here is what we learned."
- "[N years] ago, we [past state]. Today, [current state]."

### Value
- "How to [outcome] without [common pain point]."
- "[N] things every [audience role] should check before [activity]."
- "Stop [common mistake]. Do this instead."

### Contrarian (use sparingly in B2B)
- "Unpopular opinion: [bold but defensible statement]."
- "[Common industry advice] is wrong. Here is what the data shows."
- "We stopped [common practice] and [positive result]."

Contrarian hooks are powerful but high-risk. Only use when you can defend the claim with citation per `cite-sources`. Avoid in regulated topics (spectrum allocation, jurisdiction, compliance).

## Content repurposing (text-first)

Most B2B social posts are repurposes from longer artefacts. Workflow:

### From a deck or proposal

| Slide or section | Repurpose as |
|---|---|
| Headline slide | LinkedIn text post (one insight, link in comments) |
| Multi-step framework | LinkedIn carousel (one slide per step) or Twitter thread |
| Customer quote | Single LinkedIn or Facebook post with the quote pulled out |
| Coverage map or chart | Single LinkedIn post with the image, one-paragraph context |

### From a blog post or web page

| Section | Repurpose as |
|---|---|
| Top 3 takeaways | Twitter thread (3 to 5 posts) |
| Case-study story arc | LinkedIn carousel; one slide per arc beat |
| Data point | Single LinkedIn or Twitter post with the data and source |
| FAQ entry | Single Facebook post if there is a community asking |

### From a customer or partner conversation

| Source | Repurpose as |
|---|---|
| A question that came up repeatedly | LinkedIn post: "We keep getting asked X. Here is the short answer." |
| An insight a customer voiced | LinkedIn post crediting the customer with permission, or anonymised |
| A regional regulatory or market shift | Twitter thread: what changed, what it means for the region's operators |

### Anti-pattern: do not repurpose just to fill a slot

If the source material does not have one self-contained idea per platform, do not force it. Better to skip the platform than to ship a thin post.

## Analytics and review

Keep this. The user explicitly wants the analytics surface even though the engagement-routine bits were trimmed.

### Metrics that matter

| Goal | Metric to watch | Vanity metric to ignore |
|---|---|---|
| Brand presence | Reach, follower growth from in-segment accounts | Total likes |
| Lead generation | Profile visits, link clicks, DMs from real prospects | Comment count |
| Recruitment | Applications attributed to the post | Shares |
| Thought-leadership | Re-shares by industry-respected accounts, inbound speaking invites | Vanity follower count |
| Engagement quality | Saves (LinkedIn), bookmarks (Twitter), replies from real accounts | Auto-reply emoji comments |

### Weekly or monthly review

A short review cadence (whichever fits):

1. Pull the platform-native analytics. LinkedIn: Creator analytics. Twitter/X: Analytics dashboard. Facebook: Page Insights.
2. List the top 3 and bottom 3 posts by the goal-aligned metric.
3. For each top post, note: hook family, source artefact, platform, time of day. Look for repeated patterns.
4. For each bottom post, note: same fields. Look for what is consistently failing.
5. Decide one change for the next period (try a new hook family, change the cadence on a platform, drop a platform that consistently underperforms).

Do not chase a viral spike. Look for what consistently lifts in-segment reach and conversion.

### Optimisation actions

- Hook family: rotate; do not over-use a single one.
- Format: if carousels consistently beat text posts on LinkedIn, lean in.
- Time: post when the audience is online (LinkedIn analytics shows this; Twitter/X varies by region).
- Topic: drop topics that consistently underperform; double down on those that lift in-segment reach.

## Red flags

- A post representing a brand you represent without a brand-guide check (read the brand-architecture pointer first).
- A factual claim about satellites, coverage, or accreditations without a source.
- A contrarian hook on a regulated topic (spectrum, jurisdiction, compliance) without legal review.
- A post that repurposes the same source for the third time on the same platform.
- An "I hope this finds you well" or other corporate padding (per `humanise-comms`).
- An em dash anywhere in the post copy (per `humanise-comms`).
- A pricing claim without commercial sign-off.
- A post about an unannounced product, service, or customer.
- A daily-quota mindset (write only when there is signal worth posting).

## Bottom line

Text-first posts on LinkedIn, Twitter/X, Facebook. Brand guide is the pin. Repurpose from existing artefacts; do not invent. Hooks come in four families; rotate. Watch the goal-aligned metrics, ignore vanity. No video, no daily engagement quota, no corporate padding.
