---
name: calendar-workflows
description: Use when the user wants to do something concrete with their calendar via the wired MCP. Triggers include "what's on my calendar", "find a slot for", "schedule a meeting with", "suggest a time for", "move that meeting", "cancel that meeting", "respond to that invite", "list my calendars", "free / busy check", "block time for". Does NOT fire on idle calendar talk ("I'm busy", "I have a meeting") absent a concrete action verb, and does NOT fire on workflow design ("how should we run our team standup") which is operational, not a calendar action. An estate may pin the access path instead (a direct API under a named token identity, connectors forbidden, for identity control and auditability); check for that rule first, it overrides this skill's routing.
metadata:
  version: 1.1.0
---

# Calendar Workflows

A thin wrapper over the wired Calendar MCP. Tells the agent which primitive to reach for, how to compose free-slot lookups, and how to keep timezones honest.

> **Skill marker**: When applying this skill, begin your reply with `[skill: calendar-workflows]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Check for an estate access rule first (it overrides everything below)

Some organisations pin **how** the calendar is reached, not just what is done with it: a named token identity, a direct API only, a particular connector forbidden. Such rules exist for identity control (a connector authenticates as whoever authorised it, which is the wrong and uncontrolled identity for automation), production parity, and auditability.

**Look for such a rule before you use the routing below.** Read the standing instructions and memory for the estate you are working in, the working directory's `CLAUDE.md` / `AGENTS.md`, and any estate-specific skill covering this surface. Where a rule exists it **overrides this skill's routing entirely**; this skill then contributes only call mechanics and workflow shapes, never the choice of access path. The failure is otherwise silent: the skill fires on the right trigger, its advice is followed faithfully, and the breach shows up only when someone re-reads the estate's rules.

If no such rule exists, the routing below applies as written.

## Initial Assessment

Before any tool call, read CLAUDE.md / AGENTS.md for any repo-scoped scheduling guidance (including an access-path rule per the section above), then walk through:

1. **What action.** Read (list events, look up one event), search (free slots, conflict check), create (new event), update (move, change attendees), delete (cancel), or RSVP (respond to invite)?
2. **Whose calendar.** Acting user by default, but if the user says "Phil's calendar" or "the team calendar", confirm whose scope before calling `list_events`.
3. **Timezone constraint.** What timezone does the user intend? If they say "9am tomorrow", whose 9am? Default to the acting user's primary timezone, but ask if the meeting spans regions or the user named a different attendee's morning.

If any of these is unclear, ask via AskUserQuestion before reaching for a tool.

## When to Use This Skill

- The user references their calendar explicitly ("what's on my calendar", "block 2 hours for", "move the 3pm").
- The user wants a meeting scheduled with named attendees.
- The user wants a free-slot search across a time window.
- The user wants to RSVP to a pending invite.
- A meeting follow-up needs to land elsewhere (cross-skill with `asana-workflows` or `gmail-workflows`).

## When NOT to Use This Skill

- The user says "I'm busy" or "I have a meeting" without asking for a calendar action. That is context, not a request.
- The user asks how the team should structure standups, retros, or planning rituals. That is operational design, not a calendar action.
- The user wants to send a calendar invite as an email outside the wired Calendar MCP. Use `gmail-workflows` for the email-draft side; come back here for the actual event creation.
- The user is debating "should we even have this meeting". Architecture chatter; not for this skill.

## Tool catalogue

The wired Calendar MCP (`mcp__23a5dc5e...`) exposes:

| Tool | One-line shape |
|---|---|
| `list_calendars` | Enumerate calendars the acting user can read. Call once per session to anchor calendar IDs. |
| `list_events` | Read events in a window for a named calendar. Use for inspection, not for free-slot search (prefer `suggest_time`). |
| `get_event` | Read one event by ID. Use after `list_events` returns a candidate. |
| `create_event` | Create a new event with attendees, time, location, body. Always show the user the proposed event before calling. |
| `update_event` | Mutate an existing event (move time, change attendees, edit body). Confirm the delta with the user first. |
| `delete_event` | Cancel an event. Needs explicit user confirmation of the event title and time. |
| `respond_to_event` | RSVP yes / no / maybe to a pending invite. Confirm the response with the user. |
| `suggest_time` | Find free slots for the acting user and a list of attendees in a window. **Default to this over manual `list_events` scans** when the question is "when can we all meet". |

Pre-decided rule: when the question is free-slot or availability shaped, reach for `suggest_time` first. Manual `list_events` scans are for inspection (reading what's there), not for finding gaps.

## Common Workflows

### Free-slot lookup

1. Confirm the time window with the user (e.g. "next week, 9am-5pm SGT, 30-minute slots").
2. `list_calendars` once per session to anchor the calendar ID.
3. `suggest_time` with the window, the duration, and the attendee list.
4. Render the top 3-5 slots. Let the user pick.

### Schedule with N attendees

1. Confirm attendees (display names and email addresses), title, location / video link, body, and duration.
2. Run the free-slot lookup workflow above to pick a time.
3. Show the user the full proposed event.
4. On sign-off, `create_event` with the resolved time and attendees.

### Reschedule with conflict check

1. `get_event` for the event the user wants to move.
2. Confirm the proposed new time with the user.
3. `suggest_time` to verify the new slot is free for all attendees (don't trust the user's "should be fine").
4. If conflicts, surface them and ask for a different slot.
5. On sign-off, `update_event` with the new time.

### RSVP

1. `list_events` to find the pending invite (or `get_event` if the user already has the event ID).
2. Confirm the response with the user (yes / no / maybe + any note).
3. `respond_to_event` with the response.

### Recurring-event handling

The Calendar MCP treats recurring events as a series. Edits and cancellations can hit one instance or the whole series; always confirm the scope with the user before calling `update_event` or `delete_event` on a recurring event. If the MCP returns multiple matches for the same event title, the recurring series is the likely culprit.

### Meeting follow-up to task (cross-skill)

1. `get_event` for the meeting that needs follow-up.
2. Cross-skill handoff to `asana-workflows`: pass the event title, attendees, and date as context for the new task.

### Meeting follow-up to email draft (cross-skill)

1. `get_event` for the meeting.
2. Cross-skill handoff to `gmail-workflows`: pass the attendees and meeting context for the draft body.

## Timezone discipline

The wired Calendar MCP accepts and returns ISO-8601 datetimes. **Always include the timezone offset or IANA zone in any datetime you pass to the MCP.** Never pass a naive datetime (no offset, no zone); the MCP will interpret it against the server's default, which is rarely what the user means.

When rendering events back to the user, show the time in the user's primary timezone (resolve from `list_calendars` if uncertain). If a meeting spans regions, show two columns: the organiser's time and each non-organiser attendee's local time.

See `utc-timestamps` for the broader storage / transmission discipline; this skill enforces the calendar-side convention only.

## Cross-references

- `utc-timestamps`: storage, hashing, and on-the-wire timestamp rules. Calendar events are one consumer of that discipline; the rules there apply here too.
- `asana-workflows`: meeting-to-task follow-ups.
- `gmail-workflows`: meeting-to-email follow-ups; calendar invites that need a personal email alongside the system invite.
- `revops`: round-robin scheduling, meeting routing for sales / CS workflows; this skill drives the MCP-side primitives that revops orchestrates.
- `humanise-comms`: event titles, bodies, and any prose in `respond_to_event` notes are human-bound; voice rules apply.

## Red Flags

- Reaching for the connector on a surface whose estate pins a different access path. The routing here is a default, not a licence; an estate access rule outranks it, and the opening read of a session is where this is usually breached, before anyone has re-read the standing rules.
- Passing a naive datetime (no timezone offset or IANA zone) to any Calendar MCP call. The MCP will silently assume a default; the user will silently get the wrong meeting time.
- Assuming the acting user's calendar when the user said "Phil's calendar" or "the team calendar". Confirm the scope before `list_events`.
- Using `list_events` to find a free slot when `suggest_time` exists. The latter handles the math; the former needs you to do it manually.
- Calling `delete_event` or `update_event` on a recurring event without confirming "this instance" vs "this and following" vs "all" scope.
- Creating an event without showing the user the proposed body, attendee list, time, and location first.
- Sending an RSVP via `respond_to_event` without confirming the response with the user.
- Rendering meeting times to attendees without their local-timezone column (especially for cross-region meetings).
- Treating Google Meet / Zoom links as auto-generated. They are not; confirm with the user whether the event needs a video link and which provider.

## Bottom Line

Default to `suggest_time` for any availability question. Always pass explicit timezone in every datetime. Confirm scope on recurring-event mutations. Show the user the proposed event before creating, updating, or deleting; show the proposed response before RSVPing.
