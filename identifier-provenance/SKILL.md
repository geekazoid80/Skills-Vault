---
name: identifier-provenance
description: "Use when about to WRITE an identifier into an artefact that someone or something else will act on: a tracking or ticket id, task id, issue or PR number, commit SHA, account or resource id, channel id, config key, or a URL containing one. Fires hardest on artefacts a machine executes with nobody watching: a scheduled prompt, an agent brief, a spawned-task chip, a cron entry, a generated config, a PR body, a commit message, a runbook. Trigger phrases: \"tracking task\", \"see ticket\", \"ref:\", \"update the task\", \"the id is\", \"I will fill the id in later\", \"placeholder\", \"TBD\", and any moment you need a value you have not yet looked up. NOT for asserting a finding about state (verify-before-asserting owns \"X is missing\"), and NOT for whether your own work is done (completion-gate). Covers the resolve-then-write order, the loud-placeholder form for a value you cannot yet confirm, why a well-formed guess is more dangerous than a blank, two-directional resolution, the fail-closed pre-ship scan, and the ways an after-the-fact audit of identifiers quietly lies to you."
metadata:
  version: 1.0.0
---

# Identifier Provenance

> **Skill marker**: When applying this skill, begin your reply with `[skill: identifier-provenance]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

An identifier in a shipped artefact is a promise that a record exists. The promise is cheap to make and
expensive to check, so it usually is not checked, which is what makes a wrong one durable.

**Core principle: every identifier in an artefact has provenance. It was READ from the system that owns
it, in this session, and you can say which call returned it.** An id you recalled, inferred from a
pattern, or composed while drafting has no provenance, and it looks exactly like one that does.

This is not mainly about lying. The usual mechanism is duller: you are writing prose, you reach a slot
that needs a value you have not looked up yet, and you fill it so the sentence can continue. The intent
is to come back. The artefact ships first.

## The order

Three steps, and the order is the whole skill.

1. **Resolve or mint the record.** Create the task, open the issue, push the commit, list the resource.
2. **Read the id back from the response.** Not from what you expected it to be, not from a sibling.
3. **Then write the artefact that names it.**

Working in the other order, drafting the text first and creating the record after, is what produces a
phantom. It feels more efficient because the prose is the visible work, but the dependency runs the other
way: the artefact cannot be correct until the record exists.

**There is often no draft state.** Publishing an artefact can be a single call, so "I will fix the id
before this goes out" has no moment to happen in. Ask what turns your draft into a live thing, and treat
that call as the deadline, not as a save.

## When you cannot confirm the value yet

Sometimes you genuinely must write the surrounding text first. Then the slot gets a **loud placeholder**,
never a plausible value:

```
TRACKING: <TRACKING_ID>          good, unmissable, and greppable
TRACKING: <FILL_ME>              good
TRACKING: 1234567890123456       catastrophic, and this is the real failure shape
TRACKING: 123456                 bad, but at least obviously fake
TRACKING: TBD                    weak: prose-shaped, easy to read past
```

**A well-formed guess is worse than a blank, and this is the counterintuitive part.** A blank fails
loudly at the first read: by you, by a reviewer, by a linter, by the executing process. A value in the
right shape passes every one of those, because everything downstream treats "looks like an id" as "is an
id". You have not left a gap, you have manufactured a fact.

The shape rule follows: a placeholder must be **impossible to confuse with a real value**. Screaming
snake case inside angle brackets is unambiguous in almost every format, survives copy and paste, and is
trivially greppable. Do not use a shortened, zeroed or incremented version of a real id; those are
guesses wearing a disguise.

## Resolve in both directions

"The id appears in the artefact" proves nothing. Two checks, and you need both:

- **The id you wrote resolves** to a real record, of the expected type, in the expected state.
- **A value you rejected does NOT resolve.** Without this, a check that returns "found" for everything
  looks identical to a working one.

The second is the one people skip, and it is what makes the first meaningful. If you corrected an id,
confirm the discarded one is genuinely dead rather than assuming it.

Resolve against **the system that owns the record**, not against a copy. A local clone, a cached export,
a sibling document or your own earlier message can all echo a wrong value back at you convincingly.

## Where this bites hardest

Rank the risk by **who reads it next**, not by how important the artefact feels:

| Artefact | Why | Risk |
|---|---|---|
| Scheduled job, cron entry, unattended agent prompt | Executes with nobody present to notice the id is dead | **Highest** |
| Agent brief, spawned task, hand-off prompt | The receiver has no context to judge the value | High |
| Generated config, IaC, migration | Applied mechanically, often long after writing | High |
| Commit message, PR body, changelog | Read later, by someone reconstructing history | Medium |
| Chat message | The next reader corrects it | Low |

The pattern is that risk rises as the number of humans between the id and its use falls to zero. An
unattended run following a dead reference has nowhere to report and nobody to ask.

## The pre-ship scan

`scripts/scan-artefact.sh` is the mechanical half, because the discipline above is exactly the kind that
fails under composition pressure.

```sh
scripts/scan-artefact.sh path/to/artefact [more...]
```

It does two things:

- **Fails closed on unresolved placeholders.** Any `<SCREAMING_TOKEN>`, `TBD`, `FIXME` or `XXX` exits
  non-zero. This is the check that must never be advisory.
- **Enumerates every identifier-shaped literal**, with line numbers and a count. It cannot know whether
  they are real; that is your job. Stating the denominator is the point, because an id you never noticed
  is one you never resolved.

Run it on the file before the call that publishes it. Run it again on anything a subagent drafted for
you, since a brief's prose is not evidence about the ids inside it.

It makes no judgement about intent, and it should not. Point it at a document that DISCUSSES
placeholders, including this one, and it fires on the examples. That is the scanner being correct
about the bytes in the file and handing you the decision. Resist the urge to teach it which
placeholders are only illustrations: a scanner that guesses intent is a scanner that can excuse a
real one.

## Auditing identifiers after the fact

If you need to check an artefact or a session retrospectively, expect the audit itself to be the weak
part. Five ways it lies, all observed in a single real audit:

- **A tool result echoing your own string is not grounding.** Classifying ids by "did this ever appear in
  a tool result" marked a known fabrication as verified, because a grep of the author's own text is a
  tool result. Provenance means the OWNING system returned it, not that some command printed it.
- **A not-found from an endpoint you did not try** is a fact about your call. An id that 404s as a task
  may be a comment, a user or a section. Try the alternatives before calling it a phantom.
- **A loop that never ran.** Shell word-splitting differences can make a check iterate once over a joined
  string, so every lookup silently fails and the result reads as "nothing resolves". Suspect the
  instrument when EVERY row fails at once; real data is lumpy.
- **A local copy that cannot contain the answer.** A shallow or stale clone genuinely lacks recent
  commits, so a real id reads as missing. Ask the remote.
- **A CLI that prints its error to stdout.** Testing the output body rather than the exit status counts
  every failed lookup as a success. Test the exit status.

Carry a **negative control through the audit**: a value you know is fake must come back not-found. If it
does not, discard the audit rather than its findings.

## Red flags

- You are typing a value into an id slot and cannot name the call that returned it.
- The words "I will fill this in after" about an artefact you are one tool call from publishing.
- An id that matches the shape of others you have been handling, written from memory of the shape.
- A shortened, zeroed, incremented or otherwise "obviously example" version of a real id, in a real file.
- A placeholder that reads as prose (`TBD`, `TODO`, `the task`) rather than as a token.
- Relaying an id from a peer, a summary or a brief into an artefact without resolving it yourself.
- Confirming an id resolves without confirming a rejected one does not.
- An audit where every row fails, or every row passes, and you have not tested the instrument.
- Shipping an artefact a subagent drafted without scanning it, because the prose reads confidently.

## Bottom Line

Resolve or mint the record, read the id back from the response, then write the artefact. If you cannot
confirm the value yet, leave a loud unmissable placeholder, never a plausible one: a blank fails at the
first read, a well-formed guess passes every check and becomes a fact. Verify in both directions, resolve
against the system that owns the record, and scan the file before the call that publishes it. The stakes
scale with how few humans stand between the identifier and its use, which is why an unattended prompt is
the worst place in the estate to guess.
