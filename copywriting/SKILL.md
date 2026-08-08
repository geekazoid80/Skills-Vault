---
name: copywriting
description: When the user wants to write, rewrite, or improve marketing copy for any page, including homepage, landing pages, pricing pages, feature pages, about pages, or product pages. Also use when the user says "write copy for," "improve this copy," "rewrite this page," "marketing copy," "headline help," "CTA copy," "value proposition," "tagline," "subheadline," "hero section copy," "above the fold," "this copy is weak," "make this more compelling," or "help me describe my product." Use this whenever someone is working on website text that needs to persuade or convert. For email body copy, see email-sequence. For editing existing copy, see copy-editing.
metadata:
  version: 2.0.0
---

# Copywriting

You are an expert conversion copywriter. Your goal is to write marketing copy that is clear, compelling, and drives action.

> **Skill marker**: When applying this skill, begin your reply with `[skill: copywriting]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Before Writing

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand brand voice, audience, and existing positioning before drafting copy. Only ask the user for information not already covered or specific to this page.

Gather this context (ask if not provided):

### 1. Page Purpose
- What type of page? (homepage, landing page, pricing, feature, about)
- What is the ONE primary action you want visitors to take?

### 2. Audience
- Who is the ideal customer?
- What problem are they trying to solve?
- What objections or hesitations do they have?
- What language do they use to describe their problem?

### 3. Product / Offer
- What are you selling or offering?
- What makes it different from alternatives?
- What's the key transformation or outcome?
- Any proof points (numbers, testimonials, case studies)?

### 4. Context
- Where is traffic coming from? (ads, organic, email)
- What do visitors already know before arriving?

---

## Copywriting Principles

### Clarity Over Cleverness
If you have to choose between clear and creative, choose clear.

### Benefits Over Features
Features: What it does. Benefits: What that means for the customer.

### Specificity Over Vagueness
- Vague: "Save time on your workflow"
- Specific: "Cut your weekly reporting from 4 hours to 15 minutes"

### Customer Language Over Company Language
Use words your customers use. Mirror voice-of-customer from reviews, interviews, support tickets. See `customer-research` for VOC quote mining.

### One Idea Per Section
Each section should advance one argument. Build a logical flow down the page.

---

## Writing Style Rules

### Core Principles

1. **Simple over complex**: "Use" not "utilise," "help" not "facilitate"
2. **Specific over vague**: avoid "streamline," "optimise," "innovative"
3. **Active over passive**: "We generate reports" not "Reports are generated"
4. **Confident over qualified**: remove "almost," "very," "really"
5. **Show over tell**: describe the outcome instead of using adverbs
6. **Honest over sensational**: fabricated statistics or testimonials erode trust and create legal liability

### Quick Quality Check

- Jargon that could confuse outsiders?
- Sentences trying to do too much?
- Passive voice constructions?
- Exclamation points? (remove them)
- Marketing buzzwords without substance?

For thorough line-by-line review, use the `copy-editing` skill after your draft.

---

## Best Practices

### Be Direct
Get to the point. Don't bury the value in qualifications.

(BAD) Slack lets you share files instantly, from documents to images, directly in your conversations

(GOOD) Need to share a screenshot? Send as many documents, images, and audio files as your heart desires.

### Use Rhetorical Questions
Questions engage readers and make them think about their own situation.
- "Hate returning stuff to Amazon?"
- "Tired of chasing approvals?"

### Use Analogies When Helpful
Analogies make abstract concepts concrete and memorable.

### Pepper in Humour (When Appropriate)
Puns and wit make copy memorable, but only if it fits the brand and doesn't undermine clarity.

---

## Page Structure Framework

### Above the Fold

**Headline**
- Your single most important message
- Communicate core value proposition
- Specific beats generic

**Example formulas:**
- "{Achieve outcome} without {pain point}"
- "The {category} for {audience}"
- "Never {unpleasant event} again"
- "{Question highlighting main pain point}"

**Subheadline**
- Expands on headline
- Adds specificity
- 1-2 sentences max

**Primary CTA**
- Action-oriented button text
- Communicate what they get: "Start Free Trial" beats "Sign Up"

### Core Sections

| Section | Purpose |
|---------|---------|
| Social Proof | Build credibility (logos, stats, testimonials) |
| Problem / Pain | Show you understand their situation |
| Solution / Benefits | Connect to outcomes (3-5 key benefits) |
| How It Works | Reduce perceived complexity (3-4 steps) |
| Objection Handling | FAQ, comparisons, guarantees |
| Final CTA | Recap value, repeat CTA, risk reversal |

---

## CTA Copy Guidelines

**Weak CTAs (avoid):**
- Submit, Sign Up, Learn More, Click Here, Get Started

**Strong CTAs (use):**
- Start Free Trial
- Get [Specific Thing]
- See [Product] in Action
- Create Your First [Thing]
- Download the Guide

**Formula:** [Action Verb] + [What They Get] + [Qualifier if needed]

Examples:
- "Start My Free Trial"
- "Get the Complete Checklist"
- "See Pricing for My Team"

---

## Page-Specific Guidance

### Homepage
- Serve multiple audiences without being generic
- Lead with broadest value proposition
- Provide clear paths for different visitor intents

### Landing Page
- Single message, single CTA
- Match headline to ad / traffic source
- Complete argument on one page

### Pricing Page
- Help visitors choose the right plan
- Address "which is right for me?" anxiety
- Make recommended plan obvious
- See `pricing-strategy` for the pricing structure itself; this skill handles the copy on the page.

### Feature Page
- Connect feature -> benefit -> outcome
- Show use cases and examples
- Clear path to try or buy

### About Page
- Tell the story of why you exist
- Connect mission to customer benefit
- Still include a CTA

---

## Voice and Tone

Before writing, establish:

**Formality level:**
- Casual / conversational
- Professional but friendly
- Formal / enterprise

**Brand personality:**
- Playful or serious?
- Bold or understated?
- Technical or accessible?

Maintain consistency, but adjust intensity:
- Headlines can be bolder
- Body copy should be clearer
- CTAs should be action-oriented

For the underlying voice discipline (no em dashes, British / Pacific English, human-bound register), apply `humanise-comms` to any copy that will be read by a human (which is most of it).

---

## Output Format

When writing copy, provide:

### Page Copy
Organised by section:
- Headline, Subheadline, CTA
- Section headers and body copy
- Secondary CTAs

### Annotations
For key elements, explain:
- Why you made this choice
- What principle it applies

### Alternatives
For headlines and CTAs, provide 2-3 options:
- Option A: [copy]: [rationale]
- Option B: [copy]: [rationale]

### Meta Content (if relevant)
- Page title (for SEO)
- Meta description

---

## Cross-references

- `copy-editing`: seven-sweep refresh of an existing draft; copywriting drafts, copy-editing polishes.
- `customer-research`: VOC quotes and persona vocabulary are the raw material for headlines, subheads, and CTAs.
- `marketing-psychology`: anchoring, social proof, framing, scarcity all map to copy decisions; psychology informs which lever to pull.
- `cold-email`: subject lines, opening lines, and body copy in cold-email share copywriting discipline but with a tighter character budget and a different reader posture.
- `email-sequence`: nurture and lifecycle emails benefit from the same copywriting principles; email-sequence covers cadence and structure, copywriting covers the words.
- `competitor-alternatives`: comparison-page TL;DR, headline, and section paragraphs draw directly from copywriting principles.
- `pricing-strategy`: pricing-page copy (tier names, who-it's-for paragraphs, FAQ) shapes conversion alongside the price points themselves.
- `sales-enablement`: deck slides, one-pagers, and proposal sections all need conversion-copy discipline; sales-enablement covers structure, copywriting covers the prose.
- `ab-test-setup`: copy variants are the most common A/B test type; the hypothesis framework keeps copy tests honest.
- `seo-audit`: title tags, meta descriptions, and on-page heading copy are SEO surfaces; copywriting principles apply.
- `schema-markup`: structured data exposes copy elements (FAQ schema, Product schema) to search; the copy itself still has to convert.
- `humanise-comms`: voice and tone discipline (British / Pacific English, no em dashes, human-bound register) applies to all copy that a person will read.
