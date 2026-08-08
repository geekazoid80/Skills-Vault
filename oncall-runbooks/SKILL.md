---
name: oncall-runbooks
description: Use when writing or running incident response. Triggers include "we have an incident", "production is down", "the API is returning 500s", "draft an incident runbook", "write a postmortem for X", "do an incident review", "set up on-call for Y", "incoming on-call handoff", "I'm going on call next week", "what's our SEV1 procedure". Covers severity classification (SEV1-4), runbook structure (overview, detection, triage, mitigation, root cause, resolution, communication, escalation), postmortem structure (executive summary, timeline, root cause with 5 whys, contributing factors, action items, lessons learned), the blameless-culture discipline (system-not-individual focus; what conditions allowed this), and on-call handoff structure (active incidents, ongoing investigations, recent changes, known issues, upcoming events). Localised consolidation of wshobson/agents/plugins/incident-response (postmortem-writing + incident-runbook-templates + on-call-handoff-patterns folded into one skill).
metadata:
  version: 1.0.0
---

# On-Call Runbooks

> **Skill marker**: When applying this skill, begin your reply with `[skill: oncall-runbooks]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Cover the three artefacts of incident response: the runbook (procedure for when an alert fires), the postmortem (what we learned after it resolved), and the handoff (what the next on-call person needs to know). All three share one principle: structure for a 3 AM brain that has just been paged.

**Core principle:** the artefact is structured BEFORE you need it. A runbook written during the incident is too late; a postmortem written from memory after the next sprint is too late; a handoff written on the way out the door is too late. Pre-structure everything.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the on-call rotation, severity-classification policy, paging escalation paths, and existing runbook conventions before authoring. Only ask the user for information not already covered or specific to this runbook.

Before authoring, understand:

1. **Service and audience**
   - Which service or component does the runbook cover?
   - Audience (on-call engineer cold, SME with context, hand-off to another team)?
   - Tier of the service (P1 customer-facing, internal tool, batch process)?

2. **Severity and paging**
   - Severity ladder in use (SEV1-3, P0-P4)?
   - Pager destination (PagerDuty schedule, OpsGenie, shared channel)?
   - Escalation timer expectations?

3. **Existing artefacts**
   - Linked dashboards (Grafana, vendor-native console)?
   - Linked log queries / saved searches?
   - Known-good rollback or remediation playbook?

---

## When to use

- An alert just fired and you need a runbook to follow.
- A postmortem is due (per the team's SEV-triggers policy).
- An on-call shift is about to change and the outgoing engineer is writing a handoff.
- Onboarding a new on-call rotation participant.
- Auditing existing runbooks / postmortem quality / handoff templates.

## Severity classification

Pick the team's policy and stick to it. The vault default mirrors the wshobson upstream:

| Severity | Impact | Response time | Examples |
|---|---|---|---|
| **SEV1** | Complete outage; data loss; security breach | 15 min | Production down for all users; database corruption; unauthorised access discovered |
| **SEV2** | Major degradation; critical feature broken | 30 min | Payment flow broken; auth flow broken; one tenant entirely down |
| **SEV3** | Minor impact; one feature degraded | 2 hours | Search slow; one report endpoint failing; non-critical dashboard down |
| **SEV4** | Cosmetic; minimal impact | Next business day | Misaligned UI; stale documentation; non-critical metric scraping gap |

The severity drives the runbook's response time, the comms cadence (status page updates, customer-facing notifications), and whether a postmortem is mandatory. SEV1 and SEV2 always get postmortems; SEV3 gets one if it's a near-miss or novel; SEV4 typically not.

## Runbook structure

A runbook covers ONE failure mode for ONE service. Live in `docs/runbooks/<service>-<failure-mode>.md` (or wherever the project documents runbooks per `plan-time-tooling`'s engineering:deploy-checklist trigger).

```
1. Overview and impact (one paragraph)
2. Detection (alerts that fire, dashboards to open)
3. Initial triage (first 5 minutes; quick health checks)
4. Mitigation (immediate-relief steps; revert deploy, scale up, restart)
5. Root cause investigation (the systematic-debugging Phase 1 loop)
6. Resolution (the actual fix once cause is found)
7. Verification and rollback (how to confirm healed; how to roll back if mitigation worsened things)
8. Communication (status page template, customer email template)
9. Escalation matrix (who to wake up, in what order, after how long)
```

The 5-minute triage section is the most-read part; weight it accordingly.

### Triage section template

```markdown
## Initial triage (first 5 minutes)

1. Acknowledge the alert in the incident tool.
2. Open the service dashboard at <link>.
3. Check recent deployments: `<exact command>`.
4. Check upstream dependencies: <link to status pages>.
5. Quick health checks:
   - [ ] Service reachable: `curl -I <health endpoint>`
   - [ ] Database connectivity: `<exact command>`
   - [ ] Cache reachable: `<exact command>`
   - [ ] Queue depth: `<exact command>`
