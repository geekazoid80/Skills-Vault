---
name: incident-response-lifecycle
description: "Use for any NIST 800-61 incident-response process management work. Triggers include \"declare an incident\", \"incident severity P1 P2 P3 P4\", \"assign Incident Commander\", \"IC role assignment\", \"Technical Lead\", \"Communications Lead\", \"Scribe role\", \"P1 escalation matrix\", \"vendor TAC engagement\", \"draft executive update for incident\", \"customer-facing incident communication\", \"regulatory notification for breach\", \"status page update\", \"bridge call agenda\", \"run a blameless post-mortem\", \"5-whys RCA\", \"contributing factor categorisation process people technology\", \"action item disposition fix mitigate accept transfer\", \"incident metrics MTTD MTTI MTTR\", \"enhanced monitoring period after resolution\", \"phased recovery for multi-layer incident\", \"back-out plan execution\", \"incident closure notification\", \"schedule post-incident review\", \"post-mortem within 72 hours\", \"incident report template NIST\", \"severity classification matrix data risk\", \"executive notification within 30 minutes P1\". Six-step procedure (detection and classification, triage and escalation, investigation coordination, communication management, resolution and recovery, post-incident review). Three threshold tables (Severity Classification Matrix P1-P4 with user impact / service impact / data risk / response SLA columns; Escalation and Role Matrix with IC / Tech Lead / Comms Lead / Scribe assignment per severity; Enhanced Monitoring Duration with monitoring period / alert threshold reduction / re-escalation trigger per severity). Two decision trees (Incident Severity Assignment with service-availability and data-exposure branches; Escalation Decision with role-assignment and vendor-engagement routing). Four-role model: Incident Commander (owns end-to-end, makes escalation decisions), Technical Lead (coordinates diagnostics, synthesises findings), Communications Lead (drafts stakeholder notifications, manages status page), Scribe (maintains real-time timeline and bridge call decision log). Vendor-agnostic process skill; no platform tags. Audience-specific communication templates (executive / technical / customer / regulatory) live in `references/communication-templates.md`. 5-whys facilitation, fishbone diagram, contributing-factor categorisation, four-disposition action-item model, post-mortem document structure live in `references/rca-framework.md`. Scoped to the organisational coordination layer; for network-level evidence collection and forensic analysis use `incident-response-network`; for generic devops on-call discipline use `oncall-runbooks`; for log evidence retrieval use `siem-log-analysis` or `network-log-analysis`. Customised from vahagn-madatyan/netsec-skills-suite (Apache-2.0); references kept as-is for progressive disclosure with em-dash and US-to-UK spelling cleanup applied."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Incident Response Lifecycle

Structured process management for security incidents from detection through post-incident review, following the NIST 800-61 lifecycle. This skill covers the organisational coordination layer: severity classification, escalation, role assignment, stakeholder communication, recovery coordination, and root cause analysis. It does not cover technical evidence collection, device forensics, or containment execution; use `incident-response-network` for network-level evidence gathering and forensic analysis, `oncall-runbooks` for generic devops incident discipline, and `siem-log-analysis` or `network-log-analysis` for log evidence retrieval.

The procedure follows the operational lifecycle shape: detect and classify the incident, triage and escalate to the right people, coordinate the investigation across teams, manage communications to all audiences, drive resolution and recovery, then conduct a blameless post-incident review.

See `references/communication-templates.md` for notification templates by audience and severity level. See `references/rca-framework.md` for the 5-whys methodology, fishbone diagram guidance, and post-mortem document structure.

