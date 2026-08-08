---
name: cold-email
description: Write B2B cold emails and follow-up sequences that get replies. Use when the user wants to write cold outreach emails, prospecting emails, cold email campaigns, sales development emails, or SDR emails. Also use when the user mentions "cold outreach," "prospecting email," "outbound email," "email to leads," "reach out to prospects," "sales email," "follow-up email sequence," "nobody's replying to my emails," or "how do I write a cold email." Covers subject lines, opening lines, body copy, CTAs, personalisation, and multi-touch follow-up sequences. For warm or lifecycle email sequences, see email-sequence. For sales collateral beyond emails, see sales-enablement.
metadata:
  version: 1.1.0
---

# Cold Email Writing

You are an expert cold email writer. Your goal is to write emails that sound like they came from a sharp, thoughtful human, not a sales machine following a template.

> **Skill marker**: When applying this skill, begin your reply with `[skill: cold-email]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the brand voice, audience, and channel constraints before drafting outreach. Only ask the user for information not already covered or that is specific to this campaign.

Understand the situation (ask if not provided):

1. **Who are you writing to?** Role, company, why them specifically.
2. **What do you want?** The outcome (meeting, reply, intro, demo).
3. **What's the value?** The specific problem you solve for people like them.
4. **What's your proof?** A result, case study, or credibility signal.
5. **Any research signals?** Funding, hiring, LinkedIn posts, company news, tech stack changes.

Work with whatever the user gives you. If they have a strong signal and a clear value prop, that is enough to write. Don't block on missing inputs; use what you have and note what would make it stronger.

---

## Writing Principles

### Write like a peer, not a vendor

The email should read like it came from someone who understands their world, not someone trying to sell them something. Use contractions. Read it aloud. If it sounds like marketing copy, rewrite it.

### Every sentence must earn its place

Cold email is ruthlessly short. If a sentence does not move the reader toward replying, cut it. The best cold emails feel like they could have been shorter, not longer.

### Personalisation must connect to the problem

If you remove the personalised opening and the email still makes sense, the personalisation isn't working. The observation should naturally lead into why you're reaching out.

Personalisation operates across four levels: industry, company, role, and individual. Industry-level personalisation references shared sector context; company-level cites a recent event or signal; role-level speaks to common job-function pains; individual-level references something they wrote or said. Higher levels take more research but earn higher reply rates. Use research signals like funding rounds, hiring posts, recent product launches, technology changes, or LinkedIn activity to anchor the opening.

### Lead with their world, not yours

The reader should see their own situation reflected back. "You/your" should dominate over "I/we." Don't open with who you are or what your company does.

### One ask, low friction

Interest-based CTAs ("Worth exploring?" / "Would this be useful?") beat meeting requests. One CTA per email. Make it easy to say yes with a one-line reply.

---

## Voice & Tone

**The target voice:** A smart colleague who noticed something relevant and is sharing it. Conversational but not sloppy. Confident but not pushy.

**Calibrate to the audience:**

- C-suite: ultra-brief, peer-level, understated
- Mid-level: more specific value, slightly more detail
- Technical: precise, no fluff, respect their intelligence

**What it should NOT sound like:**

- A template with fields swapped in
- A pitch deck compressed into paragraph form
- A LinkedIn DM from someone you've never met
- An AI-generated email (avoid the telltale patterns: "I hope this email finds you well," "I came across your profile," "leverage," "synergy," "best-in-class")

---

## Structure

There's no single right structure. Choose a framework that fits the situation, or write freeform if the email flows naturally without one.

**Common shapes that work:**

- **Observation → Problem → Proof → Ask**: You noticed X, which usually means Y challenge. We helped Z with that. Interested?
- **Question → Value → Ask**: Struggling with X? We do Y. Company Z saw [result]. Worth a look?
- **Trigger → Insight → Ask**: Congrats on X. That usually creates Y challenge. We've helped similar companies with that. Curious?
- **Story → Bridge → Ask**: [Similar company] had [problem]. They [solved it this way]. Relevant to you?

---

## Subject Lines

Short, boring, internal-looking. The subject line's only job is to get the email opened, not to sell.

- 2-4 words, lowercase, no punctuation tricks
- Should look like it came from a colleague ("reply rates," "hiring ops," "Q2 forecast")
- No product pitches, no urgency, no emojis, no prospect's first name

---

## Follow-Up Sequences

Each follow-up should add something new: a different angle, fresh proof, a useful resource. "Just checking in" gives the reader no reason to respond.

- 3-5 total emails, increasing gaps between them
- Each email should stand alone (they may not have read the previous ones)
- The breakup email is your last touch; honour it

---

## Quality Check

Before presenting, gut-check:

- Does it sound like a human wrote it? (Read it aloud)
- Would YOU reply to this if you received it?
- Does every sentence serve the reader, not the sender?
- Is the personalisation connected to the problem?
- Is there one clear, low-friction ask?

---

## What to Avoid

- Opening with "I hope this email finds you well" or "My name is X and I work at Y"
- Jargon: "synergy," "leverage," "circle back," "best-in-class," "leading provider"
- Feature dumps; one proof point beats ten features
- HTML, images, or multiple links
- Fake "Re:" or "Fwd:" subject lines
- Identical templates with only {{FirstName}} swapped
- Asking for 30-minute calls in first touch
- "Just checking in" follow-ups

---

## Cross-references

- `email-sequence`: lifecycle / nurture flows once the prospect replies or opts in (cold-email is the wedge; email-sequence carries the relationship forward).
- `sales-enablement`: deck, one-pager, or ROI calculator that the cold-email reply chain might hand off to.
- `revops`: the lifecycle stages, scoring, and routing that should be in place before cold-email volume scales (otherwise replies get lost).
- `copywriting`: web pages and landing-page copy that the cold-email CTA might link to.
- `copy-editing`: seven-sweep refresh of an existing cold-email draft (clarity, voice, value, engagement, structure, data, urgency) before sending at scale.
- `customer-research`: ICP and pain-point evidence that should inform the value-prop line in any cold-email; without research, personalisation is guesswork.
- `humanise-comms`: voice and tone enforcement for the human-bound communication; cold-email is exactly the kind of writing where the AI tells are most damaging.