6. If recent deploy: consider rollback (link to rollback runbook).
7. If unclear: page secondary on-call; declare incident.
```

The exact commands are the value; vague guidance ("check service health") fails at 3 AM.

### Mitigation vs resolution

Mitigation = stop the bleeding (rollback, scale, restart, failover). Resolution = fix the actual cause. Always mitigate first; resolve later in a follow-up chunk where systematic-debugging applies properly.

A common failure mode: skipping mitigation and going straight to root-cause investigation while users are still affected. Mitigate, THEN investigate. Even if mitigation is "we don't know why; rolling back to the previous version".

## Postmortem structure

A postmortem covers ONE incident. Live in `docs/postmortems/YYYY-MM-DD-<short-title>.md`. The vault structure is:

```markdown
# Postmortem: <short title>

**Date:** YYYY-MM-DD
**Authors:** <names>
**Status:** Draft | In Review | Final
**Severity:** SEVN
**Duration:** N minutes (start to all-clear)

## Executive summary

One paragraph: what happened, who was affected, how long, root cause in plain language, how it was resolved. The ONE paragraph someone reads if they read nothing else.

## Impact

- Customers affected: N (or % of traffic).
- Revenue impact (if quantifiable).
- Support tickets generated.
- Data loss / data integrity implications.
- Security implications.

## Timeline (all times UTC)

| Time | Event |
|---|---|
| 14:23 | Deploy v2.3.4 completed |
| 14:31 | First alert: <alert name> |
| ... | ... |
| 15:18 | Service fully recovered; incident resolved |

UTC always (per `utc-timestamps`); local time is ambiguous across the team.

## Root cause analysis

### What happened

The mechanical description of what went wrong. One paragraph.

### Why it happened

1. **Proximate cause:** the change / event that immediately triggered the failure.
2. **Contributing factors:** conditions that allowed the proximate cause to escalate (missing test, masked staging, alert threshold too high, runbook gap).
3. **5 Whys analysis:** chain of "why?" five levels deep, ending at a system-level cause (process gap, missing tooling, knowledge gap, organisational decision). NOT at a person ("the developer made a mistake" is not a root cause).

## Action items

| Action | Owner | Priority | Due |
|---|---|---|---|
| Add connection-pool integration test | @alice | High | 2026-05-16 |
| Lower alert threshold from 90% to 70% | @bob | High | 2026-05-12 |
| Document connection-management patterns | @carol | Medium | 2026-05-23 |
| Add staging traffic-replay job | @dan | Low | 2026-06-15 |

Each action item is a real ticket in the team's tracker, not a paragraph buried in the doc. The doc links to the tickets.

## What went well

The blameless-culture half: what did the team do right that should be repeated. Quick detection, clean mitigation, good comms cadence, cross-team coordination.

## What we learned

The forward-looking half: what changes to runbooks, alert thresholds, deploy procedures, training, or architecture come out of this. Distinguish "we already changed this" from "we will change this".
```

### Blameless culture (the iron rule)

Postmortems are about systems, not individuals. The same engineer who triggered the incident is the one who knows most about it; they need to feel safe to share that knowledge. If postmortems become trials, the team learns to hide information instead of share it.

| Blame-focused | Blameless |
|---|---|
| "Who caused this?" | "What conditions allowed this?" |
| "Someone made a mistake" | "The system allowed this mistake" |
| Punish individuals | Improve systems |
| Hide information | Share learnings |

The 5 Whys must end at a system cause, not a person. "Why did the developer push the bad change?" is not a 5-Whys answer; "Why did the system allow a bad change to reach production?" is.

### Postmortem triggers

Mandatory:

- SEV1 or SEV2 incidents.
- Customer-facing outages over 15 minutes.
- Data loss or security incidents.
- Near-misses that COULD have been severe (the dry-run that almost dropped the prod database; the deploy that almost shipped a regression).
- Novel failure modes (a class of bug the team hasn't seen before).
- Incidents requiring unusual intervention (manual data repair, cross-team escalation, vendor war room).

Optional:

- Recurring SEV3s that signal a pattern.
- Successful incident response that's worth documenting as a positive example.

## On-call handoff structure

Handoffs live in the team's chat or a shared doc. Recommend a 30-minute overlap between shifts (15 min for the outgoing engineer to write; 15 min for a sync call with the incoming engineer).

```markdown
# On-call handoff: <team>

**Outgoing:** @alice (YYYY-MM-DD to YYYY-MM-DD)
**Incoming:** @bob (YYYY-MM-DD to YYYY-MM-DD)
**Handoff time:** YYYY-MM-DD HH:MM UTC

## Active incidents

(Currently firing or recently resolved within the shift.)

### <Incident name>
- Status: <ongoing / monitoring / mitigated>
- Severity: SEVN
- Started: <when>
- Impact: <one line>
- Mitigation: <what's been done>
- Next step: <what the incoming engineer should do>
- Resources: <links: dashboards, threads, tickets>

## Ongoing investigations