> **Skill marker**: When applying this skill, begin your reply with `[skill: incident-response-lifecycle]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the organisation's severity-criteria policy, contact directory, comms-channel inventory, and any existing IR-process customisations before declaring an incident or facilitating a post-mortem. Only ask the user for information not already covered or specific to this incident.

Before declaring an incident or starting the process, understand:

1. **Severity criteria policy**
   - Does the organisation use P1-P4 or a different ladder (SEV1-4, S0-S3)? Map onto P1-P4 if different.
   - What are the local thresholds for "complete outage", "data breach confirmed", "more than 50% of users affected"? The threshold tables in this skill provide a reference framework; the organisation's customisations override.
   - Who has authority to declare a P1? Is the on-call engineer empowered, or does it need a manager sign-off?

2. **Contact directory readiness**
   - Current on-call rosters per team (IC pool, Tech Lead pool, Comms Lead pool, Scribe pool)
   - Escalation contacts for engineering management and executive on-call
   - Vendor TAC numbers and support contracts (per critical vendor)
   - Regulatory notification contacts (per applicable jurisdiction and framework: GDPR DPA, HIPAA OCR, PCI-DSS QSA, financial regulators)
   - Customer-success / account-management contacts for VIP customer notification

3. **Communication channels inventory**
   - Bridge call infrastructure (Zoom room, Google Meet, Teams, dedicated VoIP bridge): is the link stable and does the team know how to join?
   - Status page URL and update authority (who can publish; what's the approval gate for a customer-facing update?)
   - Incident-tracking system (Jira, Linear, ServiceNow, PagerDuty-tied ticketing): where do incident records and action items live?
   - Email distribution lists per stakeholder group (executive, technical, customer, regulatory)

## When to use

- **Service-affecting incident declared**: a P1 or P2 event requires formal incident management with role assignment and communications
- **Escalation decision needed**: determining who to notify at what severity level and when to engage vendor support or management
- **Multi-team coordination required**: investigation spans network, security, application, and infrastructure teams needing a single command structure
- **Customer or regulatory notification required**: incident has external communication obligations (SLA breach, data exposure, regulatory reporting)
- **Post-incident review facilitation**: scheduling, structuring, and running blameless post-mortems with 5-whys root cause analysis
- **Incident metrics reporting**: collecting MTTD, MTTI, MTTR, and recurrence data for continuous improvement

## Do NOT use this skill for

- Network-level evidence collection (packet captures, flow records, ARP / MAC preservation, containment verification); use `incident-response-network` for the technical evidence layer
- Generic devops on-call runbook authoring or routine SEV3 / SEV4 handling that does not need formal NIST 800-61 process management; use `oncall-runbooks` for the devops-flavour generic discipline
- Log evidence retrieval (SIEM queries, raw syslog correlation, Graylog stream analysis); use `siem-log-analysis`, `network-log-analysis`, or `graylog-log-investigation`
- Routine change management (planned deploys, maintenance windows, vendor upgrades not triggered by an incident); use the change-management process directly
- Endpoint or application incident handling outside the network scope; use the appropriate domain-specific IR process

## Prerequisites

- **Incident management authority**: the person initiating this process must have authorisation to declare incidents and assign roles within the organisation. The IC role specifically requires authority to make escalation and communication decisions on behalf of the organisation.
- **Contact directory**: current on-call rosters, escalation contacts for management, vendor TAC numbers, and regulatory notification contacts must be accessible. See Initial Assessment for the categories.
- **Communication channels**: bridge call infrastructure (conference line or collaboration tool), status page access, and email distribution lists for each stakeholder group must be established and tested before they are needed.
- **Incident tracking system**: a ticketing system to record the incident, track actions, and maintain the timeline of events. The same system holds action items from the post-mortem (see Step 6); do not let action items live in separate documents.
- **Defined severity criteria**: organisational agreement on what constitutes P1 through P4 severity (see Threshold Tables below for a reference framework; organisation-specific customisations override).

## Procedure

Follow these six steps in sequence. Steps 3 and 4 run in parallel once roles are assigned; investigation coordination and communication management proceed simultaneously. Each step references templates from `references/communication-templates.md` and methodology from `references/rca-framework.md` where applicable.

### Step 1: Detection and classification

Classify the incident by severity, type, and scope to determine the appropriate response level.

**Severity assignment**: apply the P1-P4 taxonomy from the Threshold Tables section. Base severity on the highest-impact criterion met. When multiple criteria apply at different levels, the highest governs.

**Incident type classification**: categorise as outage (service unavailable), degradation (reduced capacity), security (unauthorised access or data exposure), or data loss (corruption or deletion). The type drives the investigation track (in Step 3) and the regulatory notification path (in Step 4).

**Scope determination**: assess whether the incident affects a single device, a network segment, an entire site, or multiple sites. Scope drives staffing, communication breadth, and recovery complexity.

**Initial impact assessment**: estimate affected user count, impacted services and their business criticality, data at risk, and revenue impact per hour. Record estimates in the incident ticket. Update estimates as scope clarifies during Step 2.

### Step 2: Triage and escalation

Assign roles, notify stakeholders, and set response timeline expectations based on the severity classification from Step 1.

**Role assignment**: every P1 or P2 incident needs four named roles:
- **Incident Commander (IC)**: owns the incident end-to-end and makes escalation decisions. Single point of authority. Should not also be doing technical investigation (use a separate Tech Lead for that).
- **Technical Lead**: coordinates diagnostics, synthesises findings from parallel investigation tracks (Step 3), and reports a single coherent technical status on each bridge call.
- **Communications Lead**: drafts stakeholder notifications, manages the status page, and shields the IC and Tech Lead from comms-overhead during active investigation.
- **Scribe**: maintains the real-time timeline of events (who did what when), records bridge call decisions, and produces the timeline artefact that feeds Step 6.

For P3, IC and Technical Lead may be combined into a single Tech Lead role; Comms Lead and Scribe optional. P4 uses normal operations workflows; no formal role assignment.

**Escalation matrix execution**: notify by severity:
- **P1**: all four roles plus engineering management, VP / director on-call, vendor TAC if vendor equipment is involved, executive notification within 30 minutes.
- **P2**: all four roles plus engineering management within 1 hour.
- **P3**: Technical Lead plus team lead within 4 hours.
- **P4**: assigned engineer via normal ticket queue.

**Response timeline expectations**:
- **P1**: bridge in 15 minutes, first update in 30 minutes, then every 30 minutes.
- **P2**: bridge in 30 minutes, first update in 1 hour, then every 2 hours.
- **P3**: initial assessment in 4 hours, daily updates.
- **P4**: acknowledgement within 1 business day.

**Vendor engagement criteria**: engage vendor TAC when the incident involves hardware failure, software defects requiring patches, or when internal triage has not identified root cause within the severity time window.

### Step 3: Investigation coordination

Coordinate the technical investigation across teams and evidence sources. For network-level evidence collection (device state, routing tables, interface data, log retrieval, packet captures, ARP / MAC preservation), reference the `incident-response-network` skill; this step focuses on organising the investigation, not executing forensic commands.

**Evidence collection tasking**: assign team members to collect evidence from relevant domains:
- Network devices via `incident-response-network` procedures
- SIEM events via `siem-log-analysis` queries (or raw syslog via `network-log-analysis` if no SIEM)
- Application logs via the application-specific log-analysis skill
- Infrastructure metrics via `grafana-dashboards` / `prometheus-configuration`
- Security tooling alerts via the SIEM Offence / event pipeline

Each assignee reports findings to the Technical Lead. The Technical Lead synthesises into a single status for each bridge call.

**Parallel investigation streams**: for complex incidents, run multiple investigation threads simultaneously. Common parallel tracks:
1. **Symptom analysis**: what is failing and for whom
2. **Change correlation**: what changed recently (deployments, config modifications, maintenance)
3. **External factors**: upstream provider issues, DDoS, DNS resolution failures

**Hypothesis tracking**: maintain a running list of hypotheses with current status (investigating, confirmed, ruled out). Each hypothesis should have an owner and a validation method. Update the list on every bridge call.

**Timeline of events (ToE)**: the Scribe maintains a running chronological log of when events occurred, when they were detected, what actions were taken, and what was discovered. The ToE becomes the foundation for the post-incident review in Step 6.

**Subject matter expert engagement**: when investigation stalls or enters an unfamiliar domain, escalate to specialists. Define clear handoff: what has been tried, what data is available, and what specific question needs answering.

### Step 4: Communication management

Manage stakeholder communications throughout the incident. Use the templates in `references/communication-templates.md` for consistent messaging across audiences.

**Stakeholder notification by audience**:
- **Executive summary**: business impact, estimated resolution, customer exposure. No technical detail.
- **Technical detail**: root cause hypothesis, diagnostics, remediation plan. Delivered on bridge call.
- **Customer-facing**: service impact, workaround if available, estimated resolution. Via status page.
- **Regulatory**: formal notification per compliance framework when required (GDPR 72-hour rule, HIPAA 60-day rule, PCI-DSS immediate notification, financial sector per jurisdiction).

Use templates from `references/communication-templates.md`. The templates are audience-tuned; do not send a technical-track update to a non-technical audience or vice versa.

**Status update cadence**: follow severity-based cadence from Step 2. Each update includes:
- Current status
- Progress since last update
- Next planned action
- Revised time-to-resolution estimate

**Bridge call management**: the IC runs calls with a fixed agenda:
1. Technical status from Tech Lead
2. Communication status from Comms Lead
3. Hypothesis updates
4. Decisions needed
5. Action items with owners and deadlines

Keep calls focused; park side discussions as action items. The Scribe captures decisions in the ToE.

**External notification requirements**: track regulatory reporting deadlines, law enforcement notification when criminal activity is suspected, customer SLA breach notification per contractual terms, and vendor escalation for ongoing support.

### Step 5: Resolution and recovery

Drive service restoration through validated recovery steps with monitoring to confirm the fix holds.

**Recovery validation criteria**: before declaring resolved, confirm:
1. Service health checks return normal for all affected components
2. Monitoring dashboards show green for at least 15 minutes (P1) or 30 minutes (P2)
3. No new related alerts during observation
4. Affected users confirm restoration (sample check for large populations)

Cross-reference `completion-gate` Layer 3 for the post-checks discipline (no claim of "resolved" without fresh verification evidence in this turn).

**Phased restoration**: for multi-layer network incidents, restore in order: core infrastructure then distribution layer then access layer then end-to-end verification. Verify each phase before proceeding. Do not restore all layers simultaneously; cascading failures during recovery are worse than a phased approach.

**Back-out plan execution**: if the fix causes new issues, execute the pre-defined rollback. Every remediation action should have a documented rollback method before execution. Use `change-verification` (when adopted) for the rollback-readiness check.

**Enhanced monitoring period**: maintain heightened monitoring after resolution:
- **P1**: 24 hours
- **P2**: 12 hours
- **P3**: through the next business day

This means reduced alert thresholds on affected systems, active watch by on-call, and immediate re-escalation if symptoms recur.

**Incident closure**: send closure notification to all stakeholders (template in `references/communication-templates.md`). Update the ticket with resolution summary, total duration, and final impact. Schedule the post-incident review.

### Step 6: Post-incident review

Conduct a blameless post-incident review to identify root cause, contributing factors, and improvement actions. See `references/rca-framework.md` for the full methodology including 5-whys facilitation guide, fishbone diagram template, and worked examples.

**Scheduling**: hold the post-mortem within 72 hours of incident resolution while details are fresh. Invite all incident participants plus relevant stakeholders. Send the invitation using the template in `references/communication-templates.md`.

**5-whys root cause analysis**: apply iteratively; for each "why" answer, ask "why" again until reaching a systemic root cause (typically 3-5 iterations). See `references/rca-framework.md` for worked examples and facilitation guidance. The blameless-culture iron rule applies: the answer to "why" is a system condition, never a person.

**Contributing factor categorisation**: classify each contributing factor as one of three categories:
- **Process** (missing runbook, unclear escalation path, gap in change management)
- **People** (training gap, staffing shortage, communication breakdown)
- **Technology** (monitoring gap, single point of failure, software defect)

This categorisation guides the type of remediation action needed.

**Action item classification**: assign each action item one of four dispositions:
- **Fix**: eliminate the root cause
- **Mitigate**: reduce likelihood or impact
- **Accept**: risk is within tolerance; document rationale
- **Transfer**: assign to another team or vendor

Every fix or mitigate action must have an owner, due date, and verification method. Track in the same incident-tracking system as the incident, not in a separate document.

**Incident metrics**: collect and record:
- **MTTD** (Mean Time to Detect): time from event occurrence to detection
- **MTTI** (Mean Time to Investigate): time from detection to root cause identified
- **MTTR** (Mean Time to Resolve): time from detection to resolution
- Total incident duration
- Number of customers affected
- Whether this is a recurrence of a previous incident

Track these metrics over time to measure improvement trends. Recurring root causes signal a systemic gap; escalate via the post-mortem action items.

## Threshold tables

### Severity classification matrix

| Severity | User Impact | Service Impact | Data Risk | Response SLA |
|----------|-----------|----------------|-----------|-------------|
| **P1 Critical** | More than 50% of users or all VIP users | Complete outage of revenue-generating service | Confirmed data breach or loss | Bridge in 15 min, updates every 30 min |
| **P2 High** | 10-50% of users affected | Major degradation or redundancy loss on critical path | Suspected data exposure | Bridge in 30 min, updates every 2 hr |
| **P3 Medium** | Less than 10% of users, workaround exists | Partial degradation, non-critical service | No data risk identified | Assessment in 4 hr, updates daily |
| **P4 Low** | Minimal or no user impact | Cosmetic, non-production, or fully redundant | None | Ack in 1 business day |

### Escalation and role matrix

| Severity | Incident Commander | Technical Lead | Comms Lead | Scribe | Management | Executive |
|----------|-------------------|---------------|------------|--------|-----------|-----------|
| **P1** | Required | Required | Required | Required | Immediate | Within 30 min |
| **P2** | Required | Required | Required | Optional | Within 1 hr | If SLA breached |
| **P3** | Combined with Tech Lead | Required | Optional | No | Within 4 hr | No |
| **P4** | No | Assigned engineer | No | No | Normal reporting | No |

### Enhanced monitoring duration

| Severity | Monitoring Period | Alert Threshold | Re-escalation Trigger |
|----------|------------------|----------------|-----------------------|
| **P1** | 24 hours | Reduced by 20% | Any recurrence symptom |
| **P2** | 12 hours | Reduced by 10% | Same failure signature |
| **P3** | Next business day | Normal thresholds | Identical alert |
| **P4** | None | Normal | Normal process |

## Decision trees

### Incident severity assignment

```
Event detected or reported
├── Is the service completely unavailable?
│   ├── Yes → Is it a revenue-generating or safety-critical service?
│   │   ├── Yes → P1 Critical
│   │   └── No → P2 High
│   └── No → Service is partially available
│       ├── Are more than 10% of users affected without workaround?
│       │   ├── Yes → P2 High
│       │   └── No → Is there a workaround available?
│       │       ├── Yes → P3 Medium
│       │       └── No, but fewer than 10% of users → P3 Medium
│       └── Is this a non-production or cosmetic issue?
│           └── Yes → P4 Low
├── Is there confirmed or suspected data exposure?
│   ├── Confirmed breach → P1 Critical (regardless of service status)
│   └── Suspected exposure → P2 High minimum
└── Has redundancy been lost on a critical path?
    ├── Yes, no failover remaining → P2 High
    └── Yes, failover still available → P3 Medium
