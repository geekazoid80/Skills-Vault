---
name: verify-before-asserting
description: "Use before stating a finding about state that someone might act on: that something is missing, orphaned, lost, stranded, at risk, broken, unmerged, dead, stale, absent, duplicated, unowned, unused or misconfigured. Fires on \"X is missing\", \"that was never done\", \"this is orphaned\", \"nobody owns this\", \"it would have been lost\", \"there is no PR\", \"the branch is unmerged\", \"that account is unused\", \"the data is gone\", \"this is at risk\", and on any finding about to be written into a tracker, ticket, PR, alert, report or message to another person. NOT for claims about whether your own work is finished (completion-gate owns done, fixed, passing, ready to merge). Covers the falsifying-check-first rule, naming the check before running it, what a tool actually measures (a direction, a subset or a derived signal rather than the state you asked about), the blast-radius ladder that raises the bar as a finding moves from thought to speech to a shared surface, and treating an inherited framing from a summary, brief or handoff as a hypothesis rather than evidence."
metadata:
  version: 1.0.0
---

# Verify Before Asserting

> **Skill marker**: When applying this skill, begin your reply with `[skill: verify-before-asserting]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

A finding is a claim about the state of something: this is missing, that is broken, nobody owns this,
that work was lost. Findings are acted on. They get written into trackers, raised with colleagues,
turned into recovery work, and they become the premise of the next decision.

The failure this skill prevents is not ignorance. It is asserting a finding that is one cheap command
away from being falsified, and then building on it before running that command.

**Core principle: a finding you have not tried to disprove is a hypothesis. Say so, or test it.**

## The iron rule

> Before a finding leaves your head, name the single cheapest check that would prove it WRONG, and run
> that check.

Two halves, both required. **Name it first**, out loud or in your notes, because a check chosen after
the fact gets chosen to agree with you. **Make it a falsifying check**, because gathering more evidence
that you are right is not verification, it is accumulation.

If you cannot name a check that would falsify the finding, you do not have a finding. Report it as an
open question instead, and say what would settle it.

## What your tool actually measured

Most bad findings come from a tool that answered a different question from the one asked, in a way that
reads as a direct answer. Three recurring shapes:

**A direction, not a state.** Comparison tools state a path between two reference points. Their output
is shaped by which two points you named and in which order, so it describes a relationship, not what
exists. The same underlying reality yields opposite-looking output depending on the direction, and
neither output is a statement about what you did or what is present.

**A subset, not the whole.** Anything paged, limited, filtered, truncated or capped returns a partial
view that looks exactly like a complete one. There is no error and the magnitude is plausible. A search
that answers "not found" from page one of several has not searched.

**A derived signal, not the thing.** Ancestry, lineage, timestamps, identifiers, counts and status
fields are computed from an underlying reality through rules that can decouple from it. When the
derivation has a known lossy step, every tool that reads the derived signal agrees with every other one,
and they are all wrong together.

The practical consequence: **several tools agreeing is not corroboration when they read the same
derived signal.** Ask what each one actually inspects. If the answer is the same field, you have one
observation, not three.

## Blast radius sets the bar

The verification bar rises with how far the finding travels. Judge which rung you are on before you
speak.

| Where the finding is going | Bar before it goes |
|---|---|
| Your own reasoning, next step private and reversible | Note it as unconfirmed and carry on |
| Spoken to the user as a possibility | Say "I think" and name what would settle it |
| Stated to the user as fact | Falsifying check run first |
| Written to a durable shared surface (tracker, ticket, PR, doc, alert, memory) | Falsifying check run first, and the evidence recorded with it |
| Acted on, especially in someone else's repo, account or system | Falsifying check run first, and the action reversible or confirmed |

The bottom two rungs are where the real cost sits. A wrong thought costs nothing. A wrong finding in a
tracker is read by other people, believed, and acted on; retracting it takes more work than verifying
would have, and the retraction never reaches everyone who saw the original.

## An inherited framing is a hypothesis

A claim arriving from a context summary, a handoff brief, a task description, a colleague's note or your
own earlier conclusion is **someone's finding, not evidence**. It carries the confident grammar of fact
while having none of the backing.

This is the most dangerous input because it arrives pre-loaded and unexamined, and because you will
reach for tools that confirm it rather than tools that test it. Treat the moment you first act on an
inherited framing as the moment to verify it, not the moment to build on it.

## Rationalisations, and why each is wrong

| What you will tell yourself | Why it does not hold |
|---|---|
| "Three separate checks agree" | They may all read one derived signal. One observation, repeated. |
| "The brief already established this" | A brief states a conclusion. It is not the evidence for it. |
| "It is obviously true" | Then the falsifying check is cheap and fast. Run it. |
| "I will confirm it after I flag it" | The flag is the expensive part. Retraction costs more than the check. |
| "There is no time" | The decisive check is usually one command and a few seconds. |
| "It is only a note for later" | Notes are read as settled fact by whoever finds them next. |
| "I would look slow if I checked" | You will look far slower retracting it. |

## Worked example

A session inherits, from a context summary, the statement that a colleague's work "was never merged and
is not on the main line". Every check it reaches for agrees: the lineage query reports the work as
unmerged, and the comparison view shows it as a large body of content the main line lacks.

Acting on that, the session recovers the work, publishes it, raises a review request, and records in the
shared tracker that a colleague's contribution was nearly lost.

All of it was false. The work had been integrated days earlier through a process that rewrites lineage,
so every lineage-based check was structurally incapable of seeing it, and the comparison view was
stating a direction from a fork point rather than what existed. The falsifying check was a single direct
content comparison between the two end states. It returns empty, meaning identical, and takes seconds.

The finding had already escaped into three shared surfaces before that check was run, and each had to be
retracted separately.

The lesson is not "know that particular lossy process". It is that **the check which would have
falsified the claim was cheaper than any one of the actions taken on the strength of it**, and it was
skipped because the inherited framing arrived as settled and the tools agreed.

## Red flags

- About to write "is missing", "was lost", "is orphaned", "nobody owns", "never happened" without having
  run a check that could have returned the opposite.
- Reaching for a second tool that would confirm the finding, rather than one that would break it.
- Citing agreement between tools without having asked what each one actually inspects.
- Building the fix, the recovery or the escalation before the finding is confirmed.
- A finding whose premise came from a summary, brief or handoff, being acted on without re-checking.
- Answering "does this exist" from a result set that hit a page size, row cap or default limit.
- Using a comparison, diff or delta view as evidence about what exists, rather than about a direction
  between two points.
- The words "clearly", "obviously" or "definitely" doing the work that evidence should be doing.
- About to raise it with a person, or write it into a shared surface, while thinking "I am fairly sure".
- Noticing the check is cheap and deciding to run it afterwards.

## Bottom line

Name the cheapest check that would prove your finding wrong, run it, and only then assert. Several tools
agreeing means nothing if they read the same derived signal; a paged read cannot say "not found"; a
comparison states a direction, not a state. An inherited framing is a hypothesis wearing the grammar of
fact. The bar rises the moment the finding leaves your head, and it is highest when it lands somewhere
other people will read and act on, because that is where retraction costs far more than verification
would have.