(Issues being debugged that aren't full incidents but need attention.)

### <Investigation name>
- Status: <investigating / monitoring / waiting on X>
- Started: <when>
- Impact: <one line>
- Context: <what we know>
- Next step: <what the incoming engineer should do>

## Recent changes

(Deploys, config edits, dependency bumps, vendor updates within the shift.)

| Time | Change | Owner |
|---|---|---|
| YYYY-MM-DD HH:MM | Deployed v2.3.4 | @alice |
| ... | ... | ... |

## Known issues with workarounds

(Things that are broken but have a documented workaround; the incoming engineer should know.)

## Upcoming events

(Maintenance windows, releases, vendor outages scheduled, planned drills.)

## Pages this shift

(How many alerts fired; were they actionable; any false alarms to silence.)
```

The "next step" field per investigation is the most valuable. The incoming engineer should be able to pick up exactly where the outgoing engineer left off.

### Handoff anti-patterns

- "Nothing to report" when there were actually 3 paged alerts that the outgoing engineer dismissed silently.
- A list of incidents without a "next step" per item (the incoming engineer has to re-read the chat history to figure out what to do).
- Status set to "resolved" for incidents that are actually still in monitoring.
- Recent-changes section missing the deploy that's about to cause the next incident.

## Cross-references

- `systematic-debugging`: the Phase 1 evidence-gathering at component boundaries IS the runbook's "Initial triage" step. Phase 4 (one fix, then verify) IS the runbook's "Resolution".
- `completion-gate` Layer 3: the verification commands in the runbook's "Verification" section apply the iron law (no claim of "resolved" without fresh verification evidence).
- `humanise-comms`: incident comms (status page, customer email, internal updates) follow the humanise-comms voice baseline. The runbook's communication templates draft the structure; humanise-comms shapes the tone.
- `secrets-hygiene`: NEVER paste real credentials, API keys, or vendor tokens into runbook commands or postmortem timelines. Use placeholders that point at the secret store.
- `utc-timestamps`: all timeline entries in postmortems and handoffs are UTC.
- `plan-time-tooling`: the engineering:deploy-checklist trigger covers writing the runbook for any chunk that ships infrastructure. Land the runbook with the chunk, not after the first incident.
- `linux-host-bringup`: the validation step in Phase 8 of a host bring-up should produce a stub runbook for the new host. Future incidents on that host start from that stub.
- `slo-implementation`: SLO burn-rate alerts page on-call; the page payload should carry the runbook URL. On-call shift handover reads the SLO snapshot first.
- `zabbix-templates-and-triage`: the four-step triage protocol (observe / deduce / test / fix) and the triage log template feed straight into the runbook's "Initial triage" section and the postmortem's "Timeline" section.
- `grafana-dashboards`: the runbook should name the Grafana dashboard URL on-call should open first; alert payloads carry the dashboard URL alongside the runbook URL.
- `graylog-log-investigation`: when the runbook's "Initial triage" needs log evidence, the Graylog stream and saved-search URL belong in the runbook by name; alert payloads carry both.
- `incident-response-network`: security-IR network-forensics sibling. When the incident is a confirmed or suspected security event with network-level evidence requirements (preserve ARP / MAC / CAM tables before they age out, capture flow records, verify containment ACLs, reconstruct timeline with chain-of-custody discipline), hand off the technical evidence layer there. This skill remains the devops-flavour generic container; `incident-response-network` is the security-IR network-forensics arm.
- `incident-response-lifecycle`: NIST 800-61 process sibling. When the incident requires formal severity classification (P1-P4 on data-risk axis), four-role assignment (Incident Commander / Technical Lead / Communications Lead / Scribe), audience-specific communications (executive / technical / customer / regulatory), or facilitated blameless post-mortem with 5-whys + contributing-factor categorisation + four-disposition action-item model, hand off the process-management layer there. This skill remains the devops-flavour generic container; `incident-response-lifecycle` is the security-IR-flavour NIST 800-61 process complement.

## Common mistakes

- Writing the runbook the first time the alert fires (too late; write it when shipping the service).
- Skipping mitigation to investigate root cause while users are still affected.
- 5 Whys that ends at "the developer made a mistake" instead of "the system allowed the mistake".
- Postmortems with action items that aren't real tickets in the team's tracker.
- Action items without owners or due dates ("we should fix this someday").
- Handoffs that say "nothing to report" when 3 alerts fired this shift.
- Vague triage commands ("check service health") instead of exact commands.
- Local-time timestamps in postmortems (ambiguous across timezones; use UTC).
- Pasting real secrets / customer data into runbook examples (use placeholders).

## Red flags

- An alert fires and there is no runbook for it.
- A postmortem is about to be written without the timeline being constructed first (the timeline is the artefact; opinion comes after evidence).
- A 5 Whys analysis blames a person at level 3 and stops.
- Action items added to the postmortem doc but never filed as tickets (decay guaranteed).
- Handoff written from memory after the incoming engineer is already on call.
- Same SEV3 recurring three times without a postmortem (the pattern is the postmortem).
- A runbook with placeholder values that haven't been filled in (`<exact command>`, `TODO`, `your service here`).
- Communication templates that quote a real customer name or transaction ID (PII / privacy gap).

## Bottom line

Pre-structure everything. Runbooks before the alert; postmortems with timeline before opinion; handoffs with next-step per investigation. The 3 AM brain needs structure, not prose.