```

### Escalation decision

```
Severity assigned
├── P1 or P2?
│   ├── Yes → Assign all four roles immediately
│   │   ├── Is vendor equipment involved in the failure?
│   │   │   ├── Yes → Open vendor TAC case immediately
│   │   │   └── No → Internal investigation first
│   │   └── Has root cause been identified within time window?
│   │       ├── P1: not identified within 30 min → Escalate to next tier
│   │       └── P2: not identified within 2 hr → Escalate to next tier
│   └── P3 or P4?
│       ├── P3 → Assign Technical Lead, monitor for escalation
│       │   └── Impact worsening? → Re-classify severity upward
│       └── P4 → Normal ticket queue, no escalation
└── At any point: if scope expands beyond initial classification
    └── Re-evaluate severity from Step 1, escalate if needed
```

## Report template

```
INCIDENT REPORT
=====================================
Incident ID:          [ticket / tracking number]
Severity:             [P1 / P2 / P3 / P4]
Incident Commander:   [name]
Duration:             [detection time] to [resolution time] ([total hours])
Status:               [Resolved / Monitoring / Under Review]

IMPACT SUMMARY:
  Users Affected:     [count or percentage]
  Services Affected:  [list of impacted services]
  Revenue Impact:     [estimated or confirmed]
  Data Impact:        [none / suspected / confirmed; description]

