---
name: gmail-workflows
description: Use when the user wants to do something concrete with their Gmail via the wired MCP. Triggers include "find that thread about", "search my inbox for", "read that email from", "draft an email to", "draft a reply to", "label that thread", "create a Gmail label", "list my drafts", "follow up on that thread", "triage my inbox by label". Does NOT fire on generic "email" mentions (SMTP design, deliverability, cold outreach copy belong to smtp-deliverability, cold-email, email-sequence). Does NOT fire on "send" requests because the wired MCP only drafts; surface this constraint to the user instead. An estate may pin the access path (a direct API under a named token identity, connectors forbidden, for identity control and auditability); check for that rule first, it overrides this skill's routing.
metadata:
  version: 1.1.0
---

# Gmail Workflows

A thin wrapper over the wired Gmail MCP. Tells the agent which primitive to reach for, how to compose search-then-read patterns, and how to discipline drafting (the wired MCP creates drafts; it does not send).

> **Skill marker**: When applying this skill, begin your reply with `[skill: gmail-workflows]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Check for an estate access rule first (it overrides everything below)

Some organisations pin **how** the mailbox is reached, not just what is done with it: a named token identity, a direct API only, a particular connector forbidden. Such rules exist for identity control (a connector authenticates as whoever authorised it, which is the wrong and uncontrolled identity for automation), production parity, and auditability.

**Look for such a rule before you use the routing below.** Read the standing instructions and memory for the estate you are working in, the working directory's `CLAUDE.md` / `AGENTS.md`, and any estate-specific skill covering this surface. Where a rule exists it **overrides this skill's routing entirely**; this skill then contributes only call mechanics and workflow shapes, never the choice of access path. The failure is otherwise silent: the skill fires on the right trigger, its advice is followed faithfully, and the breach shows up only when someone re-reads the estate's rules.

If no such rule exists, the routing below applies as written.

## Initial Assessment

Before any tool call, read CLAUDE.md / AGENTS.md for any repo-scoped inbox guidance (including an access-path rule per the section above), then walk through:

1. **Intent.** Read (search threads, read one thread), draft (new email, reply, forward), label (create / apply / triage), or list drafts (review what's already saved)?
2. **Sensitivity check.** If reading a thread, scan for PII / credentials / financials before quoting it back to the user. If drafting on the user's behalf, confirm the recipient list and any sensitive content in the body.
3. **Recipient confirmation (drafts only).** Always show the user the To, Cc, Subject, and full body before calling `create_draft`. Drafts saved to the wrong recipient are a real risk, especially with autocomplete-style address resolution.

If any of these is unclear, ask via AskUserQuestion before reaching for a tool.

## When to Use This Skill

- The user references their Gmail inbox explicitly ("find that thread about the H2 review", "draft a reply to Sara").
- The user wants a draft created for a specific recipient with specific content.
- The user wants to manage labels (create, rename, delete, apply via thread filtering).
- The user wants to triage drafts already in the queue (review, edit, delete).
- A meeting follow-up needs an email drafted (cross-skill with `calendar-workflows`).
- A task in Asana needs a notification email drafted (cross-skill with `asana-workflows`).

## When NOT to Use This Skill

- The user is talking about SMTP setup, deliverability, SPF / DKIM / DMARC, suppression lists, or sender reputation. Route to `smtp-deliverability`.
- The user is writing cold-outreach copy. Route to `cold-email` for shape; `humanise-comms` for voice.
- The user is designing a lifecycle email sequence. Route to `email-sequence`.
- The user is writing prose for a draft. The drafting tool here is for assembly; the voice rules live in `humanise-comms` (no em dashes, British / Pacific English, professional-direct tone).
- The user says "send this email". The wired MCP cannot send; explain the constraint and offer to draft instead.

## Tool catalogue

The wired Gmail MCP (`mcp__d76379c3...`) exposes:

| Tool | One-line shape |
|---|---|
| `search_threads` | Query inbox threads by string (sender, subject, body, label). Use first to find the thread the user means. |
| `get_thread` | Read a thread by ID. Call after `search_threads` returns a candidate. |
| `create_draft` | Save a draft to the user's Drafts folder. **Does NOT send.** Always show the user the full draft body and recipients before calling. |
| `list_drafts` | Enumerate drafts already saved. Useful for triage. |
| `list_labels` | Enumerate labels. Call once per session to anchor label IDs. |
| `create_label` | Create a new label. |
| `update_label` | Rename or recolour a label. |
| `delete_label` | Delete a label. Needs explicit user confirmation. |

**Draft-only constraint, called out loudly:** the wired MCP exposes `create_draft` but no send tool. When the user says "send this email", explain: "I can draft this; you'll need to click Send in Gmail. Want me to draft it now?" Do not pretend the draft was sent; do not silently route the request elsewhere.

## Common Workflows

### Search-then-read

1. Confirm the search query with the user (sender, subject, label, date range).
2. `search_threads` with the query.
3. If multiple matches, render a short list and ask which one.
4. `get_thread` with the chosen thread ID.
5. Summarise the thread back to the user, flagging any sensitive content (don't quote credentials verbatim).

### Draft a reply from a thread

1. Run the search-then-read workflow to land on the right thread.
2. Sketch the reply body inline. Apply `humanise-comms` voice rules (no em dashes, British / Pacific English, professional-direct, no banned phrases).
3. Show the user the full draft: To, Cc, Subject (auto-prefixed Re:), body.
4. On sign-off, `create_draft` with `in_reply_to` set to the thread.

### Draft a new email

1. Confirm recipient(s), subject, and body intent with the user.
2. Sketch the body inline. Apply `humanise-comms` voice rules.
3. Show the user the full draft: To, Cc, Bcc, Subject, body.
4. On sign-off, `create_draft`.

### Label-based triage

1. `list_labels` to anchor label IDs.
2. `search_threads` with `label:<name>` query (Gmail search syntax).
3. Render the matching threads. Let the user act (read, archive via label changes, draft replies).

### Follow-up after a meeting

1. Cross-skill with `calendar-workflows`: `get_event` for the meeting context.
2. Confirm attendees who need the follow-up (often a subset).
3. Sketch the follow-up body referencing the meeting (date, key decisions, action items).
4. Show the user the full draft.
5. On sign-off, `create_draft` per recipient (or one draft with the meeting attendee list).

### Cross-skill handoff to Asana task

1. Run the draft workflow above.
2. Cross-skill with `asana-workflows`: create a follow-up task referencing the email subject and the recipient.

### Triage existing drafts

1. `list_drafts` to enumerate.
2. Render a list with subjects and recipients.
3. For each draft the user wants to act on: edit the body (re-show, ask for sign-off, save by creating a new draft and deleting the old) or delete outright (confirm first).

## Drafting discipline

- **Always show the draft first.** Recipients, subject, full body. No "I've drafted an email; let me know if you want changes" without showing it.
- **Voice rules are not optional.** `humanise-comms` applies: no em dashes, British / Pacific English, no banned phrases ("hope this finds you well", "kindly", "circle back", etc.), professional-direct tone.
- **Sensitivity check.** If the body contains a customer name, deal size, headcount number, or any identifier that maps to a real person, confirm with the user before drafting.
- **Reply-all vs reply.** Default to reply (not reply-all) unless the user explicitly asks otherwise. Reply-all on a sensitive thread is a foot-gun.
- **No send.** The wired MCP creates drafts only. State this constraint when the user expects a send.

## Cross-references

- `humanise-comms`: voice rules for every draft body. No em dashes. British / Pacific English. Banned phrases list.
- `smtp-deliverability`: sender-side infrastructure (SPF / DKIM / DMARC / suppression / warmup). Different scope; use both when a chunk crosses the boundary (e.g. drafting a follow-up to a deliverability complaint thread).
- `cold-email`: cold-outreach shape and structure. Use for the copy decisions; come back here for the draft assembly.
- `email-sequence`: lifecycle / drip sequence design. Use for the sequence shape; come back here for the per-step draft.
- `calendar-workflows`: meeting-to-email follow-ups.
- `asana-workflows`: email-to-task follow-ups.

## Red Flags

- Reaching for the connector on a surface whose estate pins a different access path. The routing here is a default, not a licence; an estate access rule outranks it, and the opening read of a session is where this is usually breached, before anyone has re-read the standing rules.
- Drafting on the user's behalf without showing the body first. Always show before `create_draft`.
- Sending PII (customer names, deal sizes, headcount numbers, credentials) into a draft without a sensitivity check.
- Treating `create_draft` as a send. The draft sits in Drafts until the user opens Gmail and clicks Send. Do not pretend otherwise.
- Reply-all by default. Reply is the default; reply-all needs explicit user opt-in.
- Quoting credentials or tokens verbatim from a thread when summarising back to the user. Mask or redact.
- Letting `humanise-comms` voice rules slip ("Hope this finds you well", em dashes, "Kindly", "Going forward"). The marker for `humanise-comms` should also fire on any reply that includes draft prose.
- Calling `delete_label` or `delete_draft` (if exposed) without explicit user confirmation of the exact target.
- Skipping the search-then-read step and drafting based on what the user described, when the actual thread might contain context that changes the reply.

## Bottom Line

The wired Gmail MCP drafts; it does not send. Always show the user the full draft (recipients, subject, body) before `create_draft`. Apply `humanise-comms` voice rules to every draft body. Search-then-read before drafting a reply. Defer copy shape to `cold-email` / `email-sequence`; defer deliverability infrastructure to `smtp-deliverability`.