TIMELINE OF EVENTS:
| # | Time (UTC) | Event | Actor | Notes |
|---|-----------|-------|-------|-------|
| 1 | [time] | [event description] | [person / system] | [context] |

ROOT CAUSE:
  Category:           [Process / People / Technology]
  Root Cause:         [description from 5-whys analysis]
  Contributing Factors:
    - [factor 1; category]
    - [factor 2; category]

RESOLUTION:
  Fix Applied:        [description of what resolved the incident]
  Validated By:       [how resolution was confirmed]
  Back-out Available: [yes / no; description]

METRICS:
  MTTD:               [time from occurrence to detection]
  MTTI:               [time from detection to root cause identified]
  MTTR:               [time from detection to resolution]
  Recurrence:         [yes / no; reference to prior incident if yes]

ACTION ITEMS:
| # | Action | Type | Owner | Due Date | Status |
|---|--------|------|-------|----------|--------|
| 1 | [action] | [Fix / Mitigate / Accept / Transfer] | [name] | [date] | [status] |

POST-MORTEM STATUS:
  Scheduled:          [date / time or "pending"]
  Attendees:          [roles invited]
  Document Location:  [link to post-mortem document]
```

## Common failure modes

### Severity disagreement between teams

**Symptom:** teams classify the same incident at different severity levels, causing confusion about response urgency.

**Resolution:** the IC makes the final determination using the Threshold Tables criteria. The highest applicable severity governs. Document rationale in the ticket. If the IC is not yet assigned, the first responder sets initial severity and the IC may adjust on assignment.

### Escalation fatigue and alert noise

**Symptom:** frequent P1 / P2 declarations for issues that resolve quickly, eroding trust in severity classification.

**Resolution:** review severity criteria quarterly. Track the false-positive rate (incidents downgraded after initial classification). If P1 downgrade rate exceeds 30%, tighten P1 criteria. Ensure P3 / P4 incidents are not over-classified.

### Post-mortem action items not completed

**Symptom:** action items accumulate but are not completed, leading to recurring incidents from known causes.

**Resolution:** assign every action item an owner and due date at the review. Track completion in the incident system, not separate documents. Review open items in weekly standups. Escalate overdue items to management and report completion rates alongside MTTD / MTTR.

### Communication gaps during extended incidents

**Symptom:** status updates become infrequent during long incidents (more than 4 hours), leaving stakeholders uninformed.

**Resolution:** the Communications Lead maintains cadence regardless of investigation progress. If no new findings exist, state that explicitly in the update. For incidents exceeding 8 hours, rotate the Comms Lead role to prevent fatigue.

### Incident recurrence after resolution

**Symptom:** the same incident recurs after being marked resolved.

**Resolution:** check whether prior post-mortem action items were completed. If yes, the root cause analysis was incomplete; reconvene with broader scope. If not, escalate the completion failure. Tag the new incident as a recurrence and increase severity by one level to reflect accumulated impact.

### IC and Technical Lead combined at P1

**Symptom:** a single person tries to run the bridge call AND do technical investigation; coordination degrades, decisions slip, comms lag.

**Resolution:** split the roles immediately. At P1, the IC focuses on decisions and escalation; the Technical Lead focuses on diagnostics. If the on-call pool is too small to staff both, the IC role takes precedence and the Technical Lead role gets filled from the second-on-call pool or by escalating to the on-call manager.

## Cross-references

- `incident-response-network`: network-forensics technical evidence arm. Step 3 of this skill explicitly hands evidence collection to it. The two skills are complementary: lifecycle handles process, network handles technical evidence; together they cover a complete security incident.
- `oncall-runbooks`: devops-flavour sibling. Covers SEV1-4 classification, 9-section runbook structure, postmortem with 5-whys, on-call handoff. This skill (`incident-response-lifecycle`) is the security-IR-flavour NIST 800-61 process complement; the two divide cleanly (devops generic vs security-IR formal process).
- `siem-log-analysis`: SIEM-equipped log evidence retrieval. Step 3 evidence collection tasking includes SIEM query work; this skill points at siem-log-analysis for the technical execution.
- `network-log-analysis`: no-SIEM raw-syslog evidence retrieval. Step 3 alternative when no SIEM platform is available.
- `humanise-comms`: every stakeholder communication in Step 4 follows the humanise-comms voice baseline. The templates in `references/communication-templates.md` provide structure; humanise-comms shapes tone. Especially important for executive and customer-facing audiences where corporate-padded language undermines trust.
- `utc-timestamps`: every timeline entry, metric, and report timestamp is UTC. The Scribe's ToE in Step 3 enforces this; the metrics in Step 6 (MTTD / MTTI / MTTR) calculate from UTC timestamps.
- `systematic-debugging`: the Phase 1 evidence-gathering at component boundaries that this skill's Step 3 organises across teams. Hypothesis tracking in Step 3 IS the systematic-debugging hypothesis-and-minimal-test phase, scaled to a multi-team incident.
- `completion-gate` Layer 3: the recovery validation criteria in Step 5 ARE the completion-gate Layer 3 iron law applied to incident recovery. No claim of "resolved" without fresh verification evidence in this turn.
- `secrets-hygiene`: regulatory and customer-facing comms must not leak credentials, internal IPs that disclose topology, or session tokens. The Communications Lead in Step 4 audits before publishing.
- `cite-sources`: post-incident reports that reference external indicators (CVEs, vendor advisories, threat-intel feeds, regulatory frameworks) cite with date and identifier.
- `plan-time-tooling`: the `engineering:incident-response` mandatory trigger fires when this skill loads; the decision matrix routing covers it.
- `multi-vendor-network-ops`: the 9-element response contract on production-impacting actions taken during recovery (Step 5 fixes that touch production network state).

## Red flags

- **Assign IC and Tech Lead to same person at P1.** Single-person bottleneck. The IC needs to be running the bridge and making decisions while the Tech Lead is heads-down in diagnostics. Split the roles even if it means pulling from second-on-call.
- **Skip the Scribe role at P1.** Without a Scribe, the timeline of events is reconstructed from memory in the post-mortem (which is wrong by then). The Scribe is the source of truth for what happened when. P1 always has a Scribe.
- **5-whys ending at a person rather than a system condition.** "Why did the deploy fail? Because Bob pushed bad code." That is the wrong answer. The right answer continues: "Why was bad code able to ship? No staging environment. Why no staging? Cost-cut three quarters ago." The blameless-culture iron rule says the answer is always a system condition. If the answer is a person's name, ask why again.
- **Post-mortem held more than 7 days after resolution.** Memory decay. Action items become "we should probably look into X" instead of "X was the cause; here's the fix". Schedule within 72 hours; the 7-day mark is the late-but-still-useful cutoff.
- **Action items without owners and due dates.** Action items without owners get ignored; action items without due dates never finish. Every fix or mitigate action gets both at the review. Track in the incident system.
- **Send executive update with raw technical detail.** Executives need business impact, estimated resolution, customer exposure. Technical detail confuses (and erodes confidence). Use the executive-summary template from `references/communication-templates.md`.
- **Send customer-facing comms with internal hypothesis language.** Customers should see service impact, workaround, ETA. Internal hypothesis ("we suspect a BGP peering issue with our upstream provider") leaks debugging language and triggers customer-side speculation. Use the customer-facing template.
- **Declare resolved before enhanced monitoring period elapses.** Recovery validation criteria in Step 5 specify monitoring duration; if symptoms recur during that window, the original "resolved" claim was wrong. Re-open the incident, do not minimise.
- **Conflate this skill with `incident-response-network`.** This skill is process management (severity classification, role assignment, comms, post-mortem). `incident-response-network` is technical evidence (packet captures, ARP / MAC preservation, containment verification). The two are complementary; do not try to do forensic evidence work from this skill.
- **Send regulatory notification draft for review by the IC who is also in the bridge call.** The IC is overloaded; regulatory notifications need a separate review path (legal, compliance, executive sign-off) outside the active incident response. Pre-stage the review path in Initial Assessment so it can fire when needed.

## Bottom line

NIST 800-61 incident-response process is a six-step procedure: detect and classify, triage and escalate (assign four roles: IC / Tech Lead / Comms Lead / Scribe), coordinate investigation across teams, manage communications by audience (executive / technical / customer / regulatory), drive resolution with validated recovery, then conduct a blameless post-mortem with 5-whys RCA. Vendor-agnostic; process not tooling. Every P1 / P2 incident gets four roles staffed; every post-mortem schedules within 72 hours; every action item has an owner and due date; every blame answer continues with "why" until reaching a system condition. Hand off technical evidence to `incident-response-network`; hand off devops-flavour SEV1-4 generic discipline to `oncall-runbooks`; hand off log retrieval to `siem-log-analysis` or `network-log-analysis`.
